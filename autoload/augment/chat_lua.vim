" Copyright (c) 2025 Augment
" MIT License - See LICENSE.md for full terms

" This file contains wrappers for Lua-based chat functionality

" Send a chat message
function! augment#chat_lua#SendMessage(message, selected_text) abort
  if has('nvim')
    lua << EOF
    local ok, chat = pcall(require, 'augment/chat')
    if ok then
      chat.send_message(vim.fn.eval('a:message'), vim.fn.eval('a:selected_text'))
    else
      vim.notify('Failed to load chat module: ' .. tostring(chat), vim.log.levels.ERROR)
    end
EOF
  endif
endfunction

" Reset chat history
function! augment#chat_lua#Reset() abort
  if has('nvim')
    lua << EOF
    local ok, chat = pcall(require, 'augment/chat')
    if ok then
      chat.reset()
    end
EOF
  endif
endfunction

" Toggle chat panel
function! augment#chat_lua#Toggle() abort
  if has('nvim')
    lua << EOF
    local ok, chat = pcall(require, 'augment/chat')
    if ok then
      chat.toggle()
    end
EOF
  endif
endfunction

" Get selected text
function! augment#chat_lua#GetSelectedText() abort
  if has('nvim')
    let selected_text = ''
    lua << EOF
    local ok, chat = pcall(require, 'augment/chat')
    if ok then
      vim.g._augment_selected_text = chat.get_selected_text()
    end
EOF
    return get(g:, '_augment_selected_text', '')
  endif
  return ''
endfunction

" Attempt to use Lua chat implementation
function! augment#chat_lua#IsAvailable() abort
  if has('nvim') && (exists('g:augment_use_lua_chat') && g:augment_use_lua_chat || 
                   \ exists('g:augment_use_lua') && g:augment_use_lua)
    let l:available = 0
    lua << EOF
    local ok, chat = pcall(require, 'augment/chat')
    if ok and type(chat.send_message) == 'function' then
      vim.g._augment_chat_available = 1
    else
      vim.g._augment_chat_available = 0
    end
EOF
    return g:_augment_chat_available
  endif
  return 0
endfunction