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
    lsp = false         -- Use pure Lua LSP client (not implemented yet)
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
    -- Lazy-load chat module
    local ok, chat = pcall(require, 'augment/chat')
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