-- Copyright (c) 2025 Augment
-- MIT License - See LICENSE.md for full terms

-- Enhanced hover documentation using Neovim-specific features

local log = require('augment_log')
local ui = require('augment/ui')
local lsp = require('augment/lsp')
local M = {}

-- Hover configuration
local config = {
  -- Hover display options
  display = {
    max_width = 80,
    max_height = 30,
    border = 'rounded',
    focusable = true,
    close_on_cursor_move = true,
    close_on_esc = true,
  },
  
  -- Content formatting
  formatting = {
    wrap = true,
    trim_empty_lines = true,
    syntax_highlight = true,
  },
  
  -- Keymaps
  keymaps = {
    close = {'q', '<Esc>'},
    scroll_down = {'j', '<Down>'},
    scroll_up = {'k', '<Up>'},
    page_down = {'<C-d>', '<PageDown>'},
    page_up = {'<C-u>', '<PageUp>'},
  }
}

-- Set up the hover module
function M.setup(opts)
  if opts then
    -- Merge options
    for category, values in pairs(opts) do
      if type(values) == 'table' and type(config[category]) == 'table' then
        for k, v in pairs(values) do
          config[category][k] = v
        end
      else
        config[category] = values
      end
    end
  end
  
  log.info("Hover module initialized")
  return true
end

-- Show hover documentation at cursor position
function M.show_hover_doc()
  -- Get current position
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  
  -- Get document URI
  local uri = vim.uri_from_bufnr(bufnr)
  
  -- Create request params
  local params = {
    textDocument = {
      uri = uri
    },
    position = {
      line = row,
      character = col
    }
  }
  
  -- Display loading indicator
  local loading_ns = vim.api.nvim_create_namespace('augment_hover_loading')
  local loading_mark_id = vim.api.nvim_buf_set_extmark(bufnr, loading_ns, row, col, {
    virt_text = {{"Loading documentation...", "Comment"}},
    virt_text_pos = "eol",
    priority = 100,
  })
  
  -- Function to clear loading indicator
  local function clear_loading()
    vim.api.nvim_buf_del_extmark(bufnr, loading_ns, loading_mark_id)
  end
  
  -- Send hover request
  lsp.request('textDocument/hover', params, function(err, result)
    -- Clear loading indicator
    clear_loading()
    
    if err then
      -- Show error notification
      ui.notify("Error fetching hover documentation: " .. vim.inspect(err), "error")
      return
    end
    
    -- Check if we have results
    if not result or not result.contents then
      -- No documentation found
      ui.notify("No documentation available", "info", {timeout = 2000})
      return
    end
    
    -- Format the hover content
    local content
    if type(result.contents) == 'string' then
      content = result.contents
    elseif result.contents.kind == 'markdown' or result.contents.kind == 'plaintext' then
      content = result.contents.value
    elseif result.contents.language and result.contents.value then
      -- Code block
      content = "```" .. result.contents.language .. "\n" .. result.contents.value .. "\n```"
    elseif type(result.contents) == 'table' and result.contents.value then
      content = result.contents.value
    elseif type(result.contents) == 'table' then
      -- Array of MarkedString or MarkupContent
      local parts = {}
      for _, item in ipairs(result.contents) do
        if type(item) == 'string' then
          table.insert(parts, item)
        elseif type(item) == 'table' and item.value then
          if item.language then
            table.insert(parts, "```" .. item.language .. "\n" .. item.value .. "\n```")
          else
            table.insert(parts, item.value)
          end
        end
      end
      content = table.concat(parts, '\n\n')
    else
      -- Fallback for unexpected formats
      content = vim.inspect(result.contents)
    end
    
    -- Trim empty lines if configured
    if config.formatting.trim_empty_lines then
      content = content:gsub("^%s*\n", ""):gsub("\n%s*$", "")
    end
    
    -- Check if we have content to display
    if not content or content == "" then
      ui.notify("No documentation available", "info", {timeout = 2000})
      return
    end
    
    -- Show documentation in floating window
    ui.show_hover(content, {
      width = config.display.max_width,
      height = config.display.max_height,
      border = config.display.border,
      focusable = config.display.focusable,
      close_on_cursor_move = config.display.close_on_cursor_move,
      wrap = config.formatting.wrap
    })
  end)
end

-- Show signature help at cursor position
function M.show_signature_help()
  -- Get current position
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  
  -- Get document URI
  local uri = vim.uri_from_bufnr(bufnr)
  
  -- Create request params
  local params = {
    textDocument = {
      uri = uri
    },
    position = {
      line = row,
      character = col
    }
  }
  
  -- Send signature help request
  lsp.request('textDocument/signatureHelp', params, function(err, result)
    if err then
      -- Show error notification
      ui.notify("Error fetching signature help: " .. vim.inspect(err), "error")
      return
    end
    
    -- Check if we have results
    if not result or not result.signatures or #result.signatures == 0 then
      -- No signatures found
      ui.notify("No signature help available", "info", {timeout = 2000})
      return
    end
    
    -- Get active signature
    local active_idx = result.activeSignature or 0
    local signature = result.signatures[active_idx + 1] or result.signatures[1]
    
    -- Format the signature content
    local content = ""
    
    -- Add signature label
    content = content .. "```\n" .. signature.label .. "\n```\n\n"
    
    -- Add documentation if available
    if signature.documentation then
      if type(signature.documentation) == 'string' then
        content = content .. signature.documentation
      elseif type(signature.documentation) == 'table' and signature.documentation.value then
        content = content .. signature.documentation.value
      end
    end
    
    -- Highlight active parameter
    if signature.parameters and signature.parameters[result.activeParameter + 1] then
      local param = signature.parameters[result.activeParameter + 1]
      if param.label then
        -- Could highlight this in the UI
        content = content .. "\n\n**Active parameter:** " .. 
          (type(param.label) == 'string' and param.label or "param " .. (result.activeParameter + 1))
      end
    end
    
    -- Show signature help in floating window
    ui.show_hover(content, {
      width = math.min(#signature.label + 10, config.display.max_width),
      height = math.min(10, config.display.max_height),
      border = config.display.border,
      position = 'cursor',
      title = " Signature Help ",
      focusable = false, -- Better for signatures to be non-focusable
      close_on_cursor_move = true
    })
  end)
end

-- Show diagnostics at cursor position
function M.show_cursor_diagnostics()
  -- Get cursor position
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  
  -- Get diagnostics at cursor
  local diagnostics = vim.diagnostic.get(0, {
    lnum = row,
  })
  
  if not diagnostics or #diagnostics == 0 then
    ui.notify("No diagnostics at cursor position", "info", {timeout = 2000})
    return
  end
  
  -- Format diagnostics for display
  local content = "# Diagnostics\n\n"
  
  -- Sort by severity (highest first)
  table.sort(diagnostics, function(a, b)
    return (a.severity or 1) < (b.severity or 1)
  end)
  
  -- Map diagnostic severity to readable name and icon
  local severity_map = {
    [1] = {name = "Error", icon = ""},
    [2] = {name = "Warning", icon = ""},
    [3] = {name = "Information", icon = ""},
    [4] = {name = "Hint", icon = ""}
  }
  
  -- Build content from diagnostics
  for i, diagnostic in ipairs(diagnostics) do
    local severity = severity_map[diagnostic.severity or 3]
    
    content = content .. "## " .. severity.icon .. " " .. severity.name .. "\n\n"
    content = content .. diagnostic.message .. "\n\n"
    
    -- Add source if available
    if diagnostic.source then
      content = content .. "*Source: " .. diagnostic.source .. "*\n\n"
    end
    
    -- Add separator between diagnostics
    if i < #diagnostics then
      content = content .. "---\n\n"
    end
  end
  
  -- Show diagnostics in floating window
  ui.show_hover(content, {
    width = config.display.max_width,
    height = config.display.max_height,
    border = config.display.border,
    position = 'cursor',
    title = " Diagnostics (" .. #diagnostics .. ") ",
    focusable = config.display.focusable
  })
end

-- Create key mappings for hover features
function M.setup_keymaps()
  -- Hover documentation
  vim.keymap.set('n', 'K', M.show_hover_doc, {
    desc = "Show hover documentation",
    silent = true
  })
  
  -- Signature help
  vim.keymap.set('i', '<C-k>', M.show_signature_help, {
    desc = "Show signature help",
    silent = true
  })
  
  -- Diagnostics at cursor
  vim.keymap.set('n', '<leader>ad', M.show_cursor_diagnostics, {
    desc = "Show diagnostics at cursor",
    silent = true
  })
  
  log.info("Hover keymaps configured")
  return true
end

-- Initialize the module
M.setup()

return M