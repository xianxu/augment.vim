-- Copyright (c) 2025 Augment
-- MIT License - See LICENSE.md for full terms

-- Enhanced chat interface with Neovim-specific features

local log = require('augment_log')
local ui = require('augment/ui')
local M = {}

-- Chat state
local chat_history = {}
local chat_buffer = nil
local chat_window = nil
local current_uri = nil
local is_loading = false
local request_id = nil
local markdown = nil

-- Track chat panel state
local panel_state = {
  width = 80,
  height = 0, -- Auto-sized based on content
  position = "right", -- right, left, top, bottom
  visible = false
}

-- Enhanced configuration with Neovim-specific options
local config = {
  -- Panel configuration
  panel = {
    position = "right",    -- right, left, top, bottom
    width = 80,            -- Width of the panel
    height = 0,            -- Height (0 for auto)
    border = "rounded",    -- Border style
    winblend = 10,         -- Window transparency (0-100)
    zindex = 50,           -- Z-index for floating window
  },
  
  -- Markdown rendering
  markdown = {
    use_treesitter = true, -- Use treesitter for syntax highlighting
    syntax_highlight = true, -- Highlight code blocks
    conceal = true,         -- Use concealing for markdown syntax
  },
  
  -- Streaming configuration
  streaming = {
    enabled = true,        -- Enable streaming responses
    cursor_follow = true,  -- Follow cursor during streaming
  },
  
  -- Visual elements
  visual = {
    icons = {
      user = "󰀄 ",        -- Icon for user messages
      assistant = "󰚩 ",   -- Icon for assistant messages
      loading = "󰔟 ",     -- Loading indicator
      success = "󰄬 ",     -- Success indicator
      error = "󰀨 ",       -- Error indicator
    },
    syntax_theme = "dracula", -- Theme for code blocks
  }
}

-- Try to load markdown parser for better rendering
local function load_markdown()
  local ok, treesitter = pcall(require, 'vim.treesitter')
  if not ok then
    log.warn("Treesitter not available for markdown highlighting")
    return false
  end
  
  -- Check if markdown parser is available
  local parser_ok = treesitter.language.require_language("markdown", nil, true)
  if not parser_ok then
    log.warn("Markdown parser not available")
    return false
  end
  
  log.info("Markdown parser loaded")
  return true
end

-- Set up chat interface enhancements
function M.setup(opts)
  -- Merge configuration
  if opts then
    for category, values in pairs(opts) do
      if config[category] then
        for k, v in pairs(values) do
          config[category][k] = v
        end
      end
    end
  end
  
  -- Update panel state from config
  panel_state.position = config.panel.position
  panel_state.width = config.panel.width
  
  -- Try to load markdown parser
  markdown = load_markdown()
  
  -- Create highlight groups for chat
  vim.api.nvim_set_hl(0, 'AugmentChatUser', {
    fg = '#6272a4',
    bold = true,
    default = true
  })
  
  vim.api.nvim_set_hl(0, 'AugmentChatAssistant', {
    fg = '#50fa7b',
    bold = true,
    default = true
  })
  
  vim.api.nvim_set_hl(0, 'AugmentChatLoading', {
    fg = '#f1fa8c',
    italic = true,
    default = true
  })
  
  vim.api.nvim_set_hl(0, 'AugmentChatHeader', {
    bg = '#44475a',
    default = true
  })
  
  vim.api.nvim_set_hl(0, 'AugmentChatCodeBlock', {
    bg = '#282a36',
    default = true
  })
  
  -- Attempt to register with compat layer
  local compat = require('augment_compat')
  if compat.register_handler then
    compat.register_handler('augment/chatResponse', function(params)
      M.handle_chat_response(params)
    end)
    
    compat.register_handler('augment/chatChunk', function(params)
      M.handle_chat_chunk(params)
    end)
    
    log.info("Registered chat handlers")
  end
  
  return true
end

-- Get current URI
function M.get_uri()
  if not current_uri then
    current_uri = vim.uri_from_bufnr(0)
  end
  return current_uri
end

-- Save current URI
function M.save_uri()
  current_uri = vim.uri_from_bufnr(0)
  return current_uri
end

-- Get chat history
function M.get_history()
  return chat_history
end

-- Create chat buffer if it doesn't exist
local function ensure_chat_buffer()
  if chat_buffer and vim.api.nvim_buf_is_valid(chat_buffer) then
    return chat_buffer
  end
  
  -- Create new buffer
  chat_buffer = vim.api.nvim_create_buf(false, true)
  
  -- Set buffer options
  vim.api.nvim_buf_set_option(chat_buffer, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(chat_buffer, 'swapfile', false)
  vim.api.nvim_buf_set_option(chat_buffer, 'bufhidden', 'hide')
  vim.api.nvim_buf_set_option(chat_buffer, 'filetype', 'markdown')
  vim.api.nvim_buf_set_name(chat_buffer, 'Augment Chat')
  
  -- Set buffer-local mappings
  vim.api.nvim_buf_set_keymap(chat_buffer, 'n', 'q', '<cmd>lua require("augment.chat_enhanced").toggle()<CR>', 
    { noremap = true, silent = true, desc = "Close chat panel" })
  
  vim.api.nvim_buf_set_keymap(chat_buffer, 'n', '<CR>', '<cmd>lua require("augment.chat_enhanced").prompt_message()<CR>', 
    { noremap = true, silent = true, desc = "New chat message" })
    
  vim.api.nvim_buf_set_keymap(chat_buffer, 'n', '<leader>n', '<cmd>lua require("augment.chat_enhanced").reset()<CR>', 
    { noremap = true, silent = true, desc = "Start new conversation" })
  
  -- Add welcome message
  local welcome_lines = {
    "# Augment Chat",
    "",
    "Type a message and press Enter to start a conversation.",
    "- Press <Enter> to send a new message",
    "- Press <leader>n to start a new conversation",
    "- Press q to close the chat panel",
    ""
  }
  
  vim.api.nvim_buf_set_lines(chat_buffer, 0, -1, false, welcome_lines)
  vim.api.nvim_buf_add_highlight(chat_buffer, -1, "AugmentChatHeader", 0, 0, -1)
  
  -- Enable conceal if configured
  if config.markdown.conceal then
    vim.api.nvim_buf_set_option(chat_buffer, 'conceallevel', 2)
  end
  
  log.info("Created chat buffer")
  return chat_buffer
end

-- Create or show chat window using the enhanced UI
function M.open_chat_panel()
  -- Ensure we have a buffer
  ensure_chat_buffer()
  
  -- If window exists and is valid, just focus it
  if chat_window and vim.api.nvim_win_is_valid(chat_window) then
    vim.api.nvim_set_current_win(chat_window)
    return chat_window
  end
  
  -- Calculate window dimensions
  local editor_width = vim.o.columns
  local editor_height = vim.o.lines
  
  -- Set up window options based on panel position
  local win_opts = {
    buffer = chat_buffer,
    focus = true,
    border = config.panel.border,
    zindex = config.panel.zindex,
    winblend = config.panel.winblend,
    title = " Augment Chat ",
    title_pos = "center",
  }
  
  -- Determine window position based on panel state
  if panel_state.position == "right" then
    win_opts.width = panel_state.width
    win_opts.height = editor_height - 4
    win_opts.row = 1
    win_opts.col = editor_width - panel_state.width - 2
    win_opts.relative = "editor"
  elseif panel_state.position == "left" then
    win_opts.width = panel_state.width
    win_opts.height = editor_height - 4
    win_opts.row = 1
    win_opts.col = 1
    win_opts.relative = "editor"
  elseif panel_state.position == "bottom" then
    win_opts.width = editor_width
    win_opts.height = math.floor(editor_height / 3)
    win_opts.row = editor_height - math.floor(editor_height / 3) - 3
    win_opts.col = 0
    win_opts.relative = "editor"
  else -- top
    win_opts.width = editor_width
    win_opts.height = math.floor(editor_height / 3)
    win_opts.row = 1
    win_opts.col = 0
    win_opts.relative = "editor"
  end
  
  -- Use the UI module to create a floating window
  local float_result = ui.create_float(win_opts)
  chat_window = float_result.win
  
  -- Set window options
  vim.api.nvim_win_set_option(chat_window, 'wrap', true)
  vim.api.nvim_win_set_option(chat_window, 'foldenable', false)
  
  panel_state.visible = true
  log.info("Opened chat panel: " .. panel_state.position)
  
  return chat_window
end

-- Toggle chat panel visibility
function M.toggle()
  if panel_state.visible and chat_window and vim.api.nvim_win_is_valid(chat_window) then
    vim.api.nvim_win_close(chat_window, true)
    chat_window = nil
    panel_state.visible = false
    log.info("Closed chat panel")
  else
    M.open_chat_panel()
  end
end

-- Enhanced message input with UI
function M.prompt_message()
  -- Create a custom input dialog using the UI module
  local buf = vim.api.nvim_create_buf(false, true)
  
  -- Set up buffer with instructions
  vim.api.nvim_buf_set_option(buf, 'buftype', 'prompt')
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  
  -- Set prompt prefix and callback
  vim.fn.prompt_setprompt(buf, config.visual.icons.user .. " ")
  
  -- Create floating window for input
  local float_result = ui.create_float({
    buffer = buf,
    width = 70,
    height = 3,
    position = "center",
    focus = true,
    title = "Enter your message",
    border = "rounded"
  })
  
  -- Focus buffer for input
  vim.api.nvim_set_current_buf(buf)
  
  -- Start insert mode
  vim.cmd('startinsert!')
  
  -- Set up callback for when Enter is pressed
  vim.keymap.set({"i", "n"}, "<CR>", function()
    -- Get message text (without the prompt)
    local text = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
    text = text:gsub("^" .. vim.pesc(config.visual.icons.user .. " "), "")
    
    -- Close the input window
    vim.api.nvim_win_close(float_result.win, true)
    
    -- Only send if not empty
    if text ~= "" then
      M.send_message(text)
    end
  end, { buffer = buf, noremap = true })
  
  -- Set up Escape to cancel
  vim.keymap.set({"i", "n"}, "<Esc>", function()
    vim.api.nvim_win_close(float_result.win, true)
  end, { buffer = buf, noremap = true })
  
  return buf
end

-- Set loading state with enhanced visualization
local function set_loading(state)
  is_loading = state
  
  if not chat_buffer or not vim.api.nvim_buf_is_valid(chat_buffer) then
    return
  end
  
  -- Do everything in a protected call to avoid errors
  pcall(function()
    -- Get line count
    local line_count = vim.api.nvim_buf_line_count(chat_buffer)
    
    -- Make buffer modifiable
    pcall(function()
      vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', true)
    end)
    
    if state then
      -- Add loading indicator at the end
      local loading_text = config.visual.icons.loading .. " Augment is thinking..."
      vim.api.nvim_buf_set_lines(chat_buffer, line_count, line_count, false, 
        {"", loading_text, ""})
      pcall(function()
        vim.api.nvim_buf_add_highlight(chat_buffer, -1, "AugmentChatLoading", line_count + 1, 0, -1)
      end)
      
      -- Start a loading animation
      if chat_window and vim.api.nvim_win_is_valid(chat_window) then
        -- Create a small status progress in window title
        local loading_chars = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
        local loading_idx = 1
        
        -- Create a timer for animation
        local timer = vim.loop.new_timer()
        timer:start(0, 100, function()
          vim.schedule(function()
            if not is_loading or not vim.api.nvim_win_is_valid(chat_window) then
              timer:stop()
              return
            end
            
            -- Update loading animation
            local title = " Augment Chat " .. loading_chars[loading_idx] .. " "
            pcall(function()
              vim.api.nvim_win_set_config(chat_window, { title = title })
            end)
            
            -- Update index
            loading_idx = loading_idx % #loading_chars + 1
          end)
        end)
      end
    else
      -- Remove loading indicator if it exists
      if line_count > 1 then
        local last_line = vim.api.nvim_buf_get_lines(chat_buffer, line_count - 1, line_count, false)[1]
        if last_line:match("Augment is thinking") then
          vim.api.nvim_buf_set_lines(chat_buffer, line_count - 2, line_count, false, {})
        end
      end
      
      -- Reset window title
      if chat_window and vim.api.nvim_win_is_valid(chat_window) then
        pcall(function()
          vim.api.nvim_win_set_config(chat_window, { title = " Augment Chat " })
        end)
      end
    end
    
    -- Make buffer non-modifiable again
    pcall(function()
      vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', false)
    end)
  end)
end

-- Append user message to chat with enhanced formatting
function M.append_message(message)
  ensure_chat_buffer()
  M.open_chat_panel()
  
  -- Get line count
  local line_count = vim.api.nvim_buf_line_count(chat_buffer)
  
  -- Format user message with icon
  local formatted_message = config.visual.icons.user .. "**You:** " .. message
  
  -- Add user message
  vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', true)
  vim.api.nvim_buf_set_lines(chat_buffer, line_count, line_count, false, {
    formatted_message,
    ""
  })
  
  -- Add highlight
  vim.api.nvim_buf_add_highlight(chat_buffer, -1, "AugmentChatUser", line_count, 0, #config.visual.icons.user + 8)
  
  vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', false)
  
  -- Set loading state
  set_loading(true)
  
  -- Scroll to the end
  vim.api.nvim_win_set_cursor(chat_window, {line_count + 2, 0})
end

-- Enhance markdown rendering with treesitter if available
local function render_enhanced_markdown(buffer, text, start_line)
  -- Check for buffer validity
  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    return false
  end
  
  -- Protect against errors
  return pcall(function()
    -- Make buffer modifiable
    vim.api.nvim_buf_set_option(buffer, 'modifiable', true)
    
    -- Split the text into lines
    local lines = {}
    for line in text:gmatch("([^\n]*)\n?") do
      table.insert(lines, line)
    end
    
    -- Insert the lines
    vim.api.nvim_buf_set_lines(buffer, start_line, start_line, false, lines)
    
    -- Process code blocks for syntax highlighting
    local in_code_block = false
    local code_start = 0
    local code_end = 0
    local lang = nil
    
    for i, line in ipairs(lines) do
      local line_idx = start_line + i - 1
      
      -- Check for code block markers
      if line:match("^```") then
        if not in_code_block then
          in_code_block = true
          code_start = line_idx
          -- Extract language if present
          lang = line:match("^```(%w+)")
          
          -- Highlight the code block marker
          vim.api.nvim_buf_add_highlight(buffer, -1, "AugmentChatCodeBlock", line_idx, 0, -1)
        else
          in_code_block = false
          code_end = line_idx
          
          -- Highlight the code block
          for j = code_start, code_end do
            vim.api.nvim_buf_add_highlight(buffer, -1, "AugmentChatCodeBlock", j, 0, -1)
          end
          
          -- Apply syntax highlighting with treesitter if available and language specified
          if config.markdown.use_treesitter and markdown and lang and lang ~= "" then
            pcall(function()
              -- Collect the code from the block (excluding markers)
              local code_lines = {}
              for j = code_start + 1, code_end - 1 do
                table.insert(code_lines, lines[j - start_line + 1])
              end
              
              -- Join the lines into a single string
              local code_text = table.concat(code_lines, "\n")
              
              -- Use treesitter for syntax highlighting
              local ok, parser = pcall(vim.treesitter.get_string_parser, code_text, lang)
              if ok and parser then
                parser:parse()
                
                -- Apply highlights from the parser
                parser:for_each_tree(function(tree, lang_tree)
                  local highlighter = vim.treesitter.highlighter.new(tree, lang_tree)
                  -- Apply the highlights for the lines in the code block
                  for j = code_start + 1, code_end - 1 do
                    highlighter:highlight(buffer, j - (code_start + 1))
                  end
                end)
              end
            end)
          end
        end
      elseif in_code_block then
        -- Inside a code block
        vim.api.nvim_buf_add_highlight(buffer, -1, "AugmentChatCodeBlock", line_idx, 0, -1)
      else
        -- Highlight markdown syntax outside of code blocks
        
        -- Headers
        if line:match("^#%s+") then
          local level = line:match("^(#+)%s+")
          if level then
            vim.api.nvim_buf_add_highlight(buffer, -1, "Title", line_idx, 0, #level + 1)
          end
        end
        
        -- Bold text
        local bold_start = 1
        while true do
          local s, e = line:find("%*%*.-(%*%*)", bold_start)
          if not s then break end
          vim.api.nvim_buf_add_highlight(buffer, -1, "Bold", line_idx, s - 1, e)
          bold_start = e + 1
        end
        
        -- Italic text
        local italic_start = 1
        while true do
          local s, e = line:find("%*[^%*].-[^%*]%*", italic_start)
          if not s then break end
          vim.api.nvim_buf_add_highlight(buffer, -1, "Italic", line_idx, s - 1, e)
          italic_start = e + 1
        end
        
        -- Links
        local link_start = 1
        while true do
          local s, e = line:find("%[.-%]%(.-%))", link_start)
          if not s then break end
          vim.api.nvim_buf_add_highlight(buffer, -1, "Underlined", line_idx, s - 1, e)
          link_start = e + 1
        end
      end
    end
  end)
end

-- Append AI response to chat with enhanced rendering
function M.append_response(response)
  if not chat_buffer or not vim.api.nvim_buf_is_valid(chat_buffer) then
    return
  end
  
  -- Wrap everything in pcall to handle errors gracefully
  pcall(function()
    -- Get line count
    local line_count = vim.api.nvim_buf_line_count(chat_buffer)
    
    -- Remove loading indicator
    set_loading(false)
    
    -- Make sure buffer is modifiable
    pcall(function()
      vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', true)
    end)
    
    -- Add AI message header with icon
    local assistant_header = config.visual.icons.assistant .. "**Augment:**"
    vim.api.nvim_buf_set_lines(chat_buffer, line_count, line_count, false, {assistant_header, ""})
    
    -- Add highlight
    vim.api.nvim_buf_add_highlight(chat_buffer, -1, "AugmentChatAssistant", line_count, 0, #assistant_header)
    
    -- Render the markdown content with enhanced rendering
    local render_success = pcall(function()
      render_enhanced_markdown(chat_buffer, response, line_count + 1)
    end)
    
    if not render_success then
      -- Fallback if rendering failed
      local lines = {}
      for line in response:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
      end
      vim.api.nvim_buf_set_lines(chat_buffer, line_count + 1, line_count + 1, false, lines)
    end
    
    -- Add spacing after response
    local new_line_count = vim.api.nvim_buf_line_count(chat_buffer)
    vim.api.nvim_buf_set_lines(chat_buffer, new_line_count, new_line_count, false, {"", ""})
    
    -- Make sure to mark buffer as non-modifiable
    pcall(function() 
      vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', false)
    end)
    
    -- Scroll to the assistant header
    if chat_window and vim.api.nvim_win_is_valid(chat_window) then
      vim.api.nvim_win_set_cursor(chat_window, {line_count, 0})
    end
  end)
end

-- Variables to track streaming state
local streaming_active = false
local streaming_buffer = ""
local streaming_start_line = 0

-- Start a new streaming response
local function start_streaming()
  if not chat_buffer or not vim.api.nvim_buf_is_valid(chat_buffer) then
    return
  end
  
  pcall(function()
    -- Get line count
    local line_count = vim.api.nvim_buf_line_count(chat_buffer)
    
    -- Make buffer modifiable
    vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', true)
    
    -- Remove loading indicator if present
    if is_loading then
      local last_line = vim.api.nvim_buf_get_lines(chat_buffer, line_count - 1, line_count, false)[1]
      if last_line and last_line:match("Augment is thinking") then
        vim.api.nvim_buf_set_lines(chat_buffer, line_count - 2, line_count, false, {})
        line_count = line_count - 2
      end
    end
    
    -- Add assistant header with icon
    local assistant_header = config.visual.icons.assistant .. "**Augment:**"
    vim.api.nvim_buf_set_lines(chat_buffer, line_count, line_count, false, {assistant_header, ""})
    vim.api.nvim_buf_add_highlight(chat_buffer, -1, "AugmentChatAssistant", line_count, 0, #assistant_header)
    
    -- Update streaming state
    streaming_active = true
    streaming_buffer = ""
    streaming_start_line = line_count + 2
    
    -- Make buffer non-modifiable
    vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', false)
  end)
end

-- Enhanced streaming text handler
function M.append_text(text)
  if not is_loading or not chat_buffer or not vim.api.nvim_buf_is_valid(chat_buffer) then
    return
  end
  
  pcall(function()
    -- Start streaming if not already active
    if not streaming_active then
      start_streaming()
    end
    
    -- Append to streaming buffer
    streaming_buffer = streaming_buffer .. text
    
    -- Make buffer modifiable
    vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', true)
    
    -- Render the markdown content with enhanced rendering
    local render_success = pcall(function()
      -- Clear existing content first
      local end_line = vim.api.nvim_buf_line_count(chat_buffer)
      if streaming_start_line <= end_line then
        vim.api.nvim_buf_set_lines(chat_buffer, streaming_start_line, end_line, false, {})
      end
      
      -- Then render new content
      render_enhanced_markdown(chat_buffer, streaming_buffer, streaming_start_line)
    end)
    
    if not render_success then
      -- Fallback if rendering failed
      local lines = {}
      for line in streaming_buffer:gmatch("([^\n]*)\n?") do
        table.insert(lines, line)
      end
      
      -- Replace the existing content after the header
      local end_line = vim.api.nvim_buf_line_count(chat_buffer)
      if streaming_start_line <= end_line then
        vim.api.nvim_buf_set_lines(chat_buffer, streaming_start_line, end_line, false, lines)
      else
        -- Handle case where buffer is shorter than expected
        vim.api.nvim_buf_set_lines(chat_buffer, end_line, end_line, false, lines)
      end
    end
    
    -- Make buffer non-modifiable
    vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', false)
    
    -- Scroll to the end if configured
    if config.streaming.cursor_follow and chat_window and vim.api.nvim_win_is_valid(chat_window) then
      local curr_line = vim.api.nvim_buf_line_count(chat_buffer)
      vim.api.nvim_win_set_cursor(chat_window, {curr_line, 0})
    end
  end)
end

-- Get selected text in visual mode with enhanced functionality
function M.get_selected_text()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  
  local start_line = start_pos[2]
  local start_col = start_pos[3]
  local end_line = end_pos[2]
  local end_col = end_pos[3]
  
  -- Get the selected lines
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  
  if #lines == 0 then
    return ''
  end
  
  -- Handle single line selection
  if start_line == end_line then
    lines[1] = string.sub(lines[1], start_col, end_col)
  else
    -- Handle multiline selection
    lines[1] = string.sub(lines[1], start_col)
    lines[#lines] = string.sub(lines[#lines], 1, end_col)
  end
  
  return table.concat(lines, '\n')
end

-- Add message to chat history
function M.append_history(message, response, id)
  table.insert(chat_history, {
    role = "user",
    content = message
  })
  
  table.insert(chat_history, {
    role = "assistant",
    content = response
  })
  
  request_id = id
  log.info("Added messages to chat history, request_id: " .. tostring(id))
  
  return #chat_history
end

-- Reset chat history with enhanced UI feedback
function M.reset()
  chat_history = {}
  request_id = nil
  
  -- Also reset streaming state
  streaming_active = false
  streaming_buffer = ""
  streaming_start_line = 0
  is_loading = false
  
  -- Clear chat buffer if it exists
  if chat_buffer and vim.api.nvim_buf_is_valid(chat_buffer) then
    pcall(function()
      vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', true)
      vim.api.nvim_buf_set_lines(chat_buffer, 0, -1, false, {
        "# Augment Chat",
        "",
        "Type a message and press Enter to start a new conversation.",
        "- Press <Enter> to send a new message",
        "- Press <leader>n to start a new conversation",
        "- Press q to close the chat panel",
        ""
      })
      pcall(function()
        vim.api.nvim_buf_add_highlight(chat_buffer, -1, "AugmentChatHeader", 0, 0, -1)
      end)
      vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', false)
    end)
  end
  
  -- Show a notification
  ui.notify("Chat conversation reset", "info", {
    timeout = 2000
  })
  
  log.info("Reset chat history")
  return true
end

-- Enhanced message sending with better error handling
function M.send_message(message, selected_text)
  -- Open chat panel and append message
  M.append_message(message)
  
  -- Get current URI
  local uri = M.get_uri()
  
  -- Get cursor position
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  local position = {
    line = cursor_pos[1] - 1,
    character = cursor_pos[2]
  }
  
  -- Build request parameters
  local params = {
    textDocumentPosition = {
      textDocument = {
        uri = uri
      },
      position = position
    },
    message = message,
    history = M.get_history()
  }
  
  -- Add selected text if provided
  if selected_text then
    params.selectedText = selected_text
  end
  
  -- Show progress indicator using the UI module
  local progress = nil
  if panel_state.visible and chat_window and vim.api.nvim_win_is_valid(chat_window) then
    -- Already showing in chat panel, no need for progress
  else
    -- Show a small progress notification
    progress = ui.progress_indicator({
      title = "Sending message...",
      width = 30,
      height = 3,
      position = "bottom-right",
      auto_close = true
    })
  end
  
  -- Send the request
  local lsp_ok, lsp = pcall(require, 'augment/lsp')
  if lsp_ok and lsp.is_running() then
    -- Use our pure Lua LSP client
    lsp.request('augment/chat', params, function(err, result)
      -- Close progress if it exists
      if progress then
        progress.close()
      end
      
      if err then
        log.error("Chat request error: " .. vim.inspect(err))
        set_loading(false)
        
        -- Show error notification
        ui.notify("Error sending message: " .. (err.message or "Unknown error"), "error", {
          timeout = 5000
        })
        
        return
      end
      
      M.handle_chat_response(result)
    end)
  else
    -- Fall back to compat layer
    local compat = require('augment_compat')
    compat.request(nil, 'augment/chat', params)
    
    -- Close progress after a delay since we can't know when it's done
    if progress then
      vim.defer_fn(function()
        progress.close()
      end, 2000)
    end
  end
  
  log.info("Sent chat message: " .. message)
  return true
end

-- Reset streaming state and complete the chat
local function finish_streaming()
  -- Only do this if streaming is active
  if not streaming_active then
    return
  end
  
  pcall(function()
    -- Add final spacing after the response
    if chat_buffer and vim.api.nvim_buf_is_valid(chat_buffer) then
      local line_count = vim.api.nvim_buf_line_count(chat_buffer)
      
      vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', true)
      vim.api.nvim_buf_set_lines(chat_buffer, line_count, line_count, false, {"", ""})
      vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', false)
    end
    
    -- Reset streaming state
    streaming_active = false
    streaming_buffer = ""
    streaming_start_line = 0
  end)
end

-- Enhanced chat response handler
function M.handle_chat_response(params)
  log.info("Received chat response")
  
  -- Handle in a protected call
  pcall(function()
    -- Stop loading indicator
    set_loading(false)
    
    -- Make sure params exists and has the expected fields
    if params and params.text then
      -- If we were streaming, finish that first
      if streaming_active then
        finish_streaming()
        
        -- Add to chat history - use the accumulated streaming buffer
        local message = params.message or ""
        local request_id = params.requestId
        M.append_history(message, streaming_buffer, request_id)
      else
        -- No streaming was happening, just do a direct response
        M.append_response(params.text)
        
        -- Add to chat history
        local message = params.message or ""
        local request_id = params.requestId
        M.append_history(message, params.text, request_id)
      end
      
      -- Show success indicator in window title briefly
      if chat_window and vim.api.nvim_win_is_valid(chat_window) then
        pcall(function()
          vim.api.nvim_win_set_config(chat_window, { title = " Augment Chat " .. config.visual.icons.success .. " " })
          
          -- Reset title after a delay
          vim.defer_fn(function()
            if chat_window and vim.api.nvim_win_is_valid(chat_window) then
              vim.api.nvim_win_set_config(chat_window, { title = " Augment Chat " })
            end
          end, 2000)
        end)
      end
    else
      log.warn("Invalid chat response: " .. vim.inspect(params))
      
      -- Show error indicator in window title briefly
      if chat_window and vim.api.nvim_win_is_valid(chat_window) then
        pcall(function()
          vim.api.nvim_win_set_config(chat_window, { title = " Augment Chat " .. config.visual.icons.error .. " " })
          
          -- Reset title after a delay
          vim.defer_fn(function()
            if chat_window and vim.api.nvim_win_is_valid(chat_window) then
              vim.api.nvim_win_set_config(chat_window, { title = " Augment Chat " })
            end
          end, 2000)
        end)
      end
    end
  end)
  
  return true
end

-- Enhanced streaming chat chunk handler
function M.handle_chat_chunk(params)
  log.debug("Received chat chunk")
  
  -- Handle in a protected call
  pcall(function()
    if params and params.text then
      -- Handle potential newlines in the text chunk
      local text = params.text
      
      -- Only process if streaming is enabled
      if config.streaming.enabled then
        M.append_text(text)
      end
    else
      log.warn("Invalid chat chunk: " .. vim.inspect(params))
    end
  end)
  
  return true
end

-- Initialize module with enhanced UI
function M.initialize(opts)
  -- Set up the module
  M.setup(opts)
  
  -- Register the module
  local compat = require('augment_compat')
  if compat.register_handler then
    compat.register_handler('augment/chatResponse', M.handle_chat_response)
    compat.register_handler('augment/chatChunk', M.handle_chat_chunk)
  end
  
  return true
end

-- Register the module
function M.register()
  -- Add to augment_compat handlers
  local compat = require('augment_compat')
  if compat.register_handler then
    compat.register_handler('augment/chatResponse', M.handle_chat_response)
    compat.register_handler('augment/chatChunk', M.handle_chat_chunk)
  end
  
  return true
end

-- Initialize with default config
M.initialize()

return M