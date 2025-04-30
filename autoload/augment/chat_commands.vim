" Copyright (c) 2025 Augment
" MIT License - See LICENSE.md for full terms

" This file contains revised chat commands to support Lua implementation

" Main chat command
function! augment#chat_commands#Chat(range, args) abort
  " Check if Augment is running
  if !exists('g:augment_initialized') || !g:augment_initialized
    echohl ErrorMsg
    echo 'The Augment plugin is not running'
    echohl None
    return
  endif

  " Check if we should use Lua-based chat
  if augment#chat_lua#IsAvailable()
    " If range arguments were provided or in visual mode, get the selected text
    if a:range == 2 || mode() ==# 'v' || mode() ==# 'V'
      let selected_text = augment#chat_lua#GetSelectedText()
    else
      let selected_text = ''
    endif

    " Use the message from the additional command arguments if provided, or prompt for a message
    let message = empty(a:args) ? input('Message: ') : a:args

    " Handle cancellation or empty input
    if message ==# '' || message =~# '^\s*$'
      redraw
      echo 'Chat cancelled'
      return
    endif

    " Send the message using Lua implementation
    call augment#chat_lua#SendMessage(message, selected_text)
    return
  endif

  " Fall back to VimScript implementation
  " If range arguments were provided (when using :Augment chat) or in visual
  " mode, get the selected text
  if a:range == 2 || mode() ==# 'v' || mode() ==# 'V'
    let selected_text = augment#chat#GetSelectedText()
  else
    let selected_text = ''
  endif

  let uri = augment#chat#GetUri()
  let history = augment#chat#GetHistory()

  " Use the message from the additional command arguments if provided, or
  " prompt the user for a message
  let message = empty(a:args) ? input('Message: ') : a:args

  " Handle cancellation or empty input
  if message ==# '' || message =~# '^\s*$'
    redraw
    echo 'Chat cancelled'
    return
  endif

  call augment#chat#OpenChatPanel()
  call augment#chat#AppendMessage(message)

  call augment#log#Info(
        \ 'Making chat request with file=' . uri
        \ . ' selected_text="' . selected_text
        \ . '"' . ' message="' . message . '"')

  let params = {
      \ 'textDocumentPosition': {
      \     'textDocument': {
      \         'uri': uri,
      \     },
      \     'position': {
      \         'line': line('.') - 1,
      \         'character': col('.') - 1,
      \     },
      \ },
      \ 'message': message,
  \ }

  " Add selected text and history if available
  if !empty(selected_text)
    let params['selectedText'] = selected_text
  endif
  if !empty(history)
    let params['history'] = history
  endif

  call augment#client#Client().Request('augment/chat', params)
endfunction

" Reset chat command
function! augment#chat_commands#ChatNew(range, args) abort
  " Check if we should use Lua-based chat
  if augment#chat_lua#IsAvailable()
    call augment#chat_lua#Reset()
  else
    call augment#chat#Reset()
  endif
endfunction

" Toggle chat panel command
function! augment#chat_commands#ChatToggle(range, args) abort
  " Check if we should use Lua-based chat
  if augment#chat_lua#IsAvailable()
    call augment#chat_lua#Toggle()
  else
    call augment#chat#Toggle()
  endif
endfunction