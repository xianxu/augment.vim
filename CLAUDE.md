# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Code Style

- Follow Vim script conventions: `function!` for functions, `s:` prefix for script-local functions
- Use camelCase for function names (e.g., `augment#client#Client()`)
- Use clear, descriptive variable names
- Document functions with a brief comment above each function
- Use 4-space indentation
- Max line length ~80 characters (not strictly enforced)
- Prefix global variables with `g:augment_` (e.g., `g:augment_workspace_folders`)
- Prefix buffer-local variables with `b:_augment_` (e.g., `b:_augment_buf_tick`)
- Use `abort` keyword in function definitions for better error handling
- Use descriptive error messages with `augment#DisplayError()`

## Project Organization

- Core plugin functionality in `autoload/augment.vim`
- Feature-specific code in subdirectories (`autoload/augment/`)
- Lua interface in `lua/augment.lua`
- Entry point and command definition in `plugin/augment.vim`
- Documentation in `doc/augment.txt`

## Testing

- No formal test suite found. Test changes manually in Vim/Neovim
- Verify changes work in both Vim 9.1.0+ and Neovim 0.10.0+
- Ensure Node.js 22.0.0+ compatibility