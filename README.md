# outlineasy.nvim

LSP symbol outline sidebar for Neovim, rendered by [treeasy.nvim](https://github.com/you/treeasy.nvim).

Three scopes — **file**, **module**, **all** — let you navigate symbols scoped to a single buffer, a whole Go package (or any directory-based module), or the entire workspace.

## Requirements

- Neovim >= 0.9
- [treeasy.nvim](https://github.com/you/treeasy.nvim)
- An LSP server attached to the buffer (e.g. `gopls`, `clangd`, `lua_ls`, …)
- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) *(optional — file icons in module/all scopes)*

## Installation

```lua
-- lazy.nvim
{
  "you/outlineasy.nvim",
  dependencies = {
    "you/treeasy.nvim",
    "nvim-tree/nvim-web-devicons",  -- optional
  },
  opts = {},
}
```

## Setup

```lua
require("outlineasy").setup({
  scope = "file",   -- default scope: "file" | "module" | "all"
  width = 40,       -- sidebar width in columns
  side  = "left",   -- "left" | "right"
  icons = true,     -- false = no nerd-font icons (symbol kinds + file types)
})
```

All fields are optional. Calling `setup()` is optional too.

Recommended keybinds:

```lua
vim.keymap.set("n", "<leader>o", "<cmd>Outlineasy<cr>")
vim.keymap.set("n", "<leader>O", "<cmd>Outlineasy module<cr>")
```

## Commands

| Command | Description |
|---|---|
| `:Outlineasy [scope]` | Toggle the outline. Optionally switch scope. |
| `:OutlineasyRefresh` | Force re-query LSP and redraw. |

## Scopes

### `file`
Uses `textDocument/documentSymbol`. Returns a hierarchical tree mirroring the document structure. With `gopls` this includes nested types, methods, fields, and constants.  
Auto-refreshes on buffer switch and save.

### `module`
Uses `workspace/symbol`, filtered to the **current file's directory**. In Go this is exactly one package. Results are grouped by file.  
Auto-refreshes when you switch to a buffer in a different directory.

### `all`
Uses `workspace/symbol` with no filtering, grouped by file.  
No automatic refresh — use `:OutlineasyRefresh` explicitly.

## Keymaps

Active in the outline buffer:

| Key | Action |
|---|---|
| `<CR>` / `<2-LeftMouse>` | Expand / collapse node |
| `o` / `<Space>` | Jump to symbol in source window |
| `r` | **Rename** symbol (LSP) |
| `<LeftRelease>` | Toggle (on `[-]`/`[+]`), rename (on `[r]`), or jump |
| `e` | Recursively expand |
| `c` | Recursively collapse |
| `[󰑐]` (header) | Refresh |

## Rename

Press `r` on any symbol node (or click its `[r]` button) to trigger an LSP rename.  
A `vim.ui.input` prompt appears pre-filled with the current name — confirm with `<CR>`, cancel with `<Esc>`.

The rename uses `textDocument/rename` directly so workspace edits are applied atomically across all files. The outline auto-refreshes 200 ms afterwards. Requires a client with `renameProvider` (gopls, clangd, lua_ls, …).

## Devicons

When [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) is installed, file nodes in `module` and `all` scopes show the file-type icon with its canonical color. Colors are registered lazily into treeasy as `devicon_<ext>` keys, so they can be overridden like any other color key. The plugin degrades gracefully without devicons.

## Customisation

Colors, keymaps, and tree symbols are managed by treeasy.nvim under the class
`"outlineasy"`. Set them **before** `setup()` and they won't be overwritten:

```lua
local treeasy = require("treeasy")

treeasy.set_colors("outlineasy", {
  fn_    = "#7aa2f7",
  meth   = "#7dcfff",
  type_  = "#9ece6a",
  enum_  = "#bb9af7",
  field  = "#e0af68",
  const  = "#ff9e64",
  var_   = "#c0caf5",
  file_  = "#737aa2",
  header = { fg = "#1a1b26", bg = "#7aa2f7", bold = true },
  btn    = { fg = "#565f89", bold = true },
  dim    = "#414868",
})

treeasy.set_keymap("outlineasy", {
  toggle_collapse = { "<CR>", "<2-LeftMouse>" },
  click           = { "<LeftRelease>" },
  open_rec        = { "e" },
  collapse_rec    = { "c" },
  jump            = { "o", "<Space>" },
})

require("outlineasy").setup({ scope = "module", width = 45 })
```

### Color keys

| Key | Applies to |
|---|---|
| `fn_` | functions |
| `meth` | methods |
| `type_` | types / interfaces / structs |
| `enum_` | enums and enum members |
| `field` | struct fields / object properties |
| `const` | constants |
| `var_` | variables and other symbols |
| `file_` | file nodes (`module` / `all` scopes) |
| `header` | header bar |
| `btn` | `[-]` `[+]` `[󰑐]` buttons |
| `dim` | "no symbols found" text |

## License

MIT
