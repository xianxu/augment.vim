-- Copyright (c) 2025 Augment
-- MIT License - See LICENSE.md for full terms

-- Main entry point for Augment's Lua implementation

local M = {}

-- Module dependencies
local log = require('augment_log')
local compat = require('augment_compat')

-- Default configuration
M.config = {
  -- Feature flags
  features = {
    suggestion = true,  -- Use Lua-based suggestions
    chat = true,        -- Use Lua-based chat
    lsp = true,         -- Use pure Lua LSP client
    diagnostics = true, -- Show diagnostics in the editor
    enhanced_ui = true  -- Use enhanced UI with Neovim-specific features
  },
  
  -- Optional workspace folders
  workspace_folders = {},
  
  -- Other options
  disable_tab_mapping = false,
  disable_completions = false,
  
  -- Chat panel configuration
  chat = {
    position = "right",  -- right, left, top, bottom
    width = 80,
    show_streaming = true
  },
  
  -- LSP client configuration
  lsp = {
    autostart = true,    -- Start the LSP client automatically
    cmd = nil,           -- Use default command
    root_dir = nil       -- Use current working directory
  },
  
  -- Diagnostics configuration
  diagnostics = {
    enabled = true,       -- Enable diagnostics
    signs = true,         -- Show signs in the sign column
    virtual_text = true,  -- Show virtual text
    underline = true,     -- Underline diagnostics
    update_in_insert = false, -- Don't update in insert mode
    severity_sort = true  -- Sort by severity
  },
  
  -- Enhanced UI configuration
  ui = {
    -- Floating windows
    float = {
      border = 'rounded',   -- Border style for floating windows
      max_width = 100,      -- Maximum width for floating windows
      max_height = 30,      -- Maximum height for floating windows
      winblend = 10        -- Window transparency (0-100)
    },
    
    -- Markdown rendering
    markdown = {
      use_treesitter = true, -- Use treesitter for syntax highlighting
      syntax_highlight = true, -- Highlight code blocks
      conceal = true,        -- Use concealing for markdown syntax
    },
    
    -- Notification settings
    notifications = {
      enabled = true,        -- Whether to show notifications
      timeout = 5000,        -- Default timeout for notifications (ms)
      position = 'top-right' -- Position for notifications
    }
  }
}

-- Setup function to initialize the Lua implementation
function M.setup(opts)
  -- Record setup in logs
  log.info("Augment Lua setup called")
  
  -- Merge options with defaults
  opts = opts or {}
  for k, v in pairs(opts) do
    if k == "features" and type(v) == "table" then
      -- Merge feature flags
      for fk, fv in pairs(v) do
        M.config.features[fk] = fv
      end
    else
      M.config[k] = v
    end
  end
  
  -- Setup individual modules based on feature flags
  if M.config.features.suggestion then
    log.info("Enabling Lua suggestions")
    -- Lazy-load suggestion module
    local ok, suggestion = pcall(require, 'augment/suggestion')
    if ok then
      suggestion.register()
    else
      log.error("Failed to load suggestion module: " .. tostring(suggestion))
    end
  end
  
  if M.config.features.chat then
    log.info("Enabling Lua chat")
    
    -- Load regular or enhanced chat module based on UI feature flag
    local chat_module = M.config.features.enhanced_ui and 'augment/chat_enhanced' or 'augment/chat'
    log.info("Using chat module: " .. chat_module)
    
    -- Lazy-load chat module
    local ok, chat = pcall(require, chat_module)
    if ok then
      -- Configure chat panel
      if opts and opts.chat then
        for k, v in pairs(opts.chat) do
          M.config.chat[k] = v
        end
      end
      
      chat.register()
    else
      log.error("Failed to load chat module: " .. tostring(chat))
    end
  end
  
  if M.config.features.lsp then
    log.info("Enabling Lua LSP client")
    -- Lazy-load LSP module
    local ok, lsp = pcall(require, 'augment/lsp')
    if ok then
      -- Configure LSP client
      if opts and opts.lsp then
        lsp.configure(opts.lsp)
      end
      
      -- Register handlers
      if M.config.features.suggestion then
        local suggestion_ok, suggestion = pcall(require, 'augment/suggestion')
        if suggestion_ok then
          lsp.register_notification_handler('augment/suggestion', function(params)
            suggestion.show(params)
          end)
        end
      end
      
      if M.config.features.chat then
        local chat_ok, chat = pcall(require, 'augment/chat')
        if chat_ok then
          lsp.register_notification_handler('augment/chatChunk', function(params)
            chat.handle_chat_chunk(params)
          end)
          
          lsp.register_response_handler('augment/chat', function(result)
            chat.handle_chat_response(result)
          end)
        end
      end
      
      if M.config.features.diagnostics then
        local diagnostics_ok, diagnostics = pcall(require, 'augment/diagnostics')
        if diagnostics_ok then
          -- Configure diagnostics
          if opts and opts.diagnostics then
            diagnostics.setup(opts.diagnostics)
          else
            diagnostics.setup(M.config.diagnostics)
          end
          
          -- Register diagnostics handler
          lsp.register_notification_handler('textDocument/publishDiagnostics', function(params)
            diagnostics.handle_diagnostics(params)
          end)
          
          log.info("Diagnostics handlers registered")
        else
          log.error("Failed to load diagnostics module: " .. tostring(diagnostics))
        end
      end
      
      -- Initialize UI module if enhanced UI is enabled
      if M.config.features.enhanced_ui then
        local ui_ok, ui = pcall(require, 'augment/ui')
        if ui_ok then
          -- Configure UI
          if opts and opts.ui then
            ui.setup(opts.ui)
          else
            ui.setup(M.config.ui)
          end
          
          log.info("Enhanced UI initialized")
          
          -- Load enhanced hover module
          local hover_ok, hover = pcall(require, 'augment/hover')
          if hover_ok then
            -- Set up hover module
            hover.setup_keymaps()
            log.info("Enhanced hover documentation initialized")
          else
            log.warn("Failed to load hover module: " .. tostring(hover))
          end
        else
          log.error("Failed to load UI module: " .. tostring(ui))
        end
      end
      
      -- Start the LSP client
      if M.config.lsp.autostart then
        lsp.start_client()
      end
    else
      log.error("Failed to load LSP module: " .. tostring(lsp))
    end
  end
  
  -- Set up global exports
  -- These functions might be called directly from VimScript
  _G.augment_accept = function(fallback)
    local ok, suggestion = pcall(require, 'augment/suggestion')
    if ok and M.config.features.suggestion then
      local success = suggestion.accept()
      if not success and fallback then
        vim.api.nvim_feedkeys(fallback, 'n', true)
      end
      return success
    else
      -- Fall back to VimScript
      if fallback then
        vim.api.nvim_feedkeys(fallback, 'n', true)
      end
      return false
    end
  end
  
  log.info("Augment Lua setup complete")
  return true
end

-- Accept suggestion (for direct calls)
function M.accept(fallback)
  return _G.augment_accept(fallback)
end

-- Expose version information
function M.version()
  local v
  pcall(function()
    v = vim.fn['augment#version#Version']()
  end)
  return v or "unknown"
end

return M