# outlineasy.nvim

LSP symbol outline sidebar for Neovim, rendered by [treeasy.nvim](https://github.com/hl037/treeasy.nvim).

Three scopes — **file**, **module**, **all** — let you navigate symbols scoped to a single buffer, a whole package (Go, etc.), or all loaded buffers.

## Requirements

- Neovim >= 0.9
- [treeasy.nvim](https://github.com/hl037/treeasy.nvim)
- An LSP server with `documentSymbolProvider`
- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) *(optional)*

## Installation

### lazy.nvim

```lua
{
  hl037/outlineasy.nvim",
  dependencies = {
    "hl037/treeasy.nvim",
    "nvim-tree/nvim-web-devicons",  -- optional
  },
  opts = {},
}
```

### vim-plug

```vim
Plug 'hl037/treeasy.nvim'
Plug 'nvim-tree/nvim-web-devicons'   " optional
Plug 'hl037/outlineasy.nvim'
```

```lua
-- in init.lua — must be called explicitly with vim-plug
require("outlineasy").setup({})
```

## Setup

```lua
require("outlineasy").setup({
  scope     = "file",  -- default scope: "file" | "module" | "all"
  width     = 40,      -- sidebar width in columns
  side      = "left",  -- "left" | "right"
  icons     = true,    -- false = no nerd-font icons
  max_open  = 20,      -- module: max files to open-and-detect before using ext map
  max_files = 64,      -- module: max files before showing "too many files"
})
```

`setup()` registers user commands and loads persisted state (scope, filters).

Recommended keybinds:

```lua
vim.keymap.set("n", "<leader>o",  "<cmd>Outlineasy<cr>")
vim.keymap.set("n", "<leader>O",  "<cmd>Outlineasy module<cr>")
vim.keymap.set("n", "<leader>xo", "<cmd>OutlineasyClose<cr>")
```

## Commands

| Command | Description |
|---|---|
| `:Outlineasy [scope]` | Toggle panel, or switch scope if already open. |
| `:OutlineasyClose` | Close the panel. |
| `:OutlineasyRefresh` | Force re-query and redraw. |

## Scopes

### `file`
`textDocument/documentSymbol` on the current buffer. Hierarchical tree with nested types, methods, fields. Auto-refreshes on buffer switch and save.

### `module`
`textDocument/documentSymbol` fanned out to every file in the current buffer's directory matching the same filetype. In Go this is exactly one package. Results are grouped by file, sorted alphabetically. Auto-refreshes when you switch to a buffer in a different directory.

**File count tiers:**
- `< max_open` (20): opens all files, detects filetype, closes non-matching ones
- `< max_files` (64): globs only extensions from the `FT_EXTENSIONS` map
- `>= max_files`: displays "too many files" placeholder

### `all`
Same as `module` but across all currently loaded buffers with a matching filetype. No automatic refresh.

## Keymaps

Active in the outline buffer:

| Key | Action |
|---|---|
| `<CR>` / `<2-LeftMouse>` | Expand / collapse |
| `o` / `<Space>` | Jump to symbol |
| `r` | Rename symbol (LSP) |
| `C` | Collapse all |
| `E` | Expand all |
| `e` | Recursively expand subtree |
| `c` | Recursively collapse subtree |
| `[󰑐]` (header) | Refresh |
| `[scope]` (header) | Cycle scope (file → module → all) |

## Filter

The `[/] filters` node exposes symbol-kind checkboxes. Toggle with `<CR>` or click. Hidden kinds are excluded from all scopes. The header shows the count of hidden kinds (`-2`). State persisted across sessions.

## Rename

Press `r` on any symbol (or click `[r]`) to rename via `textDocument/rename`. Uses `vim.ui.input` pre-filled with the current name. Requires `renameProvider`.

## Architecture

outlineasy uses an **agent** system. Each agent manages the content of a node in the treeasy tree. The spawner owns the node itself (creation and `replace_node` on cleanup).

```
ghost
  header
  filter_node (checkboxes)
  content (ghost)              ← owned by current BufferAgent
    [module] file_node         ← owned by ModuleBufferAgent, one per file
      symbols                  ← owned by LspDocumentAgent (ghost)
    [file] symbols             ← owned by LspDocumentAgent (ghost)
```

**Built-in agents:**

`DocumentBufferAgent` — file scope. Watches `LspAttach`/`LspDetach`, spawns one `LspDocumentAgent` per client.

`LspDocumentAgent` — handles one LSP client. Sends `textDocument/documentSymbol`, populates its node.

`ModuleBufferAgent` — module/all scope. Lists files, creates file nodes (non-ghost, sorted alpha), spawns a `DocumentBufferAgent` per file.

## Extension points

### Custom filetype extension map

```lua
local oa = require("outlineasy")
oa.FT_EXTENSIONS.nix     = { "*.nix" }
oa.FT_EXTENSIONS.cpp     = { "*.cpp", "*.cc", "*.hpp", "*.h" }
oa.setup({})
```

### Custom agents

```lua
require("outlineasy").set_agent(filetype, scope, MyAgentClass)
-- filetype: e.g. "go", "lua", or "*" for default
-- scope:    "document", "lsp_document", "module"
```

Agent interface:

```lua
MyAgent.new(node)              -- node: treeasy node to manage
agent:start(bufnr, opts)       -- opts: { scope, outlineasy, set_open, max_open, max_files }
agent:change(bufnr, opts) → bool  -- true = adapt in place, false = kill+respawn
agent:kill()                   -- cleanup resources only (no tree changes)
agent:refresh()                -- re-query
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
  warn   = "#e0af68",
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

## License

MIT
