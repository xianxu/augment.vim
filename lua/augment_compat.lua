-- Copyright (c) 2025 Augment
-- MIT License - See LICENSE.md for full terms

-- This is a compatibility module that bridges between VimScript and the Lua implementation

-- Use our dedicated logger or fall back to simple logging if it fails
local log
local function safe_require(module)
  local ok, result = pcall(require, module)
  if ok then return result else return nil end
end

log = safe_require("augment_log")

-- Function to log if our logger is available, otherwise use echo
local function log_info(message, echo)
  if log then
    log.info(message, echo)
  elseif echo then
    vim.schedule(function()
      vim.api.nvim_echo({{"Augment: " .. message, "Normal"}}, false, {})
    end)
  end
end

local function log_error(message, echo)
  if log then
    log.error(message, echo)
  elseif echo then
    vim.schedule(function()
      vim.api.nvim_echo({{"Augment Error: " .. message, "ErrorMsg"}}, false, {})
    end)
  end
end

-- Create our module
local M = {}

-- Custom notification handlers table
local notification_handlers = {}

-- Register a custom handler for notifications
function M.register_handler(method, handler)
  if type(handler) ~= "function" then
    log_error("Handler must be a function")
    return false
  end
  
  notification_handlers[method] = handler
  log_info("Registered handler for " .. method)
  return true
end

-- Log that we're being loaded
log_info("augment_compat module loaded", true)

-- Log module load in VimEnter to make sure it appears after startup
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    log_info("augment_compat initialization complete", true)
  end
})

-- Start the lsp client (core function needed by VimScript)
function M.start_client(command, notification_methods, workspace_folders)
  -- Log function call with details
  if log then
    log.func_call("start_client", command, notification_methods, #workspace_folders)
  end
  log_info("Starting LSP client", true)
  
  -- Input validation
  if not command or type(command) ~= "table" or #command == 0 then
    local err_msg = "Invalid command: " .. vim.inspect(command)
    log_error(err_msg, true)
    error(err_msg)
  end
  
  -- Get plugin version if possible
  local plugin_version
  local ok, err = pcall(function()
    plugin_version = vim.fn['augment#version#Version']()
  end)
  if not ok then
    plugin_version = "unknown"
    log_error("Failed to get plugin version: " .. err)
  end
  
  -- Set up basic configuration
  local config = {
    name = 'Augment Server',
    cmd = command,
    init_options = {
      editor = 'nvim',
      vimVersion = tostring(vim.version()),
      pluginVersion = plugin_version,
    },
    handlers = {}
  }
  
  -- Add handlers for notification methods
  for _, method in ipairs(notification_methods) do
    config.handlers[method] = function(_, params, _)
      if log then
        log.debug("Received notification: " .. method)
      end
      
      -- Check if we have a custom Lua handler for this method
      local custom_handler = notification_handlers[method]
      if custom_handler then
        -- Use our Lua handler
        vim.schedule(function()
          local ok, err = pcall(custom_handler, params)
          if not ok then
            log_error("Error in custom handler for " .. method .. ": " .. err)
            -- Fall back to VimScript handler
            pcall(vim.fn['augment#client#NvimNotification'], method, params)
          end
        end)
      else
        -- Use VimScript handler
        vim.schedule(function()
          local ok, err = pcall(vim.fn['augment#client#NvimNotification'], method, params)
          if not ok and log then
            log.error("Error in notification handler: " .. err)
          end
        end)
      end
    end
  end
  
  -- Add exit handler
  config.on_exit = function(code, signal, client_id)
    log_info("LSP client exited with code " .. code .. ", signal " .. signal, true)
    
    vim.schedule(function()
      local ok, err = pcall(vim.fn['augment#client#NvimOnExit'], code, signal, client_id)
      if not ok then
        log_error("Error in exit handler: " .. err)
      end
    end)
  end
  
  -- Add workspace folders if provided
  if workspace_folders and #workspace_folders > 0 then
    config.workspace_folders = workspace_folders
    if log then
      log.info("Using " .. #workspace_folders .. " workspace folders")
    end
  else
    log_info("No workspace folders provided", true)
  end
  
  -- Start the client
  local ok, id_or_err = pcall(vim.lsp.start_client, config)
  if not ok then
    log_error("Failed to start LSP client: " .. tostring(id_or_err), true)
    error("Failed to start LSP client: " .. tostring(id_or_err))
  end
  
  log_info("LSP client started with ID: " .. id_or_err, true)
  return id_or_err
end

-- Attach buffer to client
function M.open_buffer(client_id, bufnr)
  if log then
    log.func_call("open_buffer", client_id, bufnr)
  end
  
  -- Validate arguments
  if not client_id or not bufnr then
    local err_msg = "Missing required arguments for open_buffer"
    log_error(err_msg, true)
    error(err_msg)
  end
  
  -- Check if client exists
  local client = vim.lsp.get_client_by_id(client_id)
  if not client then
    local err_msg = "No LSP client found for ID: " .. client_id
    log_error(err_msg)
    return false
  end
  
  -- Attach buffer
  local ok, err = pcall(vim.lsp.buf_attach_client, bufnr, client_id)
  if not ok then
    log_error("Failed to attach buffer: " .. err)
    return false
  end
  
  log_info("Attached buffer " .. bufnr .. " to client " .. client_id)
  return true
end

-- Send notification
function M.notify(client_id, method, params)
  if log then
    log.func_call("notify", client_id, method)
  end
  
  -- Check if client exists
  local client = vim.lsp.get_client_by_id(client_id)
  if not client then
    local err_msg = "No LSP client found for ID: " .. client_id
    log_error(err_msg)
    
    -- Also log to augment log
    pcall(function()
      vim.fn['augment#log#Error']('No lsp client found for id: ' .. client_id)
    end)
    return
  end
  
  -- Send notification
  local ok, err = pcall(function()
    client.notify(method, params)
  end)
  
  if not ok then
    log_error("Failed to send notification " .. method .. ": " .. err)
  else
    if log then
      log.debug("Sent notification: " .. method)
    end
  end
end

-- Send request
function M.request(client_id, method, params)
  if log then
    log.func_call("request", client_id, method)
  end
  
  -- Check if client exists
  local client = vim.lsp.get_client_by_id(client_id)
  if not client then
    local err_msg = "No LSP client found for ID: " .. client_id
    log_error(err_msg)
    
    -- Also log to augment log
    pcall(function()
      vim.fn['augment#log#Error']('No lsp client found for id: ' .. client_id)
    end)
    return
  end
  
  -- Create the callback function
  local callback = function(err, result)
    vim.schedule(function()
      if err then
        log_error("Request error for " .. method .. ": " .. vim.inspect(err))
      else
        if log then
          log.debug("Received response for " .. method)
        end
      end
      
      -- Forward to VimScript handler
      local ok, call_err = pcall(vim.fn['augment#client#NvimResponse'], method, params, result, err)
      if not ok and log then
        log.error("Error in response handler: " .. call_err)
      end
    end)
  end
  
  -- Send request
  local ok, id_or_err = pcall(function()
    local _, id = client.request(method, params, callback)
    return id
  end)
  
  if not ok then
    log_error("Failed to send request " .. method .. ": " .. id_or_err)
    return nil
  end
  
  log_info("Sent request: " .. method .. " (ID: " .. id_or_err .. ")")
  return id_or_err
end

-- Show log in a buffer
function M.show_log()
  if log and log.show then
    log.show()
  else
    log_error("Logger not available", true)
  end
end

-- Return module
return M