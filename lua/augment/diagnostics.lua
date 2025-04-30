-- Copyright (c) 2025 Augment
-- MIT License - See LICENSE.md for full terms

-- Diagnostics visualization for Augment plugin

local log = require('augment_log')
local M = {}

-- Configuration options
local config = {
  enabled = true,           -- Whether diagnostics are enabled
  signs = true,             -- Show diagnostic signs in the sign column
  virtual_text = true,      -- Show diagnostics as virtual text
  underline = true,         -- Underline diagnostics
  float_opts = {            -- Options for floating windows
    border = 'rounded',     -- Border style for floating windows
    max_width = 100,        -- Maximum width of floating windows
    max_height = 20,        -- Maximum height of floating windows
    focusable = false,      -- Whether floating windows are focusable
  },
  severity_sort = true,     -- Sort diagnostics by severity
  update_in_insert = false, -- Update diagnostics in insert mode
}

-- Diagnostic namespace
local namespace = vim.api.nvim_create_namespace('augment_diagnostics')

-- Diagnostic levels
local SEVERITY = {
  ERROR = 1,
  WARN = 2,
  INFO = 3,
  HINT = 4
}

-- Define signs for different diagnostic levels
local diagnostic_signs = {
  {name = 'AugmentSignError', text = '', texthl = 'AugmentSignError', linehl = '', numhl = ''},
  {name = 'AugmentSignWarn', text = '', texthl = 'AugmentSignWarn', linehl = '', numhl = ''},
  {name = 'AugmentSignInfo', text = '', texthl = 'AugmentSignInfo', linehl = '', numhl = ''},
  {name = 'AugmentSignHint', text = '', texthl = 'AugmentSignHint', linehl = '', numhl = ''},
}

-- Map between LSP severity and our levels
local severity_map = {
  [1] = SEVERITY.ERROR,
  [2] = SEVERITY.WARN,
  [3] = SEVERITY.INFO,
  [4] = SEVERITY.HINT
}

-- Setup diagnostic signs and highlighting
local function setup_highlights()
  -- Define highlight groups for diagnostic signs
  vim.api.nvim_set_hl(0, 'AugmentSignError', {fg = '#e06c75', default = true})
  vim.api.nvim_set_hl(0, 'AugmentSignWarn', {fg = '#e5c07b', default = true})
  vim.api.nvim_set_hl(0, 'AugmentSignInfo', {fg = '#61afef', default = true})
  vim.api.nvim_set_hl(0, 'AugmentSignHint', {fg = '#98c379', default = true})
  
  -- Define highlight groups for diagnostics
  vim.api.nvim_set_hl(0, 'AugmentDiagnosticError', {fg = '#e06c75', default = true})
  vim.api.nvim_set_hl(0, 'AugmentDiagnosticWarn', {fg = '#e5c07b', default = true})
  vim.api.nvim_set_hl(0, 'AugmentDiagnosticInfo', {fg = '#61afef', default = true})
  vim.api.nvim_set_hl(0, 'AugmentDiagnosticHint', {fg = '#98c379', default = true})
  
  -- Define underline highlights
  vim.api.nvim_set_hl(0, 'AugmentDiagnosticUnderlineError', {undercurl = true, sp = '#e06c75', default = true})
  vim.api.nvim_set_hl(0, 'AugmentDiagnosticUnderlineWarn', {undercurl = true, sp = '#e5c07b', default = true})
  vim.api.nvim_set_hl(0, 'AugmentDiagnosticUnderlineInfo', {undercurl = true, sp = '#61afef', default = true})
  vim.api.nvim_set_hl(0, 'AugmentDiagnosticUnderlineHint', {undercurl = true, sp = '#98c379', default = true})
  
  -- Define signs for different diagnostic levels
  for _, sign in ipairs(diagnostic_signs) do
    vim.fn.sign_define(sign.name, sign)
  end
end

-- Configure Neovim's diagnostic display
local function setup_diagnostic_config()
  vim.diagnostic.config({
    virtual_text = config.virtual_text and {
      prefix = '» ',
      spacing = 4,
      source = 'if_many',
      severity = {
        min = vim.diagnostic.severity.HINT
      }
    } or false,
    signs = config.signs,
    underline = config.underline,
    update_in_insert = config.update_in_insert,
    severity_sort = config.severity_sort,
    float = {
      border = config.float_opts.border,
      source = 'always',
      header = '',
      prefix = '',
      max_width = config.float_opts.max_width,
      max_height = config.float_opts.max_height,
      focusable = config.float_opts.focusable,
    }
  }, namespace)
end

-- Setup diagnostics functionality
function M.setup(opts)
  -- Merge configuration
  if opts then
    for k, v in pairs(opts) do
      if k == 'float_opts' and type(v) == 'table' then
        for fk, fv in pairs(v) do
          config.float_opts[fk] = fv
        end
      else
        config[k] = v
      end
    end
  end
  
  -- Setup the visual elements
  setup_highlights()
  
  -- Configure diagnostics display
  setup_diagnostic_config()
  
  -- Register keymaps for diagnostics navigation
  -- Go to previous diagnostic
  vim.keymap.set('n', '[d', function()
    vim.diagnostic.goto_prev({namespace = namespace})
  end, {desc = 'Go to previous Augment diagnostic'})
  
  -- Go to next diagnostic
  vim.keymap.set('n', ']d', function()
    vim.diagnostic.goto_next({namespace = namespace})
  end, {desc = 'Go to next Augment diagnostic'})
  
  -- Show diagnostics in a floating window
  vim.keymap.set('n', '<leader>ad', function()
    vim.diagnostic.open_float({namespace = namespace})
  end, {desc = 'Show Augment diagnostics'})
  
  -- Show diagnostics list
  vim.keymap.set('n', '<leader>aq', function()
    vim.diagnostic.setloclist({namespace = namespace})
  end, {desc = 'Show Augment diagnostics in quickfix list'})
  
  log.info("Diagnostics module initialized")
  return true
end

-- Convert LSP diagnostics to Neovim diagnostics
local function convert_diagnostics(diagnostics)
  local result = {}
  
  for _, diag in ipairs(diagnostics) do
    local severity = severity_map[diag.severity] or SEVERITY.INFO
    
    -- Create a diagnostic entry
    table.insert(result, {
      lnum = diag.range.start.line,
      col = diag.range.start.character,
      end_lnum = diag.range["end"].line,
      end_col = diag.range["end"].character,
      severity = severity,
      message = diag.message,
      source = diag.source or 'augment'
    })
  end
  
  return result
end

-- Set diagnostics for a buffer
function M.set_diagnostics(bufnr, diagnostics)
  if not config.enabled then return end
  
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  -- Convert LSP diagnostics to Neovim diagnostics
  local converted = convert_diagnostics(diagnostics)
  
  -- Set the diagnostics
  vim.diagnostic.set(namespace, bufnr, converted)
  
  log.debug("Set " .. #converted .. " diagnostics for buffer " .. bufnr)
  return true
end

-- Clear diagnostics for a buffer
function M.clear_diagnostics(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  -- Clear the diagnostics
  vim.diagnostic.reset(namespace, bufnr)
  
  log.debug("Cleared diagnostics for buffer " .. bufnr)
  return true
end

-- Show diagnostics at cursor
function M.show_diagnostics_at_cursor()
  vim.diagnostic.open_float({namespace = namespace})
end

-- Show all diagnostics in a location list
function M.show_diagnostics_list()
  vim.diagnostic.setloclist({namespace = namespace})
end

-- Enable diagnostics
function M.enable()
  config.enabled = true
  setup_diagnostic_config()
  log.info("Diagnostics enabled")
  return true
end

-- Disable diagnostics
function M.disable()
  config.enabled = false
  
  -- Clear all diagnostics
  vim.diagnostic.reset(namespace)
  
  log.info("Diagnostics disabled")
  return true
end

-- Toggle diagnostics
function M.toggle()
  if config.enabled then
    M.disable()
  else
    M.enable()
  end
  
  return config.enabled
end

-- Get diagnostic configuration
function M.get_config()
  return vim.deepcopy(config)
end

-- Handle diagnostics from LSP
function M.handle_diagnostics(params)
  if not config.enabled then return end
  
  -- Get buffer for the URI
  local uri = params.uri
  local bufnr = vim.uri_to_bufnr(uri)
  
  -- Only handle diagnostics for loaded buffers
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    log.debug("Buffer for URI " .. uri .. " not loaded, skipping diagnostics")
    return
  end
  
  -- Set the diagnostics
  M.set_diagnostics(bufnr, params.diagnostics)
  
  return true
end

-- Initialize module
M.setup()

return M