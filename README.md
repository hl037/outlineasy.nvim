# outlineasy.nvim

LSP symbol outline sidebar for Neovim, rendered by [treeasy.nvim](https://github.com/you/treeasy.nvim).

Three scopes — **file**, **module**, **all** — let you navigate symbols scoped to a single buffer, a whole Go package (or any directory-based module), or the entire workspace.

## Requirements

- Neovim >= 0.9
- [treeasy.nvim](https://github.com/you/treeasy.nvim)
- An LSP server attached to the buffer (e.g. `gopls`, `clangd`, `lua_ls`, …)
- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) *(optional — file icons in module/all scopes)*

## Installation

### lazy.nvim

```lua
{
  "you/outlineasy.nvim",
  dependencies = {
    "you/treeasy.nvim",
    "nvim-tree/nvim-web-devicons",  -- optional
  },
  opts = {},
}
```

`opts = {}` calls `setup()` automatically via lazy.nvim. Passing options directly:

```lua
{
  "you/outlineasy.nvim",
  dependencies = { "you/treeasy.nvim" },
  config = function()
    require("outlineasy").setup({
      scope = "module",
      width = 45,
    })
  end,
}
```

### vim-plug

```vim
Plug 'you/treeasy.nvim'
Plug 'nvim-tree/nvim-web-devicons'   " optional
Plug 'you/outlineasy.nvim'
```

Then in your `init.lua` (or a `lua << EOF` block in `init.vim`):

```lua
require("outlineasy").setup({})
```

**Note:** `setup()` must be called explicitly — unlike lazy.nvim, vim-plug does not call it automatically.

## Setup

```lua
require("outlineasy").setup({
  scope = "file",   -- default scope: "file" | "module" | "all"
  width = 40,       -- sidebar width in columns
  side  = "left",   -- "left" | "right"
  icons = true,     -- false = no nerd-font icons (symbol kinds + file types)
})
```

`setup()` registers the user commands and loads persisted state (scope, filters). It must be called before using the plugin.

Recommended keybinds:

```lua
vim.keymap.set("n", "<leader>o", "<cmd>Outlineasy<cr>")
vim.keymap.set("n", "<leader>O", "<cmd>Outlineasy module<cr>")
vim.keymap.set("n", "<leader>xo", "<cmd>OutlineasyClose<cr>")
```

## Commands

| Command | Description |
|---|---|
| `:Outlineasy [scope]` | Open the panel (or switch scope if already open). No arg = toggle. |
| `:OutlineasyClose` | Close the panel. |
| `:OutlineasyRefresh` | Force re-query and redraw. |

`:Outlineasy` is idempotent: if the panel is already open and you call `:Outlineasy module`, it switches to module scope and refreshes without closing and reopening.

## Scopes

### `file`
Uses `textDocument/documentSymbol` on the current buffer. Returns a hierarchical tree mirroring the document structure. With gopls this includes nested types, methods, fields, and constants.
Auto-refreshes on buffer switch and on save.

### `module`
Fans out `textDocument/documentSymbol` to every file in the current buffer's directory. In Go this covers exactly one package. Results appear incrementally as each file is processed, grouped by file.
Auto-refreshes when you switch to a buffer in a different directory.

### `all`
Same as `module` but operates on all currently loaded buffers with a matching filetype. No automatic refresh — use `:OutlineasyRefresh` explicitly.

> **gopls note** — `workspace/symbol` with an empty query returns nothing in gopls. outlineasy works around this by querying each file individually via `textDocument/documentSymbol`. Files not yet loaded are opened silently. The built-in gopls override handles this automatically.

## Keymaps

Active in the outline buffer:

| Key | Action |
|---|---|
| `<CR>` / `<2-LeftMouse>` | Expand / collapse node |
| `o` / `<Space>` | Jump to symbol in source window |
| `r` | **Rename** symbol (LSP) |
| `C` | Collapse all nodes |
| `E` | Expand all nodes |
| `<LeftRelease>` | Toggle (on `[-]`/`[+]`), rename (on `[r]`), or jump |
| `e` | Recursively expand subtree |
| `c` | Recursively collapse subtree |
| `[󰑐]` (header) | Refresh |

## Filter

The `[/] filters` node below the header is a collapsible list of symbol-kind checkboxes. Toggle any kind with `<CR>` or click. Hidden kinds are excluded from the tree and the count is shown in the header (`-2` = two kinds hidden). Filter state is persisted across sessions.

## Rename

Press `r` on any symbol node (or click its `[r]` button) to trigger an LSP rename. A `vim.ui.input` prompt appears pre-filled with the current name — confirm with `<CR>`, cancel with `<Esc>`.

Requires a client with `renameProvider` (gopls, clangd, lua_ls, …).

## Devicons

When [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) is installed, file nodes in `module` and `all` scopes show the file-type icon with its canonical color. The plugin degrades gracefully without devicons.

## Custom providers

A provider is a Lua table with three functions:

```lua
{
  -- cb(Symbol[] | nil) — called once
  file = function(bufnr, cb) end,

  -- notify(uri, Symbol[]) called per file as results arrive
  -- done() called when no more results are coming
  module = function(bufnr, dir, notify, done) end,
  all    = function(bufnr, notify, done) end,
}
-- Symbol = { name, kind, uri, range, children? }
```

Providers are matched by LSP server name and **auto-loaded** from
`lua/outlineasy/overrides/<server_name>.lua`. You can also register one explicitly:

```lua
require("outlineasy").set_provider("my_lsp", { ... })
```

## Customisation

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
  rename          = { "r" },
  collapse_all    = { "C" },
  expand_all      = { "E" },
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
| `file_` | file nodes, devicons fallback |
| `header` | header bar |
| `btn` | `[-]` `[+]` `[󰑐]` `[r]` buttons |
| `dim` | "no symbols found", filter hint |
| `devicon_<ext>` | auto-registered per extension |

## License

MIT
