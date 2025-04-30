" Augment Lua Diagnostic Script
" This script helps diagnose issues with the Lua implementation

echom "Starting Augment Lua diagnostics..."

" Check if Neovim is being used
if !has('nvim')
  echohl ErrorMsg
  echom "ERROR: This diagnostic tool requires Neovim"
  echohl None
  finish
endif

" Reload modules
echom "Reloading Lua modules..."
lua << EOF
package.loaded['augment_log'] = nil
package.loaded['augment_compat'] = nil
package.loaded['augment'] = nil
EOF

" Check for required modules
lua << EOF
local function print_module_status(name)
  local ok, mod = pcall(require, name)
  if ok then
    vim.api.nvim_echo({{"✓ Module '" .. name .. "' loaded successfully", "Normal"}}, false, {})
    return true
  else
    vim.api.nvim_echo({{"✗ Module '" .. name .. "' failed to load: " .. tostring(mod), "ErrorMsg"}}, false, {})
    return false
  end
end

vim.api.nvim_echo({{"Checking for required modules:", "Title"}}, false, {})
local augment_log_ok = print_module_status('augment_log')
local augment_compat_ok = print_module_status('augment_compat')
local augment_ok = print_module_status('augment')

-- Initialize logging if possible
if augment_log_ok then
  local log = require('augment_log')
  log.set_level('DEBUG')
  log.info("Diagnostic script executed")
end

-- Check for required functions in augment_compat
if augment_compat_ok then
  local compat = require('augment_compat')
  local required_functions = {
    'start_client', 
    'open_buffer', 
    'notify', 
    'request'
  }
  
  vim.api.nvim_echo({{"", ""}}, false, {})
  vim.api.nvim_echo({{"Checking for required functions in augment_compat:", "Title"}}, false, {})
  
  for _, func_name in ipairs(required_functions) do
    if type(compat[func_name]) == 'function' then
      vim.api.nvim_echo({{"✓ Function '" .. func_name .. "' exists", "Normal"}}, false, {})
    else
      vim.api.nvim_echo({{"✗ Function '" .. func_name .. "' is missing", "ErrorMsg"}}, false, {})
    end
  end
end

-- Check for required functions in augment
if augment_ok then
  local augment = require('augment')
  local required_functions = {
    'start_client', 
    'open_buffer', 
    'notify', 
    'request'
  }
  
  vim.api.nvim_echo({{"", ""}}, false, {})
  vim.api.nvim_echo({{"Checking for required functions in augment:", "Title"}}, false, {})
  
  for _, func_name in ipairs(required_functions) do
    if type(augment[func_name]) == 'function' then
      vim.api.nvim_echo({{"✓ Function '" .. func_name .. "' exists", "Normal"}}, false, {})
    else
      vim.api.nvim_echo({{"✗ Function '" .. func_name .. "' is missing", "ErrorMsg"}}, false, {})
    end
  end
end

-- Check log file accessibility
vim.api.nvim_echo({{"", ""}}, false, {})
vim.api.nvim_echo({{"Checking log file:", "Title"}}, false, {})

local log_file = vim.fn.stdpath('state') .. '/augment.log'
local file = io.open(log_file, "a")
if file then
  file:write("Diagnostic check run at " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
  file:close()
  vim.api.nvim_echo({{"✓ Log file is writable: " .. log_file, "Normal"}}, false, {})
else
  vim.api.nvim_echo({{"✗ Cannot write to log file: " .. log_file, "ErrorMsg"}}, false, {})
end

-- Provide summary of diagnostic results
vim.api.nvim_echo({{"", ""}}, false, {})
vim.api.nvim_echo({{"Diagnostic Summary:", "Title"}}, false, {})

if augment_log_ok and augment_compat_ok then
  vim.api.nvim_echo({{"✓ Basic compatibility layer is working", "Normal"}}, false, {})
  vim.api.nvim_echo({{"✓ Logging is functional", "Normal"}}, false, {})
  vim.api.nvim_echo({{"", ""}}, false, {})
  vim.api.nvim_echo({{"For detailed logs, run :AugmentShowLuaLog", "Normal"}}, false, {})
else
  vim.api.nvim_echo({{"✗ There are issues with the compatibility layer", "ErrorMsg"}}, false, {})
end
EOF

echom "Augment Lua diagnostics complete."