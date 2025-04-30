-- Copyright (c) 2025 Augment
-- MIT License - See LICENSE.md for full terms

-- Dedicated logging module for Lua errors and debug information
-- Outputs to ~/.local/state/nvim/augment.log

local M = {}

-- Log levels
M.levels = {
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4,
  FATAL = 5
}

-- Current log level (can be changed at runtime)
local current_level = M.levels.INFO

-- Colors for different log levels when shown in Neovim
local level_colors = {
  [M.levels.DEBUG] = "Comment",
  [M.levels.INFO] = "Normal",
  [M.levels.WARN] = "WarningMsg",
  [M.levels.ERROR] = "ErrorMsg",
  [M.levels.FATAL] = "ErrorMsg"
}

-- Level names for output
local level_names = {
  [M.levels.DEBUG] = "DEBUG",
  [M.levels.INFO] = "INFO",
  [M.levels.WARN] = "WARN",
  [M.levels.ERROR] = "ERROR",
  [M.levels.FATAL] = "FATAL"
}

-- Get log file path in Neovim state directory
local function get_log_file()
  local state_dir = vim.fn.stdpath('state')
  return state_dir .. '/augment.log'
end

-- Initialize log file with header
local function init_log_file()
  local file = io.open(get_log_file(), 'w')
  if file then
    file:write("=== Augment Lua Module Log ===\n")
    file:write("Started: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
    file:write("Neovim Version: " .. vim.version().major .. "." .. 
               vim.version().minor .. "." .. vim.version().patch .. "\n")
    file:write("============================\n\n")
    file:close()
    return true
  end
  return false
end

-- Try to initialize the log file on module load
local log_init_success = init_log_file()
if not log_init_success then
  vim.schedule(function()
    vim.api.nvim_echo({{"Failed to initialize augment log file", "ErrorMsg"}}, false, {})
  end)
end

-- Write to log file
local function write_to_log(level, message)
  if level < current_level then
    return  -- Skip if below current log level
  end
  
  local file = io.open(get_log_file(), 'a')
  if not file then
    vim.schedule(function()
      vim.api.nvim_echo({{"Failed to write to augment log file", "ErrorMsg"}}, false, {})
    end)
    return
  end
  
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local level_name = level_names[level] or "UNKNOWN"
  file:write(string.format("[%s] [%s] %s\n", timestamp, level_name, message))
  file:close()
end

-- Set log level
function M.set_level(level)
  if type(level) == "string" then
    level = M.levels[string.upper(level)] or M.levels.INFO
  end
  current_level = level
  M.info("Log level set to " .. level_names[current_level])
end

-- Log with level and optional echo to screen
local function log(level, message, echo)
  write_to_log(level, message)
  
  if echo then
    vim.schedule(function()
      vim.api.nvim_echo({{"Augment: " .. message, level_colors[level] or "Normal"}}, false, {})
    end)
  end
end

-- Public logging functions
function M.debug(message, echo)
  log(M.levels.DEBUG, message, echo)
end

function M.info(message, echo)
  log(M.levels.INFO, message, echo)
end

function M.warn(message, echo)
  log(M.levels.WARN, message, echo or true) -- Warnings echo by default
end

function M.error(message, echo)
  log(M.levels.ERROR, message, echo or true) -- Errors echo by default
end

function M.fatal(message, echo)
  log(M.levels.FATAL, message, echo or true) -- Fatal errors echo by default
end

-- Log a structured traceback of the current execution stack
function M.trace(message)
  message = message or "Execution trace"
  local trace_str = debug.traceback(message, 2)
  write_to_log(M.levels.DEBUG, trace_str)
end

-- Log a value with inspection
function M.inspect(value, message)
  message = message or "Value inspection"
  local inspected = vim.inspect(value)
  write_to_log(M.levels.DEBUG, message .. ": " .. inspected)
end

-- Log a function call with arguments
function M.func_call(func_name, ...)
  local args = {...}
  local args_str = ""
  for i, arg in ipairs(args) do
    if i > 1 then args_str = args_str .. ", " end
    args_str = args_str .. vim.inspect(arg)
  end
  write_to_log(M.levels.DEBUG, "Function call: " .. func_name .. "(" .. args_str .. ")")
end

-- Log an exception with traceback
function M.exception(err, message)
  message = message or "Exception caught"
  local err_str = tostring(err)
  write_to_log(M.levels.ERROR, message .. ": " .. err_str)
  M.trace()
end

-- Open the log file in a split window
function M.show()
  local log_file = get_log_file()
  vim.cmd("split " .. log_file)
  
  -- Set buffer options
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  
  -- Move cursor to end of file
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_win_set_cursor(0, {line_count, 0})
  
  -- Set up autocommand to auto-refresh log
  vim.cmd([[
  augroup augment_log_window
    autocmd!
    autocmd BufEnter <buffer> edit
    autocmd BufEnter <buffer> normal G
  augroup END
  ]])
end

-- Return the logger
return M