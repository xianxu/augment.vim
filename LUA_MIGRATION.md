# Augment.vim Lua Migration Plan

This document outlines the plan for migrating Augment.vim from VimScript to Lua for Neovim.

## Current Status

The VimScript implementation is fully functional. We're beginning to establish a Lua structure for future development.

## Structure

Planned module structure:

```
lua/
├── augment.lua         # Original compatibility layer for Neovim LSP
└── augment/
    ├── init.lua        # Main entry point and setup
    ├── core.lua        # Core functionality (coming soon)
    ├── client.lua      # LSP client interface (coming soon)
    ├── suggestion.lua  # Suggestion handling (coming soon)
    ├── chat.lua        # Chat functionality (coming soon)
    ├── log.lua         # Logging utilities (coming soon)
    └── version.lua     # Version tracking (coming soon)
```

## Migration Strategy

We'll follow an incremental approach:

1. Establish basic module structure
2. Implement core functionality in parallel with VimScript
3. Add opt-in mechanism for Lua implementation
4. Gradually replace VimScript functionality
5. Add Neovim-specific improvements

## Next Steps

* Build out core.lua with basic functionality
* Create client.lua to handle LSP interactions
* Implement suggestion handling with Neovim extmarks

Each step will be tested thoroughly before moving to the next.