-- Copyright (c) 2025 Augment
-- MIT License - See LICENSE.md for full terms

-- Custom LSP client implementation for the Augment plugin

local log = require('augment_log')
local M = {}

-- Client state
local client_id = nil
local initialized = false
local capabilities = nil
local file_watchers = {}

-- Notification handlers for LSP messages
local notification_handlers = {}

-- Response handlers for LSP requests
local response_handlers = {}

-- Configuration
local config = {
  cmd = nil,             -- Command to start the server
  autostart = true,      -- Whether to start the server automatically
  root_dir = nil,        -- Root directory for the server
  workspace_folders = {} -- Workspace folders to sync
}

-- Set up custom LSP capabilities
local function setup_capabilities()
  local default_capabilities = vim.lsp.protocol.make_client_capabilities()
  
  -- Add custom capabilities needed for Augment
  default_capabilities.textDocument.completion = {
    dynamicRegistration = false,
    completionItem = {
      snippetSupport = true,
      commitCharactersSupport = true,
      documentationFormat = { "markdown", "plaintext" },
      deprecatedSupport = true,
      preselectSupport = true
    },
    contextSupport = true
  }
  
  -- Add custom augment capabilities
  default_capabilities.augment = {
    chat = true,
    suggestions = true,
    version = require('augment/version').version()
  }
  
  -- Return the capabilities
  return default_capabilities
end

-- Register a notification handler
function M.register_notification_handler(method, callback)
  notification_handlers[method] = callback
  log.debug("Registered notification handler for " .. method)
  return true
end

-- Register a response handler
function M.register_response_handler(method, callback)
  response_handlers[method] = callback
  log.debug("Registered response handler for " .. method)
  return true
end

-- Get the command to start the language server
function M.get_server_command()
  -- If already configured, use that
  if config.cmd then
    return config.cmd
  end
  
  -- Check for user configuration
  if vim.g.augment_job_command then
    return vim.g.augment_job_command
  end
  
  -- Use default configuration
  local node_command = vim.g.augment_node_command or 'node'
  local runtime_path = vim.fn.resolve(vim.fn.expand('<sfile>:p:h:h:h') .. '/dist/server.js')
  
  log.info("Using server command: " .. node_command .. " " .. runtime_path)
  return {node_command, runtime_path, '--stdio'}
end

-- Check compatibility with the Node.js runtime
function M.check_runtime_compatibility()
  local command = M.get_server_command()
  if not command or #command == 0 then
    log.error("Failed to determine the Augment runtime command")
    return false
  end
  
  -- Check if the runtime exists
  local runtime = command[1]
  if vim.fn.executable(runtime) ~= 1 then
    log.error("The Augment runtime (" .. runtime .. ") was not found")
    return false
  end
  
  -- Check the runtime version
  local result = vim.fn.system({runtime, '--version'})
  if vim.v.shell_error ~= 0 then
    log.warn("Failed to determine runtime version: " .. result)
    return true -- Continue anyway
  end
  
  -- Parse version
  local version_match = result:match('v(%d+)%.%d+%.%d+')
  if not version_match then
    log.warn("Failed to parse runtime version: " .. result)
    return true -- Continue anyway
  end
  
  local major_version = tonumber(version_match)
  if not major_version or major_version < 19 then
    log.error("Unsupported runtime version: " .. result .. ". Please use Node.js version 19 or later.")
    return false
  end
  
  log.info("Using runtime (Node.js) version: " .. result)
  return true
end

-- Configure workspace folders
function M.configure_workspace_folders()
  -- Get workspace folders from configuration
  local workspace_folders = vim.g.augment_workspace_folders or {}
  if type(workspace_folders) == 'string' then
    workspace_folders = {workspace_folders}
  end
  
  -- Convert to LSP format
  local folders = {}
  for _, folder in ipairs(workspace_folders) do
    local expanded = vim.fn.expand(folder)
    if vim.fn.isdirectory(expanded) == 1 then
      table.insert(folders, {
        uri = vim.uri_from_fname(expanded),
        name = vim.fn.fnamemodify(expanded, ':t')
      })
    else
      log.warn("Workspace folder does not exist: " .. expanded)
    end
  end
  
  config.workspace_folders = folders
  return folders
end

-- Set up custom LSP handlers
local function setup_handlers()
  local handlers = {}
  
  -- Default handler for notifications
  handlers['window/logMessage'] = function(_, params, _)
    local levels = {
      [1] = log.error,
      [2] = log.warn,
      [3] = log.info,
      [4] = log.debug
    }
    
    local logger = levels[params.type] or log.info
    logger("LSP: " .. params.message)
  end
  
  -- Handle diagnostics
  handlers['textDocument/publishDiagnostics'] = function(_, params, _)
    local ok, diagnostics = pcall(require, 'augment/diagnostics')
    if ok then
      diagnostics.handle_diagnostics(params)
    else
      log.error("Failed to load diagnostics module: " .. tostring(diagnostics))
    end
  end
  
  -- Add custom handlers for Augment-specific methods
  for method, handler in pairs(notification_handlers) do
    handlers[method] = function(_, params, _)
      -- Call in protected mode
      local ok, err = pcall(handler, params)
      if not ok then
        log.error("Error in notification handler for " .. method .. ": " .. tostring(err))
      end
    end
  end
  
  return handlers
end

-- Create a custom request handler for a method
local function create_request_handler(method)
  return function(err, result)
    if err then
      log.error("Error in LSP request " .. method .. ": " .. vim.inspect(err))
      return
    end
    
    -- Find the handler for this method
    local handler = response_handlers[method]
    if handler then
      local ok, handler_err = pcall(handler, result)
      if not ok then
        log.error("Error in response handler for " .. method .. ": " .. tostring(handler_err))
      end
    else
      log.debug("No handler for response: " .. method)
    end
  end
end

-- Start the LSP client
function M.start_client()
  if client_id then
    log.info("LSP client already started")
    return client_id
  end
  
  -- Check runtime compatibility
  if not M.check_runtime_compatibility() then
    log.error("Runtime compatibility check failed")
    return nil
  end
  
  -- Get workspace folders
  local workspace_folders = M.configure_workspace_folders()
  
  -- Set up capabilities
  capabilities = setup_capabilities()
  
  -- Get command to start server
  local cmd = M.get_server_command()
  
  -- Set up LSP client configuration
  local client_config = {
    name = 'augment',
    cmd = cmd,
    capabilities = capabilities,
    handlers = setup_handlers(),
    init_options = {
      editor = 'nvim',
      vimVersion = tostring(vim.version()),
      pluginVersion = require('augment/version').version()
    },
    root_dir = vim.fn.getcwd(),
    workspace_folders = workspace_folders,
    flags = {
      allow_incremental_sync = true,
      debounce_text_changes = 150
    }
  }
  
  -- Start the client
  log.info("Starting LSP client")
  client_id = vim.lsp.start_client(client_config)
  
  if not client_id then
    log.error("Failed to start LSP client")
    return nil
  end
  
  log.info("LSP client started with ID: " .. client_id)
  
  -- Mark as initialized
  initialized = true
  
  -- Automatically attach to all buffers
  if config.autostart then
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) then
        M.attach_buffer(bufnr)
      end
    end
    
    -- Set up autocommand to attach to new buffers
    vim.api.nvim_create_autocmd("BufEnter", {
      callback = function(args)
        M.attach_buffer(args.buf)
      end
    })
  end
  
  return client_id
end

-- Attach the LSP client to a buffer
function M.attach_buffer(bufnr)
  if not client_id then
    log.debug("No LSP client to attach")
    return false
  end
  
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  -- Only attach to real files
  local filename = vim.api.nvim_buf_get_name(bufnr)
  if filename == '' or vim.fn.filereadable(filename) == 0 then
    return false
  end
  
  -- Check if already attached
  local clients = vim.lsp.get_active_clients({bufnr = bufnr, name = 'augment'})
  if #clients > 0 then
    log.debug("Buffer " .. bufnr .. " already attached to LSP client")
    return true
  end
  
  -- Attach the client
  local ok = vim.lsp.buf_attach_client(bufnr, client_id)
  if not ok then
    log.error("Failed to attach buffer " .. bufnr .. " to LSP client")
    return false
  end
  
  log.debug("Attached buffer " .. bufnr .. " to LSP client")
  return true
end

-- Get workspace folders
function M.get_workspace_folders()
  return config.workspace_folders
end

-- Send a notification to the LSP server
function M.notify(method, params)
  if not client_id then
    log.error("No LSP client to send notification")
    return false
  end
  
  local client = vim.lsp.get_client_by_id(client_id)
  if not client then
    log.error("LSP client not found")
    return false
  end
  
  -- Send notification
  client.notify(method, params)
  log.debug("Sent notification: " .. method)
  return true
end

-- Send a request to the LSP server
function M.request(method, params, callback)
  if not client_id then
    log.error("No LSP client to send request")
    return false
  end
  
  local client = vim.lsp.get_client_by_id(client_id)
  if not client then
    log.error("LSP client not found")
    return false
  end
  
  -- Create callback if not provided
  local cb = callback or create_request_handler(method)
  
  -- Send request
  client.request(method, params, cb)
  log.debug("Sent request: " .. method)
  return true
end

-- Check if the client is running
function M.is_running()
  if not client_id then
    return false
  end
  
  local client = vim.lsp.get_client_by_id(client_id)
  return client ~= nil
end

-- Stop the LSP client
function M.stop_client()
  if not client_id then
    log.info("No LSP client to stop")
    return false
  end
  
  local client = vim.lsp.get_client_by_id(client_id)
  if not client then
    log.error("LSP client not found")
    client_id = nil
    initialized = false
    return false
  end
  
  -- Stop the client
  client.stop()
  log.info("Stopped LSP client")
  
  -- Reset state
  client_id = nil
  initialized = false
  return true
end

-- Get client ID
function M.get_client_id()
  return client_id
end

-- Get client state
function M.get_state()
  return {
    client_id = client_id,
    initialized = initialized,
    workspace_folders = config.workspace_folders,
    capabilities = capabilities
  }
end

-- Configure the LSP client
function M.configure(opts)
  -- Update configuration
  if opts.cmd then config.cmd = opts.cmd end
  if opts.autostart ~= nil then config.autostart = opts.autostart end
  if opts.root_dir then config.root_dir = opts.root_dir end
  
  log.info("LSP client configured")
  return true
end

-- Return the module
return M