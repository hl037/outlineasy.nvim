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
| `:OutlineasyRefresh` | Force re-query and redraw. |

## Scopes

### `file`
Uses `textDocument/documentSymbol`. Returns a hierarchical tree mirroring the document structure — with gopls this includes nested types, methods, fields, and constants.
Auto-refreshes on buffer switch and on save.

### `module`
Uses `textDocument/documentSymbol` on every file in the current buffer's directory. In Go this covers exactly one package. Results appear incrementally as each file is processed, grouped by file.
Auto-refreshes when you switch to a buffer in a different directory.

### `all`
Same as `module` but operates on all currently loaded buffers with a matching filetype. No automatic refresh — use `:OutlineasyRefresh` explicitly.

> **gopls note** — `workspace/symbol` with an empty query returns nothing in gopls regardless of the `symbolMatcher` setting. outlineasy works around this by using `textDocument/documentSymbol` per file for both `module` and `all` scopes. Files not yet loaded are opened silently (`bufload` + `filetype detect`) and closed after the request completes.

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

The rename uses `textDocument/rename` directly so workspace edits are applied atomically across all files. The outline auto-refreshes 200 ms afterwards. Requires a client with `renameProvider` (gopls, clangd, lua_ls, …).

## Devicons

When [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) is installed, file nodes in `module` and `all` scopes show the file-type icon with its canonical color. Colors are registered lazily into treeasy as `devicon_<ext>` keys and can be overridden like any other color key. The plugin degrades gracefully without devicons.

## Custom providers

outlineasy uses a provider system to decouple LSP interaction from the tree. A provider is a Lua table with three functions:

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
`lua/outlineasy/overrides/<server_name>.lua` if the file exists.
You can also register one explicitly:

```lua
require("outlineasy").set_provider("my_lsp", {
  file   = function(bufnr, cb) ... end,
  module = function(bufnr, dir, notify, done) ... end,
  all    = function(bufnr, notify, done) ... end,
})
```

The built-in gopls override lives at `lua/outlineasy/overrides/gopls.lua` and
can be replaced the same way.

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
| `file_` | file nodes (`module` / `all` scopes), fallback when devicons absent |
| `header` | header bar |
| `btn` | `[-]` `[+]` `[󰑐]` `[r]` buttons |
| `dim` | "no symbols found" text, filter hint |
| `devicon_<ext>` | auto-registered per extension when devicons is active |

## License

MIT
