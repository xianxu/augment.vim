-- Copyright (c) 2025 Augment
-- MIT License - See LICENSE.md for full terms

-- Enhanced UI elements for Neovim-specific features

local log = require('augment_log')
local M = {}

-- UI configuration
M.config = {
  -- Floating windows
  float = {
    border = 'rounded',      -- Border style for floating windows
    max_width = 100,         -- Maximum width for floating windows
    max_height = 30,         -- Maximum height for floating windows
    padding = { 1, 1, 1, 1 }, -- Padding inside floating windows (top, right, bottom, left)
    winblend = 10,           -- Window transparency (0-100)
    zindex = 50,             -- Z-index for floating windows
    focusable = true,        -- Whether floating windows are focusable
  },
  
  -- Highlighting
  highlight = {
    enabled = true,          -- Whether to use custom highlighting
    virtual_text = true,     -- Whether to use virtual text for annotations
    use_treesitter = true,   -- Whether to use treesitter for syntax highlighting
  },
  
  -- Hover documentation
  hover = {
    auto_focus = false,      -- Whether to auto-focus hover windows
    max_width = 80,          -- Maximum width for hover windows
    max_height = 20,         -- Maximum height for hover windows
    close_on_cursor_move = true, -- Whether to close hover windows when cursor moves
  },
  
  -- Notification settings
  notifications = {
    enabled = true,          -- Whether to show notifications
    timeout = 5000,          -- Default timeout for notifications (ms)
    max_width = 60,          -- Maximum width for notifications
    position = 'top-right',  -- Position for notifications
    icons = {
      error = '',
      warn = '',
      info = '',
      hint = '',
    }
  }
}

-- Color scheme
local colors = {
  bg = '#282a36',
  fg = '#f8f8f2',
  dark_bg = '#21222c',
  light_bg = '#44475a',
  blue = '#6272a4',
  cyan = '#8be9fd',
  green = '#50fa7b',
  orange = '#ffb86c',
  pink = '#ff79c6',
  purple = '#bd93f9',
  red = '#ff5555',
  yellow = '#f1fa8c',
}

-- Variable for storing open windows
local open_windows = {}

-- Namespace for extmarks
local ns = vim.api.nvim_create_namespace('augment_ui')

-- Set up highlight groups
local function setup_highlights()
  -- UI elements
  vim.api.nvim_set_hl(0, 'AugmentFloat', { bg = colors.bg, fg = colors.fg, default = true })
  vim.api.nvim_set_hl(0, 'AugmentFloatBorder', { bg = colors.bg, fg = colors.purple, default = true })
  vim.api.nvim_set_hl(0, 'AugmentFloatTitle', { bg = colors.bg, fg = colors.pink, bold = true, default = true })
  
  -- Status items
  vim.api.nvim_set_hl(0, 'AugmentStatusNormal', { bg = colors.blue, fg = colors.bg, bold = true, default = true })
  vim.api.nvim_set_hl(0, 'AugmentStatusActive', { bg = colors.green, fg = colors.bg, bold = true, default = true })
  vim.api.nvim_set_hl(0, 'AugmentStatusError', { bg = colors.red, fg = colors.fg, bold = true, default = true })
  
  -- Virtual text
  vim.api.nvim_set_hl(0, 'AugmentVirtualText', { fg = colors.blue, italic = true, default = true })
  vim.api.nvim_set_hl(0, 'AugmentVirtualTextInfo', { fg = colors.cyan, italic = true, default = true })
  vim.api.nvim_set_hl(0, 'AugmentVirtualTextWarning', { fg = colors.orange, italic = true, default = true })
  vim.api.nvim_set_hl(0, 'AugmentVirtualTextError', { fg = colors.red, italic = true, default = true })
  
  -- Notifications
  vim.api.nvim_set_hl(0, 'AugmentNotificationInfo', { bg = colors.dark_bg, fg = colors.cyan, default = true })
  vim.api.nvim_set_hl(0, 'AugmentNotificationWarning', { bg = colors.dark_bg, fg = colors.orange, default = true })
  vim.api.nvim_set_hl(0, 'AugmentNotificationError', { bg = colors.dark_bg, fg = colors.red, default = true })
  vim.api.nvim_set_hl(0, 'AugmentNotificationSuccess', { bg = colors.dark_bg, fg = colors.green, default = true })
  
  -- Code blocks
  vim.api.nvim_set_hl(0, 'AugmentCodeBlock', { bg = colors.dark_bg, default = true })
  vim.api.nvim_set_hl(0, 'AugmentCodeBlockBorder', { fg = colors.purple, default = true })
  
  log.debug("UI highlights configured")
end

-- Close all open windows
function M.close_all_windows()
  for _, win in pairs(open_windows) do
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  open_windows = {}
end

-- Create a floating window
function M.create_float(opts)
  opts = opts or {}
  
  -- Get editor dimensions
  local columns = vim.o.columns
  local lines = vim.o.lines
  
  -- Calculate dimensions
  local width = opts.width or math.min(columns - 10, M.config.float.max_width)
  local height = opts.height or math.min(lines - 6, M.config.float.max_height)
  
  -- Calculate position
  local row, col
  if opts.position == 'center' then
    row = math.floor((lines - height) / 2)
    col = math.floor((columns - width) / 2)
  elseif opts.position == 'cursor' then
    -- Get current window and cursor position
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cursor_line = cursor[1]
    local cursor_col = cursor[2]
    
    -- Get current window position
    local win_pos = vim.fn.win_screenpos(0)
    local win_row = win_pos[1] - 1
    local win_col = win_pos[2] - 1
    
    -- Calculate position relative to cursor
    row = win_row + cursor_line
    col = win_col + cursor_col
    
    -- Adjust if too close to screen edge
    if row + height + 2 > lines then
      row = row - height - 2
    end
    if col + width + 2 > columns then
      col = columns - width - 2
    end
  else
    -- Default to centered
    row = math.floor((lines - height) / 2)
    col = math.floor((columns - width) / 2)
  end
  
  -- Buffer setup
  local buf = opts.buffer or vim.api.nvim_create_buf(false, true)
  
  -- Set buffer options
  if not opts.buffer then
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    
    -- Set buffer filetype if provided
    if opts.filetype then
      vim.api.nvim_buf_set_option(buf, 'filetype', opts.filetype)
    end
  end
  
  -- Window options
  local win_opts = {
    relative = 'editor',
    row = row,
    col = col,
    width = width,
    height = height,
    style = 'minimal',
    border = opts.border or M.config.float.border,
    zindex = opts.zindex or M.config.float.zindex,
    noautocmd = true,
  }
  
  -- Add title if provided
  if opts.title then
    win_opts.title = opts.title
    win_opts.title_pos = 'center'
  end
  
  -- Create window
  local win = vim.api.nvim_open_win(buf, opts.focus or false, win_opts)
  
  -- Set window options
  vim.api.nvim_win_set_option(win, 'winblend', opts.winblend or M.config.float.winblend)
  vim.api.nvim_win_set_option(win, 'winhl', 'Normal:AugmentFloat,FloatBorder:AugmentFloatBorder')
  vim.api.nvim_win_set_option(win, 'wrap', opts.wrap or true)
  
  -- Store window for later reference
  local id = #open_windows + 1
  open_windows[id] = win
  
  -- Add content if provided
  if opts.content then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, type(opts.content) == 'string' 
      and vim.split(opts.content, '\n') or opts.content)
  end
  
  -- Set up auto-close if requested
  if opts.timeout then
    vim.defer_fn(function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
        open_windows[id] = nil
      end
    end, opts.timeout)
  end
  
  -- Return window and buffer ids
  return { win = win, buf = buf, id = id }
end

-- Show virtual text at a specific position
function M.show_virtual_text(opts)
  if not M.config.highlight.virtual_text then
    return
  end
  
  opts = opts or {}
  
  -- Required options
  local bufnr = opts.buffer or vim.api.nvim_get_current_buf()
  local line = opts.line or (vim.api.nvim_win_get_cursor(0)[1] - 1)
  local text = opts.text or ""
  
  -- Optional settings
  local hl_group = opts.highlight or "AugmentVirtualText"
  local id = opts.id or math.random(1000000) -- Used for removal
  
  -- Add virtual text
  vim.api.nvim_buf_set_extmark(bufnr, ns, line, 0, {
    id = id,
    virt_text = {{text, hl_group}},
    virt_text_pos = opts.pos or "eol",
    hl_mode = "combine",
    priority = opts.priority or 100,
  })
  
  return id
end

-- Clear virtual text by id
function M.clear_virtual_text(bufnr, id)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_del_extmark(bufnr, ns, id)
end

-- Show a notification
function M.notify(message, level, opts)
  if not M.config.notifications.enabled then
    return
  end
  
  opts = opts or {}
  level = level or "info" -- info, warn, error, success
  
  -- Map level to highlight group
  local hl_map = {
    info = "AugmentNotificationInfo",
    warn = "AugmentNotificationWarning",
    error = "AugmentNotificationError",
    success = "AugmentNotificationSuccess"
  }
  
  -- Get icon for level
  local icon = M.config.notifications.icons[level] or ""
  
  -- Format message
  local content = icon .. " " .. message
  
  -- Calculate position based on config
  local position = opts.position or M.config.notifications.position
  
  -- Create float with notification
  local float_opts = {
    width = opts.width or M.config.notifications.max_width,
    height = opts.height or 3,
    border = opts.border or "rounded",
    content = content,
    timeout = opts.timeout or M.config.notifications.timeout,
    focus = false,
    filetype = "markdown"
  }
  
  -- Determine position
  if position == "top-right" then
    float_opts.row = 1
    float_opts.col = vim.o.columns - float_opts.width - 2
    float_opts.relative = "editor"
  elseif position == "top-left" then
    float_opts.row = 1
    float_opts.col = 1
    float_opts.relative = "editor"
  elseif position == "bottom-right" then
    float_opts.row = vim.o.lines - float_opts.height - 2
    float_opts.col = vim.o.columns - float_opts.width - 2
    float_opts.relative = "editor"
  elseif position == "bottom-left" then
    float_opts.row = vim.o.lines - float_opts.height - 2
    float_opts.col = 1
    float_opts.relative = "editor"
  else
    -- Default to centered
    float_opts.position = "center"
  end
  
  -- Create floating window
  local result = M.create_float(float_opts)
  
  -- Set highlight
  local hl_group = hl_map[level] or "AugmentNotificationInfo"
  vim.api.nvim_win_set_option(result.win, 'winhl', 'Normal:' .. hl_group .. ',FloatBorder:' .. hl_group)
  
  return result
end

-- Create a progress indicator
function M.progress_indicator(opts)
  opts = opts or {}
  
  local steps = opts.steps or 20
  local current_step = 0
  local timer = nil
  local win = nil
  local buf = nil
  
  -- Create a buffer for the progress
  buf = vim.api.nvim_create_buf(false, true)
  
  -- Create initial content
  local content = opts.title and (opts.title .. "\n") or ""
  content = content .. "[" .. string.rep(" ", steps) .. "]"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
  
  -- Create the window
  local float_result = M.create_float({
    buffer = buf,
    width = opts.width or steps + 4,
    height = opts.height or 3,
    position = opts.position or "center",
    focus = false,
    title = opts.window_title,
  })
  
  win = float_result.win
  
  -- Function to update progress
  local function update_progress()
    if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
      if timer then
        timer:stop()
      end
      return
    end
    
    -- Update progress bar
    current_step = current_step + 1
    if current_step > steps then
      -- Done
      if timer then
        timer:stop()
      end
      
      if opts.on_complete then
        opts.on_complete()
      end
      
      -- Auto close if requested
      if opts.auto_close then
        vim.defer_fn(function()
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
          end
        end, 500)
      end
      
      return
    end
    
    -- Update buffer
    local line = opts.title and 1 or 0
    local progress_text = "[" .. string.rep("=", current_step) .. 
                          string.rep(" ", steps - current_step) .. "]"
    
    vim.api.nvim_buf_set_option(buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(buf, line, line + 1, false, {progress_text})
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
    
    -- Call progress callback
    if opts.on_progress then
      opts.on_progress(current_step, steps)
    end
  end
  
  -- Create timer for animation
  timer = vim.loop.new_timer()
  timer:start(0, opts.interval or 100, update_progress)
  
  -- Return control functions
  return {
    -- Update progress manually
    update = function(new_step)
      if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
        return false
      end
      
      current_step = new_step
      if current_step > steps then
        current_step = steps
      end
      
      update_progress()
      return true
    end,
    
    -- Complete progress
    complete = function()
      if not vim.api.nvim_win_is_valid(win) or not vim.api.nvim_buf_is_valid(buf) then
        return false
      end
      
      current_step = steps
      update_progress()
      return true
    end,
    
    -- Close the progress window
    close = function()
      if timer then
        timer:stop()
      end
      
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
    
    -- Get the window and buffer
    get_window = function() return win end,
    get_buffer = function() return buf end,
  }
end

-- Show markdown in a floating window
function M.show_markdown(content, opts)
  opts = opts or {}
  
  -- Default options
  opts.filetype = 'markdown'
  opts.width = opts.width or 80
  opts.wrap = true
  
  -- Create the window
  local result = M.create_float(opts)
  local buf = result.buf
  
  -- Helper function to apply highlighting
  local function apply_highlighting(text)
    -- Split the text into lines
    local lines = vim.split(text, "\n")
    
    -- Add the content to the buffer
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    
    -- Apply basic markdown highlighting
    local in_code_block = false
    local code_lang = ""
    local code_start = 0
    
    for i, line in ipairs(lines) do
      -- Highlight code blocks
      if line:match("^```") then
        if not in_code_block then
          in_code_block = true
          code_start = i - 1
          -- Extract language if present
          code_lang = line:match("^```(%w+)")
          
          -- Highlight the code block marker
          vim.api.nvim_buf_add_highlight(buf, ns, "AugmentCodeBlockBorder", i - 1, 0, -1)
        else
          in_code_block = false
          
          -- Highlight the ending marker
          vim.api.nvim_buf_add_highlight(buf, ns, "AugmentCodeBlockBorder", i - 1, 0, -1)
          
          -- If treesitter is available and enabled, attempt to highlight the code
          if M.config.highlight.use_treesitter and code_lang and code_lang ~= "" then
            pcall(function()
              -- Get the lines in the code block
              local code_lines = vim.tbl_map(function(l) 
                return l:gsub("^```" .. code_lang, "")
              end, vim.list_slice(lines, code_start + 1, i - 1))
              
              -- Join into a single string
              local code = table.concat(code_lines, "\n")
              
              -- Attempt to highlight using treesitter
              local ok, parser = pcall(vim.treesitter.get_string_parser, code, code_lang)
              if ok and parser then
                parser:parse()
                
                -- Apply highlights
                parser:for_each_tree(function(tree, lang_tree)
                  local highlighter = vim.treesitter.highlighter.new(tree, lang_tree)
                  highlighter:highlight(buf, ns, code_start + 1, i - 1)
                end)
              end
            end)
          end
        end
      elseif in_code_block then
        -- Inside a code block
        vim.api.nvim_buf_add_highlight(buf, ns, "AugmentCodeBlock", i - 1, 0, -1)
      else
        -- Highlight headers
        if line:match("^#%s+") then
          vim.api.nvim_buf_add_highlight(buf, ns, "AugmentFloatTitle", i - 1, 0, -1)
        end
        
        -- Highlight bold text
        for start_pos, end_pos in line:gmatch("()%*%*(.-)%*%*()") do
          vim.api.nvim_buf_add_highlight(buf, ns, "Bold", i - 1, start_pos - 1, end_pos - 3)
        end
        
        -- Highlight italic text
        for start_pos, end_pos in line:gmatch("()%*(.-)%*()") do
          vim.api.nvim_buf_add_highlight(buf, ns, "Italic", i - 1, start_pos - 1, end_pos - 2)
        end
      end
    end
  end
  
  -- Apply highlighting
  apply_highlighting(content)
  
  -- Add scrolling keymaps if content is long
  if #vim.split(content, "\n") > opts.height then
    vim.api.nvim_buf_set_keymap(buf, 'n', '<Down>', [[<C-d>]], { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<Up>', [[<C-u>]], { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'j', [[j]], { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'k', [[k]], { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'G', [[G]], { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'gg', [[gg]], { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '<cmd>close<CR>', { noremap = true, silent = true })
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<cmd>close<CR>', { noremap = true, silent = true })
  end
  
  return result
end

-- Show a hover window at cursor position
function M.show_hover(content, opts)
  opts = opts or {}
  
  -- Set position to cursor
  opts.position = 'cursor'
  
  -- Default options
  opts.width = opts.width or math.min(80, M.config.hover.max_width)
  opts.height = opts.height or math.min(20, M.config.hover.max_height)
  opts.focus = opts.focus or M.config.hover.auto_focus
  
  -- Create the hover window
  local result = M.show_markdown(content, opts)
  
  -- Set up auto-close on cursor move if configured
  if M.config.hover.close_on_cursor_move then
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local bufnr = vim.api.nvim_get_current_buf()
    
    -- Create autocommand to close on cursor move
    local group = vim.api.nvim_create_augroup("AugmentHoverClose" .. result.id, { clear = true })
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = group,
      buffer = bufnr,
      callback = function()
        local new_pos = vim.api.nvim_win_get_cursor(0)
        if new_pos[1] ~= cursor_pos[1] or new_pos[2] ~= cursor_pos[2] then
          -- Close hover window
          if vim.api.nvim_win_is_valid(result.win) then
            vim.api.nvim_win_close(result.win, true)
          end
          
          -- Clean up autocommand
          vim.api.nvim_del_augroup_by_id(group)
        end
      end
    })
    
    -- Also close on InsertEnter
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = group,
      buffer = bufnr,
      callback = function()
        if vim.api.nvim_win_is_valid(result.win) then
          vim.api.nvim_win_close(result.win, true)
        end
        
        -- Clean up autocommand
        vim.api.nvim_del_augroup_by_id(group)
      end
    })
  end
  
  return result
end

-- Create a simple command palette
function M.command_palette(items, opts)
  opts = opts or {}
  
  if not items or #items == 0 then
    log.warn("Command palette called with no items")
    return
  end
  
  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  
  -- Calculate height based on number of items
  local height = math.min(#items + 2, 15)
  
  -- Find max item length for width
  local max_length = 0
  for _, item in ipairs(items) do
    max_length = math.max(max_length, #item.label + (item.description and #item.description + 3 or 0))
  end
  
  -- Set width with some padding
  local width = math.min(max_length + 4, 80)
  
  -- Set up selection state
  local selected_index = 1
  
  -- Function to render items
  local function render_items()
    -- Clear buffer
    vim.api.nvim_buf_set_option(buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    
    -- Add items
    for i, item in ipairs(items) do
      local prefix = i == selected_index and "> " or "  "
      local line = prefix .. item.label
      
      -- Add description if available
      if item.description then
        -- Pad to align descriptions
        local padding = width - #line - #item.description - 2
        line = line .. string.rep(" ", padding) .. "(" .. item.description .. ")"
      end
      
      vim.api.nvim_buf_set_lines(buf, i - 1, i - 1, false, {line})
      
      -- Add highlighting if selected
      if i == selected_index then
        vim.api.nvim_buf_add_highlight(buf, ns, "AugmentStatusActive", i - 1, 0, 2)
        vim.api.nvim_buf_add_highlight(buf, ns, "AugmentFloatTitle", i - 1, 2, 2 + #item.label)
      end
    end
    
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  end
  
  -- Initial render
  render_items()
  
  -- Create window
  local float_result = M.create_float({
    buffer = buf,
    width = width,
    height = height,
    position = opts.position or "center",
    focus = true,
    title = opts.title or "Command Palette",
  })
  
  local win = float_result.win
  
  -- Set up keymappings
  vim.api.nvim_buf_set_keymap(buf, 'n', 'j', '', {
    noremap = true,
    callback = function()
      selected_index = math.min(selected_index + 1, #items)
      render_items()
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', 'k', '', {
    noremap = true,
    callback = function()
      selected_index = math.max(selected_index - 1, 1)
      render_items()
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
    noremap = true,
    callback = function()
      local selected = items[selected_index]
      if selected and selected.action then
        -- Close the window
        vim.api.nvim_win_close(win, true)
        
        -- Execute the action
        selected.action()
      end
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '', {
    noremap = true,
    callback = function()
      vim.api.nvim_win_close(win, true)
      if opts.on_cancel then
        opts.on_cancel()
      end
    end
  })
  
  vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '', {
    noremap = true,
    callback = function()
      vim.api.nvim_win_close(win, true)
      if opts.on_cancel then
        opts.on_cancel()
      end
    end
  })
  
  return float_result
end

-- Set up the module
function M.setup(opts)
  -- Merge options
  if opts then
    for category, values in pairs(opts) do
      if M.config[category] then
        for k, v in pairs(values) do
          M.config[category][k] = v
        end
      end
    end
  end
  
  -- Set up highlights
  setup_highlights()
  
  log.info("UI module initialized")
  return true
end

-- Initialize with default config
M.setup()

return M