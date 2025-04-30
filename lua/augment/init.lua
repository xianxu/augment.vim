-- Copyright (c) 2025 Augment
-- MIT License - See LICENSE.md for full terms

local M = {}

-- Set up configuration
M.setup = function(opts)
  opts = opts or {}
  
  -- Will implement later
  
  return true
end

-- Get version information
M.version = function()
  return vim.call('augment#version#Version')
end

return M