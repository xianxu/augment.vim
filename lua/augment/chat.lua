-- Copyright (c) 2025 Augment
-- MIT License - See LICENSE.md for full terms

local log = require('augment_log')
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

-- Set up markdown highlighting if available
function M.setup()
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

-- Apply basic markdown formatting to text
local function format_markdown(text)
  -- Replace code blocks with syntax highlighting
  text = text:gsub("```(%w*)(.-)\n```", function(lang, code)
    return "```" .. lang .. code .. "\n```"
  end)
  
  return text
end

-- Render a markdown string in the buffer with basic formatting
local function render_markdown(bufnr, text, start_line)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  
  -- Protect against errors
  return pcall(function()
    -- Make the buffer modifiable
    vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
    
    -- Split the text into lines
    local lines = {}
    for line in text:gmatch("([^\n]*)\n?") do
      table.insert(lines, line)
    end
    
    -- Insert the lines
    vim.api.nvim_buf_set_lines(bufnr, start_line, start_line, false, lines)
    
    -- Highlight code blocks
    local in_code_block = false
    local code_start = 0
    local code_end = 0
    
    for i, line in ipairs(lines) do
      local line_idx = start_line + i - 1
      
      -- Check for code block markers
      if line:match("^```") then
        if not in_code_block then
          in_code_block = true
          code_start = line_idx
        else
          in_code_block = false
          code_end = line_idx
          
          -- Apply highlighting to the code block (safely)
          pcall(function()
            vim.api.nvim_buf_add_highlight(bufnr, -1, "AugmentChatCodeBlock", code_start, 0, -1)
            for j = code_start + 1, code_end - 1 do
              vim.api.nvim_buf_add_highlight(bufnr, -1, "AugmentChatCodeBlock", j, 0, -1)
            end
            vim.api.nvim_buf_add_highlight(bufnr, -1, "AugmentChatCodeBlock", code_end, 0, -1)
          end)
        end
      elseif in_code_block then
        -- Inside a code block
        pcall(function()
          vim.api.nvim_buf_add_highlight(bufnr, -1, "AugmentChatCodeBlock", line_idx, 0, -1)
        end)
      end
    end
  end)
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
  vim.api.nvim_buf_set_keymap(chat_buffer, 'n', 'q', '<cmd>lua require("augment.chat").toggle()<CR>', 
    { noremap = true, silent = true, desc = "Close chat panel" })
  
  vim.api.nvim_buf_set_keymap(chat_buffer, 'n', '<CR>', '<cmd>lua require("augment.chat").prompt_message()<CR>', 
    { noremap = true, silent = true, desc = "New chat message" })
    
  vim.api.nvim_buf_set_keymap(chat_buffer, 'n', '<leader>n', '<cmd>lua require("augment.chat").reset()<CR>', 
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
  
  log.info("Created chat buffer")
  return chat_buffer
end

-- Create or show chat window
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
  
  -- Determine window position based on panel state
  local win_config = {}
  if panel_state.position == "right" then
    win_config = {
      relative = 'editor',
      width = panel_state.width,
      height = editor_height - 6,
      col = editor_width - panel_state.width,
      row = 1,
      style = 'minimal',
      border = 'rounded'
    }
  elseif panel_state.position == "left" then
    win_config = {
      relative = 'editor',
      width = panel_state.width,
      height = editor_height - 6,
      col = 0,
      row = 1,
      style = 'minimal',
      border = 'rounded'
    }
  elseif panel_state.position == "bottom" then
    win_config = {
      relative = 'editor',
      width = editor_width,
      height = math.floor(editor_height / 3),
      col = 0,
      row = editor_height - math.floor(editor_height / 3) - 3,
      style = 'minimal',
      border = 'rounded'
    }
  else -- top
    win_config = {
      relative = 'editor',
      width = editor_width,
      height = math.floor(editor_height / 3),
      col = 0,
      row = 1,
      style = 'minimal',
      border = 'rounded'
    }
  end
  
  -- Create window
  chat_window = vim.api.nvim_open_win(chat_buffer, true, win_config)
  
  -- Set window options
  vim.api.nvim_win_set_option(chat_window, 'wrap', true)
  vim.api.nvim_win_set_option(chat_window, 'conceallevel', 2)
  vim.api.nvim_win_set_option(chat_window, 'foldenable', false)
  vim.api.nvim_win_set_option(chat_window, 'winhl', 'Normal:Normal,FloatBorder:FloatBorder')
  
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

-- Prompt for a new message
function M.prompt_message()
  local message = vim.fn.input({
    prompt = "Message: ",
    completion = "file",
    cancelreturn = ""
  })
  
  if message == "" then
    return false
  end
  
  M.send_message(message)
  return true
end

-- Set loading state
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
      vim.api.nvim_buf_set_lines(chat_buffer, line_count, line_count, false, 
        {"", "*Augment is thinking...*", ""})
      pcall(function()
        vim.api.nvim_buf_add_highlight(chat_buffer, -1, "AugmentChatLoading", line_count + 1, 0, -1)
      end)
    else
      -- Remove loading indicator if it exists
      if line_count > 1 then
        local last_line = vim.api.nvim_buf_get_lines(chat_buffer, line_count - 1, line_count, false)[1]
        if last_line == "*Augment is thinking...*" then
          vim.api.nvim_buf_set_lines(chat_buffer, line_count - 2, line_count, false, {})
        end
      end
    end
    
    -- Make buffer non-modifiable again
    pcall(function()
      vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', false)
    end)
  end)
end

-- Append user message to chat
function M.append_message(message)
  ensure_chat_buffer()
  M.open_chat_panel()
  
  -- Get line count
  local line_count = vim.api.nvim_buf_line_count(chat_buffer)
  
  -- Add user message
  vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', true)
  vim.api.nvim_buf_set_lines(chat_buffer, line_count, line_count, false, {
    "**You:** " .. message,
    ""
  })
  
  -- Add highlight
  vim.api.nvim_buf_add_highlight(chat_buffer, -1, "AugmentChatUser", line_count, 0, 8)
  
  vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', false)
  
  -- Set loading state
  set_loading(true)
  
  -- Scroll to the end
  vim.api.nvim_win_set_cursor(chat_window, {line_count + 2, 0})
end

-- Append AI response to chat
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
    
    -- Format response with markdown
    local formatted_text = format_markdown(response)
    
    -- Make sure buffer is modifiable
    pcall(function()
      vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', true)
    end)
    
    -- Add AI message header
    vim.api.nvim_buf_set_lines(chat_buffer, line_count, line_count, false, {"**Augment:**", ""})
    
    -- Add highlight
    vim.api.nvim_buf_add_highlight(chat_buffer, -1, "AugmentChatAssistant", line_count, 0, 11)
    
    -- Render the markdown content with error handling
    local render_success = pcall(function()
      render_markdown(chat_buffer, formatted_text, line_count + 1)
    end)
    
    if not render_success then
      -- Fallback if rendering failed
      local lines = {}
      for line in formatted_text:gmatch("([^\n]*)\n?") do
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
      if last_line == "*Augment is thinking...*" then
        vim.api.nvim_buf_set_lines(chat_buffer, line_count - 2, line_count, false, {})
        line_count = line_count - 2
      end
    end
    
    -- Add assistant header
    vim.api.nvim_buf_set_lines(chat_buffer, line_count, line_count, false, {"**Augment:**", ""})
    vim.api.nvim_buf_add_highlight(chat_buffer, -1, "AugmentChatAssistant", line_count, 0, 11)
    
    -- Update streaming state
    streaming_active = true
    streaming_buffer = ""
    streaming_start_line = line_count + 2
    
    -- Make buffer non-modifiable
    vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', false)
  end)
end

-- Append text chunk to chat (for streaming responses)
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
    
    -- Format the text for display
    local display_text = streaming_buffer
    
    -- Make buffer modifiable
    vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', true)
    
    -- Split text into lines
    local text_lines = {}
    for line in display_text:gmatch("([^\n]*)\n?") do
      table.insert(text_lines, line)
    end
    
    -- Replace the existing content after the header
    local end_line = vim.api.nvim_buf_line_count(chat_buffer)
    if streaming_start_line <= end_line then
      vim.api.nvim_buf_set_lines(chat_buffer, streaming_start_line, end_line, false, text_lines)
    else
      -- Handle case where buffer is shorter than expected
      vim.api.nvim_buf_set_lines(chat_buffer, end_line, end_line, false, text_lines)
    end
    
    -- Apply code block highlighting
    pcall(function()
      local in_code_block = false
      local code_start = 0
      
      for i, line in ipairs(text_lines) do
        local line_idx = streaming_start_line + i - 1
        
        -- Check for code block markers
        if line:match("^```") then
          if not in_code_block then
            in_code_block = true
            code_start = line_idx
            vim.api.nvim_buf_add_highlight(chat_buffer, -1, "AugmentChatCodeBlock", line_idx, 0, -1)
          else
            in_code_block = false
            vim.api.nvim_buf_add_highlight(chat_buffer, -1, "AugmentChatCodeBlock", line_idx, 0, -1)
          end
        elseif in_code_block then
          -- Inside a code block
          vim.api.nvim_buf_add_highlight(chat_buffer, -1, "AugmentChatCodeBlock", line_idx, 0, -1)
        end
      end
    end)
    
    -- Make buffer non-modifiable
    vim.api.nvim_buf_set_option(chat_buffer, 'modifiable', false)
    
    -- Scroll to the end
    if chat_window and vim.api.nvim_win_is_valid(chat_window) then
      local curr_line = vim.api.nvim_buf_line_count(chat_buffer)
      vim.api.nvim_win_set_cursor(chat_window, {curr_line, 0})
    end
  end)
end

-- Get selected text in visual mode
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

-- Reset chat history
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
        "Type a message and press Enter to start a conversation.",
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
  
  log.info("Reset chat history")
  return true
end

-- Send a chat message to the server
function M.send_message(message, selected_text)
  -- Save the original buffer and position information BEFORE opening chat panel
  local original_bufnr = vim.api.nvim_get_current_buf()
  local original_file = vim.api.nvim_buf_get_name(original_bufnr)
  local original_uri = vim.uri_from_bufnr(original_bufnr)
  local original_cursor = vim.api.nvim_win_get_cursor(0)
  local original_pos = {
    line = original_cursor[1] - 1,
    character = original_cursor[2]
  }
  
  -- Open chat panel and append message
  M.append_message(message)
  
  -- Use the saved URI and position from the original buffer (not the chat buffer)
  local uri = original_uri
  
  -- Build request parameters with the original file location
  local params = {
    textDocumentPosition = {
      textDocument = {
        uri = uri
      },
      position = original_pos  -- Use the position from original buffer
    },
    originalFile = {
      path = original_file,
      uri = uri,
      line = original_cursor[1]
    },
    message = message,
    history = M.get_history()
  }
  
  -- Add selected text if provided
  if selected_text then
    params.selectedText = selected_text
    
    -- Get visual marks for accurate selection positions
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    
    -- Add detailed selection info
    params.selectionInfo = {
      filePath = original_file,
      startLine = start_pos[2],
      endLine = end_pos[2],
      startCol = start_pos[3],
      endCol = end_pos[3],
      lineRange = start_pos[2] == end_pos[2] 
                 and tostring(start_pos[2])
                 or (start_pos[2] .. "-" .. end_pos[2])
    }
  end
  
  -- Log the parameters for debugging (only to log file, not to user)
  log.info("Sending chat API parameters: " .. vim.inspect(params))
  
  -- Send the request
  local compat = require('augment_compat')
  local client = vim.lsp.get_active_clients()[1]
  
  if client then
    -- Use direct LSP client if available
    client.request('augment/chat', params, function(err, result)
      if err then
        log.error("Chat request error: " .. vim.inspect(err))
        set_loading(false)
        vim.schedule(function()
          vim.api.nvim_echo({{"Error in chat request: " .. err.message, "ErrorMsg"}}, true, {})
        end)
        return
      end
      
      M.handle_chat_response(result)
    end)
  else
    -- Fall back to compat layer
    compat.request(nil, 'augment/chat', params)
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

-- Handle chat response from server
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
    else
      log.warn("Invalid chat response: " .. vim.inspect(params))
    end
  end)
  
  return true
end

-- Handle streaming chat chunk from server
function M.handle_chat_chunk(params)
  log.debug("Received chat chunk")
  
  -- Handle in a protected call
  pcall(function()
    if params and params.text then
      -- Handle potential newlines in the text chunk
      local text = params.text
      M.append_text(text)
    else
      log.warn("Invalid chat chunk: " .. vim.inspect(params))
    end
  end)
  
  return true
end

-- Initialize module
M.setup()

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

return M
