# Neovim-Specific Enhancements for Augment.vim

This plugin now includes a comprehensive set of Neovim-specific UI enhancements when running in Neovim. These features use Neovim's Lua API and native capabilities to provide a significantly improved user experience over the base VimScript implementation.

## Enhanced UI Features

### General UI Improvements

- **Custom UI Module**: A dedicated `ui.lua` module for consistent floating windows, notifications, and enhanced visual elements
- **Theming**: Consistent color scheme across all UI components
- **Notifications**: Non-intrusive notification system with customizable timeout and position
- **Progress Indicators**: Animated progress indicators for long-running operations
- **Command Palette**: Interactive command palette for selecting from multiple options

### Enhanced Chat Interface

- **Improved Floating Windows**: Better positioning, border styles, and transparency options
- **Enhanced Markdown Rendering**: Using Treesitter for syntax highlighting in code blocks
- **Better Streaming**: Smoother streaming experience with cursor following
- **Interactive Message Input**: Dedicated input dialog with improved UX
- **Loading Animations**: Visual feedback during message processing
- **Icons**: Visual indicators for different message types and states

### Advanced Hover Documentation

- **Enhanced Hover Windows**: Better formatting and positioning of hover documentation
- **Signature Help**: Interactive signature help during function input
- **Diagnostic Hover**: Detailed diagnostic information at cursor position
- **Syntax Highlighting**: Code in documentation is properly highlighted
- **Interactive Navigation**: Keyboard shortcuts for scrolling long documentation

### Diagnostics Visualization

- **Virtual Text**: Enhanced virtual text for showing diagnostics inline
- **Signs**: Custom signs in the sign column for different diagnostic levels
- **Underlines**: Customizable underlines for diagnostics
- **Floating Windows**: Detailed diagnostic information in floating windows
- **Navigation**: Keymaps for navigating between diagnostics

## How to Enable

These enhanced features are hidden behind feature flags to maintain compatibility with Vim. To enable the Neovim-specific enhancements, add the following to your configuration:

```vim
" Enable Lua-based implementation
let g:augment_use_lua = v:true

" Enable enhanced UI features (Neovim-only)
let g:augment_use_enhanced_ui = v:true
```

Or in Lua:

```lua
vim.g.augment_use_lua = true
vim.g.augment_use_enhanced_ui = true
```

## Configuration

The enhanced UI can be configured through Lua. Here's an example configuration:

```lua
require('augment').setup({
  features = {
    enhanced_ui = true,  -- Enable enhanced UI
  },
  ui = {
    float = {
      border = 'rounded',  -- Border style for floating windows
      max_width = 100,     -- Maximum width
      max_height = 30,     -- Maximum height
      winblend = 10        -- Window transparency (0-100)
    },
    markdown = {
      use_treesitter = true,  -- Use treesitter for syntax highlighting
      syntax_highlight = true, -- Highlight code blocks
      conceal = true,         -- Use concealing for markdown syntax
    },
    notifications = {
      enabled = true,         -- Whether to show notifications
      timeout = 5000,         -- Default timeout (ms)
      position = 'top-right'  -- Position for notifications
    }
  }
})
```

## Requirements

To use these enhanced features, you need:

- Neovim 0.7.0 or newer
- Treesitter installed for optimal code highlighting
- A terminal that supports Unicode characters for icons

## Fallbacks

When running in Vim or when enhanced UI features are disabled, the plugin will automatically fall back to the standard VimScript implementation with basic UI elements.