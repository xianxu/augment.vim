# Augment.vim Lua Migration Plan

This document outlines the plan for migrating Augment.vim from VimScript to Lua for Neovim.

## Current Status

We have an incremental, feature-by-feature approach to migrating from VimScript to Lua:

1. **Compatibility Layer**: We've created a robust `augment_compat.lua` module that provides compatibility with the existing VimScript code.

2. **Suggestion Handling**: We've implemented a Lua-based suggestion system using Neovim's extmarks API. This can be enabled with `g:augment_use_lua_suggestions = v:true`.

3. **Chat Interface**: We've created an enhanced chat interface with better markdown rendering and syntax highlighting for code blocks. This can be enabled with `g:augment_use_lua_chat = v:true`.

4. **LSP Client**: We've built a pure Lua LSP client that leverages Neovim's native LSP capabilities. This can be enabled with `g:augment_use_lua_lsp = v:true`.

5. **Logging System**: We've added a comprehensive logging system in `augment_log.lua` that writes to `~/.local/state/nvim/augment.log`.

6. **Feature Flags**: Users can selectively enable Lua features via feature flags.

## Structure

Current module structure:

```
lua/
├── augment.lua         # Original compatibility layer for Neovim LSP
├── augment_compat.lua  # Robust compatibility module with logging
├── augment_log.lua     # Logging system 
└── augment/
    ├── init.lua        # Main entry point and setup
    ├── suggestion.lua  # Suggestion handling with extmarks
    ├── chat.lua        # Enhanced chat interface
    ├── lsp.lua         # Pure Lua LSP client
    ├── core.lua        # Core functionality (coming soon)
    └── version.lua     # Version tracking (coming soon)
```

## User Configuration

### Basic Usage

To enable all Lua features:

```vim
" In .vimrc or init.vim
let g:augment_use_lua = v:true
```

### Selective Features

To enable specific Lua features:

```vim
" Enable only Lua-based suggestions
let g:augment_use_lua_suggestions = v:true

" Enable enhanced chat interface
let g:augment_use_lua_chat = v:true

" Enable pure Lua LSP client
let g:augment_use_lua_lsp = v:true
```

### Diagnostic Tools

For debugging:

```vim
" Show logs
:AugmentShowLuaLog

" Run diagnostics
:source /path/to/augment.vim/lua_diagnostic.vim
```

## Migration Strategy

We're following an incremental approach:

1. ✅ Establish compatibility layer
2. ✅ Add comprehensive logging
3. ✅ Implement suggestion handling
4. ✅ Add chat functionality
5. ✅ Implement custom LSP client
6. ⬜ Complete the transition to pure Lua

## Next Steps

* Add more Neovim-specific UI improvements
* Enhance existing features with Neovim APIs
* Add diagnostics visualization
* Complete the transition to pure Lua

Each feature can be independently enabled allowing for gradual adoption and thorough testing.