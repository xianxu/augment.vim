-- Copyright (c) 2025 Augment
-- MIT License - See LICENSE.md for full terms

local log = require('augment_log')
local M = {}

-- Namespace for extmarks
local ns_id = vim.api.nvim_create_namespace('augment_suggestions')

-- Current suggestion state
local current_suggestion = nil
local current_extmark = nil
local current_bufnr = nil

-- Setup suggestion highlighting
function M.setup()
  -- Create highlight group for suggestions
  vim.api.nvim_set_hl(0, 'AugmentSuggestion', {
    fg = '#808080',
    ctermfg = 244,
    default = true
  })
  
  log.info("Suggestion module initialized")
  return true
end

-- Clear the current suggestion
function M.clear()
  if current_extmark and current_bufnr and vim.api.nvim_buf_is_valid(current_bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, current_bufnr, ns_id, current_extmark)
    log.debug("Cleared suggestion extmark")
  end
  
  current_suggestion = nil
  current_extmark = nil
  return true
end

-- Show a suggestion at the current cursor position
function M.show(suggestion, bufnr, row, col)
  -- Clear any existing suggestion
  M.clear()
  
  -- Validate parameters
  if not suggestion or not suggestion.text or suggestion.text == '' then
    log.debug("Empty suggestion, not showing")
    return false
  end
  
  -- Store suggestion information
  current_suggestion = suggestion
  current_bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  -- Get cursor position if not provided
  if not row or not col then
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    row = cursor_pos[1] - 1  -- Convert to 0-based
    col = cursor_pos[2]
  end
  
  log.debug(string.format("Showing suggestion: '%s' at %d:%d", 
    suggestion.text, row, col))
  
  -- Create extmark with virtual text
  current_extmark = vim.api.nvim_buf_set_extmark(current_bufnr, ns_id, row, col, {
    virt_text = {{suggestion.text, 'AugmentSuggestion'}},
    virt_text_pos = 'inline',
    priority = 100
  })
  
  return true
end

-- Accept the current suggestion
function M.accept()
  if not current_suggestion or not current_suggestion.text or current_suggestion.text == '' then
    log.debug("No suggestion to accept")
    return false
  end
  
  local text = current_suggestion.text
  log.info(string.format("Accepting suggestion: '%s'", text))
  
  -- Get current cursor position
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local row = cursor_pos[1] - 1  -- Convert to 0-based
  local col = cursor_pos[2]
  
  -- Insert the suggestion text
  pcall(vim.api.nvim_buf_set_text, 0, row, col, row, col, {text})
  
  -- Move cursor to end of inserted text
  vim.api.nvim_win_set_cursor(0, {row + 1, col + #text})
  
  -- Clear the suggestion
  M.clear()
  
  return true
end

-- Handle completion response from LSP
function M.handle_completion(result)
  if not result or not result.items or #result.items == 0 then
    log.debug("Empty completion result")
    M.clear()
    return false
  end
  
  -- Get the first completion item
  local item = result.items[1]
  if not item or not item.insertText then
    log.debug("Invalid completion item")
    M.clear()
    return false
  end
  
  -- Create suggestion object
  local suggestion = {
    text = item.insertText,
    label = item.label,
    detail = item.detail,
    kind = item.kind
  }
  
  -- Show the suggestion
  return M.show(suggestion)
end

-- Register this module with the Lua implementation
function M.register()
  -- Create notification handler for suggestions
  local compat = require('augment_compat')
  if compat.register_handler then
    compat.register_handler('augment/suggestion', function(params)
      M.show(params)
    end)
    log.info("Registered suggestion handler")
  end
  
  -- Set up autocmd to clear suggestions when cursor moves
  vim.api.nvim_create_autocmd("CursorMovedI", {
    callback = function()
      M.clear()
    end
  })
  
  return true
end

-- Initialize module
M.setup()

return M