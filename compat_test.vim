" Test the compatibility module
echo "Testing Lua compatibility module..."

" Force reload the module
lua package.loaded['augment_compat'] = nil

" Try to load the module
lua << EOF
local ok, compat = pcall(require, 'augment_compat')
if ok then
  vim.api.nvim_echo({{"Successfully loaded augment_compat", "Normal"}}, false, {})
  
  -- Check if start_client function exists
  if type(compat.start_client) == 'function' then
    vim.api.nvim_echo({{"start_client function exists", "Normal"}}, false, {})
  else
    vim.api.nvim_echo({{"ERROR: start_client function does not exist", "ErrorMsg"}}, false, {})
  end
  
  -- Check if other functions exist
  if type(compat.open_buffer) == 'function' and
     type(compat.notify) == 'function' and
     type(compat.request) == 'function' then
    vim.api.nvim_echo({{"All required functions exist", "Normal"}}, false, {})
  else
    vim.api.nvim_echo({{"ERROR: Some functions are missing", "ErrorMsg"}}, false, {})
  end
else
  vim.api.nvim_echo({{"ERROR: Failed to load module: " .. tostring(compat), "ErrorMsg"}}, false, {})
end
EOF