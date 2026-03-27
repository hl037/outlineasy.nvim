local M = {}

local ok, treeasy = pcall(require, "treeasy")
if not ok then
  vim.notify("outlineasy: requires treeasy.nvim", vim.log.levels.ERROR)
  return M
end

local providers = require("outlineasy.providers")
local state_mod = require("outlineasy.state")
local S         = state_mod.S
local tree_m    = treeasy.tree
local node_m    = treeasy.node
local CLASS     = "outlineasy"

-- ── devicons integration ──────────────────────────────────────────────────────

local devicons_ok, devicons = pcall(require, "nvim-web-devicons")

-- Cache of ext -> color key already registered into treeasy
local _devicon_color_cache = {}

-- Returns (icon_str, color_key) for a filename.
-- color_key is always a valid treeasy color key for CLASS.
local function file_devicon(fname)
  if not S.icons or not devicons_ok then return "", "file_" end
  local icon, hex = devicons.get_icon_color(fname, nil, { default = true })
  if not icon then return "󰈙 ", "file_" end
  local ext = vim.fn.fnamemodify(fname, ":e")
  local key = "devicon_" .. ext
  if not _devicon_color_cache[key] then
    -- Hot-patch the color into the live class
    local colors = treeasy.get_colors(CLASS) or {}
    colors[key] = hex
    treeasy.set_colors(CLASS, colors)
    _devicon_color_cache[key] = true
  end
  return icon .. " ", key
end

-- ── Class registration ────────────────────────────────────────────────────────

local function setup_class()
  if not treeasy.get_keymap(CLASS) then
    treeasy.set_keymap(CLASS, {
      toggle_collapse = { "<CR>", "<2-LeftMouse>" },
      click           = { "<LeftRelease>" },
      open_rec        = { "e" },
      collapse_rec    = { "c" },
      -- custom event: navigate to symbol without toggling
      jump            = { "o", "<Space>" },
      rename          = { "r" },
      collapse_all    = { "C" },
      expand_all      = { "E" },
    })
  end
  if not treeasy.get_colors(CLASS) then
    treeasy.set_colors(CLASS, {
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
  end
  if not treeasy.get_symbols(CLASS) then
    treeasy.set_symbols(CLASS, {
      mid = "├─ ", last = "└─ ", vert = "│  ", space = "   ",
    })
  end
end

-- ── Symbol kind maps ──────────────────────────────────────────────────────────

local KIND_COLOR = {
  [5]="type_", [6]="meth",  [7]="field", [8]="field",
  [9]="fn_",   [10]="enum_",[11]="type_",[12]="fn_",
  [13]="var_", [14]="const",[22]="enum_",[23]="type_",
  [26]="type_",
}
local KIND_ICON = {
  [5]="󰠱 ",[6]=" ",[7]=" ",[8]=" ",
  [9]=" ",[10]=" ",[11]=" ",[12]="󰊕 ",
  [13]=" ",[14]=" ",[22]=" ",[23]="󰙅 ",
  [26]="󰊄 ",
}
-- LSP SymbolKind → short badge
-- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#symbolKind
local KIND_BADGE = {
  [1]="F",  -- File
  [2]="M",  -- Module
  [3]="N",  -- Namespace
  [4]="P",  -- Package
  [5]="c",  -- Class
  [6]="m",  -- Method
  [7]="p",  -- Property
  [8]="f",  -- Field
  [9]="C",  -- Constructor
  [10]="e", -- Enum
  [11]="i", -- Interface
  [12]="f", -- Function
  [13]="v", -- Variable
  [14]="K", -- Constant
  [15]="s", -- String
  [16]="n", -- Number
  [17]="b", -- Boolean
  [18]="a", -- Array
  [19]="o", -- Object
  [20]="k", -- Key
  [21]="~", -- Null
  [22]="E", -- EnumMember
  [23]="s", -- Struct
  [24]="t", -- Event
  [25]="O", -- Operator
  [26]="T", -- TypeParameter
}

local function sym_tag(kind, name)
  local c     = KIND_COLOR[kind] or "var_"
  local icon  = S.icons and (KIND_ICON[kind] or "  ") or ""
  local badge = KIND_BADGE[kind] or "?"
  return "<c:" .. c .. ">[" .. badge .. "] " .. icon .. name .. "</c>"
end

-- ── Node text / handler functions (module-level, no closures) ─────────────────

local SCOPE_CYCLE = { file = "module", module = "all", all = "file" }

-- ── Global expand / collapse ──────────────────────────────────────────────────

local function walk_set_open(node, open)
  if not node.children then return end
  S.view:set_open(node, open)
  for _, child in ipairs(node.children) do
    walk_set_open(child, open)
  end
end

local function global_collapse()
  if not S.ghost then return end
  for _, child in ipairs(S.ghost.children or {}) do
    walk_set_open(child, false)
  end
end

local function global_expand()
  if not S.ghost then return end
  for _, child in ipairs(S.ghost.children or {}) do
    walk_set_open(child, true)
  end
end

-- Shared handlers dispatched to every node type
local function on_collapse_all(_n, _v, _ctx) global_collapse() end
local function on_expand_all(_n, _v, _ctx)   global_expand()   end

-- Header --

local function header_text(node, _v)
  return {
    "<c:header> 󱘎 Outline </c>"
    .. "  <a:scope><c:btn>[" .. (node.scope or "?") .. "]</c></a>"
    .. "  <a:refresh><c:btn>[󰑐]</c></a>",
  }
end

local function header_click(_n, _v, ctx)
  if ctx.label_pos.col_index < 0 then return end
  for _, a in ipairs(ctx.areas) do
    if a == "scope" then
      S.scope = SCOPE_CYCLE[S.scope] or "file"
      S.header.scope = S.scope
      tree_m.update_node(S.header)
      state_mod.save()
      M.refresh()
      return
    end
    if a == "refresh" then M.refresh(); return end
  end
end

-- Filter node (collapsible, with kind checkboxes as children) --

-- Ordered list of kind groups shown as checkboxes.
-- Each entry controls one or more LSP SymbolKind numbers.
local FILTER_KINDS = {
  { kinds = {12},    badge = "f", label = "function",    color = "fn_"   },
  { kinds = {6},     badge = "m", label = "method",      color = "meth"  },
  { kinds = {9},     badge = "C", label = "constructor", color = "fn_"   },
  { kinds = {5},     badge = "c", label = "class",       color = "type_" },
  { kinds = {23},    badge = "s", label = "struct",      color = "type_" },
  { kinds = {11},    badge = "i", label = "interface",   color = "type_" },
  { kinds = {26},    badge = "T", label = "type param",  color = "type_" },
  { kinds = {10},    badge = "e", label = "enum",        color = "enum_" },
  { kinds = {22},    badge = "E", label = "enum member", color = "enum_" },
  { kinds = {13},    badge = "v", label = "variable",    color = "var_"  },
  { kinds = {14},    badge = "K", label = "constant",    color = "const" },
  { kinds = {7, 8},  badge = "p", label = "field/prop",  color = "field" },
  { kinds = {2,3,4}, badge = "M", label = "module/ns",   color = "var_"  },
}

local function count_hidden()
  local n = 0
  for _, g in ipairs(FILTER_KINDS) do
    if S.hidden_kinds[g.kinds[1]] then n = n + 1 end
  end
  return n
end

local function filter_open_text(_n, _v)
  local h = count_hidden()
  local hint = h > 0 and ("<c:const> -" .. h .. "</c>") or ""
  return { "<c:dim>[/] filters</c>" .. hint .. "  <a:toggle><c:btn>[-]</c></a>" }
end

local function filter_collapsed_text(_n, _v)
  local h = count_hidden()
  local hint = h > 0 and ("<c:const> -" .. h .. "</c>") or ""
  return { "<c:dim>[/] filters</c>" .. hint .. "  <a:toggle><c:btn>[+]</c></a>" }
end

local function filter_click(_n, view, ctx)
  if ctx.label_pos.col_index < 0 then return end
  for _, a in ipairs(ctx.areas) do
    if a == "toggle" then view:_handle_event("toggle_collapse", _n, ctx); return end
  end
end

-- Checkbox child node --

local function checkbox_text(node, _v)
  local g = node.kind_group
  local hidden = S.hidden_kinds[g.kinds[1]]
  local box = hidden and "<c:dim>[ ]</c>" or "<c:type_>[✓]</c>"
  return { box .. " <c:" .. g.color .. ">[" .. g.badge .. "] " .. g.label .. "</c>" }
end

local function checkbox_toggle(node, _v, _ctx)
  local g = node.kind_group
  local hidden = S.hidden_kinds[g.kinds[1]]
  for _, k in ipairs(g.kinds) do
    if hidden then S.hidden_kinds[k] = nil else S.hidden_kinds[k] = true end
  end
  -- Redraw checkbox and filter header (hidden count may change)
  tree_m.update_node(node)
  tree_m.update_node(S.filter_node)
  state_mod.save()
  M.refresh()
end

local function checkbox_click(node, view, ctx)
  if ctx.label_pos.col_index < 0 then return end
  checkbox_toggle(node, view, ctx)
end

local function new_checkbox_node(group, parent, index)
  local n = node_m.new()
  n.kind_group              = group
  n.open_text               = checkbox_text
  n.collapsed_text          = checkbox_text
  n.handler["click"]        = checkbox_click
  n.handler["toggle_collapse"] = checkbox_toggle
  n.handler["jump"]         = checkbox_toggle
  n.parent = parent; n.index = index
  return n
end

-- File node (module / all scopes) --

local function file_open_text(node, _v)
  local fname = vim.fn.fnamemodify(vim.uri_to_fname(node.file_uri), ":t")
  local icon, color = file_devicon(fname)
  return { "<c:" .. color .. ">[F] " .. icon .. fname .. "</c>  <a:toggle><c:btn>[-]</c></a>" }
end

local function file_collapsed_text(node, _v)
  local fname = vim.fn.fnamemodify(vim.uri_to_fname(node.file_uri), ":t")
  local icon, color = file_devicon(fname)
  return { "<c:" .. color .. ">[F] " .. icon .. fname .. "</c>  <a:toggle><c:btn>[+]</c></a>" }
end

local function file_click(_n, view, ctx)
  if ctx.label_pos.col_index < 0 then return end
  for _, a in ipairs(ctx.areas) do
    if a == "toggle" then view:_handle_event("toggle_collapse", _n, ctx); return end
  end
end

-- Symbol node --

local function sym_open_text(node, _v)
  local t = sym_tag(node.sym_kind, node.sym_name)
  local suffix = "  <a:rename><c:btn>[r]</c></a>"
  if node.children and #node.children > 0 then
    return { t .. "  <a:toggle><c:btn>[-]</c></a>" .. suffix }
  end
  return { t .. suffix }
end

local function sym_collapsed_text(node, _v)
  local t = sym_tag(node.sym_kind, node.sym_name)
  local suffix = "  <a:rename><c:btn>[r]</c></a>"
  if node.children and #node.children > 0 then
    return { t .. "  <a:toggle><c:btn>[+]</c></a>" .. suffix }
  end
  return { t .. suffix }
end

local function find_source_win()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if w ~= S.win and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "" then
      return w
    end
  end
end

local function goto_sym(node)
  if not (node.sym_uri and node.sym_range) then return end
  local path = vim.uri_to_fname(node.sym_uri)
  local line  = node.sym_range.start.line
  local col   = node.sym_range.start.character
  local target = find_source_win()
  if not target then
    vim.cmd((S.side == "left") and "botright vsplit" or "topleft vsplit")
    target = vim.api.nvim_get_current_win()
  end
  local buf = vim.fn.bufadd(path)
  if not vim.api.nvim_buf_is_loaded(buf) then vim.fn.bufload(buf) end
  vim.api.nvim_win_set_buf(target, buf)
  vim.api.nvim_win_set_cursor(target, { line + 1, col })
  vim.api.nvim_set_current_win(target)
  return target, buf
end

local function sym_rename(node, _v, _ctx)
  if not (node.sym_uri and node.sym_range) then return end
  vim.ui.input({ prompt = "Rename → ", default = node.sym_name }, function(new_name)
    if not new_name or new_name == "" or new_name == node.sym_name then return end
    -- Load the symbol's buffer to have a valid bufnr for the LSP request
    local path = vim.uri_to_fname(node.sym_uri)
    local bufnr = vim.fn.bufadd(path)
    if not vim.api.nvim_buf_is_loaded(bufnr) then vim.fn.bufload(bufnr) end
    local pos = {
      line      = node.sym_range.start.line,
      character = node.sym_range.start.character,
    }
    providers.rename(bufnr, pos, new_name, function(err)
      if err then
        vim.notify("outlineasy rename: " .. err, vim.log.levels.ERROR)
        return
      end
      -- Update the node label optimistically before the LSP refresh
      node.sym_name = new_name
      tree_m.update_node(node)
      -- Full refresh after a short delay (workspace edits may touch many files)
      vim.defer_fn(M.refresh, 200)
    end)
  end)
end

local function sym_click(node, view, ctx)
  if ctx.label_pos.col_index < 0 then return end
  for _, a in ipairs(ctx.areas) do
    if a == "toggle" then view:_handle_event("toggle_collapse", node, ctx); return end
    if a == "rename" then sym_rename(node, view, ctx); return end
  end
  goto_sym(node)
end

local function sym_jump(node, _v, ctx)
  if ctx.label_pos.col_index < 0 then return end
  goto_sym(node)
end

-- Empty placeholder --

local function empty_text(_n, _v)
  return { "<c:dim>  no symbols found</c>" }
end

-- ── Node constructors ─────────────────────────────────────────────────────────

local function new_sym_node(sym)
  local n = node_m.new()
  n.sym_kind           = sym.kind
  n.sym_name           = sym.name
  n.sym_uri            = sym.uri
  n.sym_range          = sym.range
  n.open_text          = sym_open_text
  n.collapsed_text     = sym_collapsed_text
  n.handler["click"]        = sym_click
  n.handler["jump"]         = sym_jump
  n.handler["rename"]       = sym_rename
  n.handler["collapse_all"] = on_collapse_all
  n.handler["expand_all"]   = on_expand_all
  if sym.children and #sym.children > 0 then
    n.children = {}
    for i, child in ipairs(sym.children) do
      local cn = new_sym_node(child)
      cn.parent = n; cn.index = i
      n.children[i] = cn
    end
  end
  return n
end

-- ── Tree builders ─────────────────────────────────────────────────────────────

-- file scope: flat list of sym nodes (normalized symbols, may have children)
local function build_file_nodes(symbols)
  local nodes = {}
  for i, sym in ipairs(symbols) do
    nodes[i] = new_sym_node(sym)
  end
  return nodes
end

-- ── Filter ────────────────────────────────────────────────────────────────────

-- Recursively prune nodes whose kind is hidden.
-- Containers whose own kind is hidden are dropped entirely (with subtree).
-- Containers whose kind is visible keep their visible children (may be empty).
local function filter_node_tree(node)
  if node.sym_kind and S.hidden_kinds[node.sym_kind] then return nil end
  if not node.children then return node end
  local kept = {}
  for _, child in ipairs(node.children) do
    local fc = filter_node_tree(child)
    if fc then table.insert(kept, fc) end
  end
  if #kept == #node.children then return node end  -- nothing changed, no copy needed
  local copy = {}
  for k, v in pairs(node) do copy[k] = v end
  copy.children = kept
  return copy
end

local function apply_filter(nodes)
  if next(S.hidden_kinds) == nil then return nodes end
  local out = {}
  for _, n in ipairs(nodes) do
    local fn = filter_node_tree(n)
    if fn then table.insert(out, fn) end
  end
  return out
end

-- ── Ghost content replacement ─────────────────────────────────────────────────

-- ghost.children = { header, filter_node, ...content_nodes }
local function set_content(nodes)
  local g, h, fn = S.ghost, S.header, S.filter_node
  h.parent  = g; h.index  = 1
  fn.parent = g; fn.index = 2
  g.children = { h, fn }
  local filtered = apply_filter(nodes)
  for i, n in ipairs(filtered) do
    n.parent = g; n.index = i + 2
    g.children[i + 2] = n
  end
  tree_m.update_node(g)
end

local function set_empty()
  local n = node_m.new()
  n.open_text = empty_text; n.collapsed_text = empty_text
  set_content({ n })
end

-- ── Refresh logic ─────────────────────────────────────────────────────────────

local function win_valid()
  return S.win and vim.api.nvim_win_is_valid(S.win)
end

local function update_header()
  if not S.header then return end
  S.header.scope = S.scope
  tree_m.update_node(S.header)
end

local function refresh_file(bufnr)
  S.buf = bufnr
  providers.file_symbols(bufnr, function(syms)
    if not win_valid() then return end
    if not syms or #syms == 0 then set_empty(); return end
    local nodes = build_file_nodes(syms)
    set_content(nodes)
    for _, n in ipairs(nodes) do
      if n.children then S.view:set_open(n, true) end
    end
  end)
end

local function refresh_ws(bufnr, dir)
  S.buf = bufnr
  S.dir = dir

  -- Accumulate file nodes by URI, update tree incrementally as each file arrives
  local file_nodes = {}   -- uri → fnode
  local initialized = false

  local function get_or_create_fnode(uri)
    if file_nodes[uri] then return file_nodes[uri] end
    local fnode = node_m.new()
    fnode.file_uri             = uri
    fnode.open_text            = file_open_text
    fnode.collapsed_text       = file_collapsed_text
    fnode.handler["click"]     = file_click
    fnode.handler["collapse_all"] = on_collapse_all
    fnode.handler["expand_all"]   = on_expand_all
    fnode.children = {}
    file_nodes[uri] = fnode
    return fnode
  end

  local function notify(uri, syms)
    if not win_valid() then return end
    local fnode = get_or_create_fnode(uri)
    -- Build sym children from normalized symbols
    local sorted = {}
    for _, s in ipairs(syms) do table.insert(sorted, s) end
    table.sort(sorted, function(a, b)
      return (a.range and a.range.start.line or 0)
           < (b.range and b.range.start.line or 0)
    end)
    fnode.children = {}
    for i, sym in ipairs(sorted) do
      local sn = new_sym_node(sym)
      sn.parent = fnode; sn.index = i
      fnode.children[i] = sn
    end

    if not initialized then
      -- First file: set_content with what we have so far
      initialized = true
      local nodes = {}
      for _, fn in pairs(file_nodes) do table.insert(nodes, fn) end
      set_content(nodes)
    else
      -- Subsequent files: append fnode to ghost if new, then update
      local already = false
      for _, child in ipairs(S.ghost.children) do
        if child == fnode then already = true; break end
      end
      if not already then
        local idx = #S.ghost.children + 1
        fnode.parent = S.ghost; fnode.index = idx
        S.ghost.children[idx] = fnode
        tree_m.update_node(S.ghost)
      else
        tree_m.update_node(fnode)
      end
    end
    S.view:set_open(fnode, true)
  end

  local function done()
    if not win_valid() then return end
    if not initialized then set_empty() end
  end

  if dir then
    providers.module_symbols(bufnr, dir, notify, done)
  else
    providers.all_symbols(bufnr, notify, done)
  end
end

function M.refresh()
  if not win_valid() then return end
  update_header()
  -- Resolve tracked buffer: don't query the outline buffer itself
  local bufnr = S.buf
  local outline_buf = vim.api.nvim_win_get_buf(S.win)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) or bufnr == outline_buf then
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if b ~= outline_buf and vim.api.nvim_buf_is_loaded(b)
        and vim.bo[b].buftype == "" then
        bufnr = b; break
      end
    end
  end
  if not bufnr then set_empty(); return end
  if S.scope == "file" then
    refresh_file(bufnr)
  elseif S.scope == "module" then
    local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":h")
    refresh_ws(bufnr, dir)
  else  -- "all"
    refresh_ws(bufnr, nil)
  end
end

-- ── Window / tree lifecycle ───────────────────────────────────────────────────

local function make_tree()
  local ghost  = node_m.new(); ghost.ghost = true
  local header = node_m.new()
  header.scope                  = S.scope
  header.open_text              = header_text
  header.collapsed_text         = header_text
  header.handler["click"]       = header_click
  header.handler["collapse_all"] = on_collapse_all
  header.handler["expand_all"]   = on_expand_all

  local fnode = node_m.new()
  fnode.open_text               = filter_open_text
  fnode.collapsed_text          = filter_collapsed_text
  fnode.handler["click"]        = filter_click
  fnode.handler["collapse_all"] = on_collapse_all
  fnode.handler["expand_all"]   = on_expand_all
  fnode.children = {}
  for i, group in ipairs(FILTER_KINDS) do
    local cb = new_checkbox_node(group, fnode, i)
    cb.handler["collapse_all"] = on_collapse_all
    cb.handler["expand_all"]   = on_expand_all
    fnode.children[i] = cb
  end

  ghost.children = { header, fnode }
  header.parent = ghost; header.index = 1
  fnode.parent  = ghost; fnode.index  = 2

  S.ghost       = ghost
  S.header      = header
  S.filter_node = fnode
  S.tree        = tree_m.new({ class = CLASS, root = ghost })
end

local function open_win()
  local cmd = (S.side == "right") and "botright " or "topleft "
  vim.cmd(cmd .. S.width .. "vsplit")
  S.win  = vim.api.nvim_get_current_win()
  S.view = treeasy.attach_tree(S.win, S.tree)
end

function M.open(scope)
  ensure_autocmds()
  if scope then S.scope = scope end
  setup_class()
  if win_valid() then
    -- Already open: just switch scope and refresh
    S.header.scope = S.scope
    tree_m.update_node(S.header)
    state_mod.save()
    M.refresh()
    return
  end
  local src_buf = vim.api.nvim_get_current_buf()
  make_tree()
  open_win()
  vim.cmd("wincmd p")
  S.buf = src_buf
  M.refresh()
end

function M.close()
  if win_valid() then vim.api.nvim_win_close(S.win, true) end
  S.win = nil; S.view = nil; S.tree = nil
  S.ghost = nil; S.header = nil; S.filter_node = nil
end

-- Idempotent toggle: open if closed, close if open with no scope arg.
-- If a scope arg is given and the panel is already open, just switch scope.
function M.toggle(scope)
  if win_valid() and not scope then
    M.close()
  else
    M.open(scope)
  end
end

-- ── Autocmds ──────────────────────────────────────────────────────────────────

local autocmds_ready = false

-- Forward declaration used in M.open above
ensure_autocmds = function()
  if autocmds_ready then return end
  autocmds_ready = true
  local aug = vim.api.nvim_create_augroup("outlineasy", { clear = true })

  local function is_outline_buf(bufnr)
    return win_valid() and bufnr == vim.api.nvim_win_get_buf(S.win)
  end

  local function try_refresh_buf(bufnr)
    if not win_valid() then return end
    if vim.bo[bufnr].buftype ~= "" then return end
    if is_outline_buf(bufnr) then return end
    if S.scope == "file" then
      refresh_file(bufnr)
    elseif S.scope == "module" then
      local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":h")
      if dir ~= S.dir then S.buf = bufnr; refresh_ws(bufnr, dir) end
    end
  end

  vim.api.nvim_create_autocmd("BufEnter", {
    group = aug,
    callback = function()
      if not win_valid() then return end
      local bufnr = vim.api.nvim_get_current_buf()
      if is_outline_buf(bufnr) or vim.bo[bufnr].buftype ~= "" then return end
      -- Always refresh on buffer switch — LSP may or may not be ready yet.
      -- LspAttach will re-trigger if it wasn't ready.
      if S.scope == "file" then
        if bufnr ~= S.buf then try_refresh_buf(bufnr) end
      elseif S.scope == "module" then
        local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":h")
        if dir ~= S.dir then try_refresh_buf(bufnr) end
      end
    end,
  })

  -- Fires when an LSP client attaches to a buffer (may be after BufEnter).
  -- Re-refresh if it's the buffer we're currently tracking or displaying.
  vim.api.nvim_create_autocmd("LspAttach", {
    group = aug,
    callback = function(ev)
      if not win_valid() then return end
      local bufnr = ev.buf
      if is_outline_buf(bufnr) then return end
      -- Refresh if this is the currently tracked source buffer,
      -- or if it's the buffer currently focused in a source window.
      local focused = vim.api.nvim_get_current_buf()
      if bufnr == S.buf or bufnr == focused then
        try_refresh_buf(bufnr)
      end
    end,
  })

  -- Re-query on save (picks up new/removed symbols)
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = aug,
    callback = function()
      if not win_valid() then return end
      local bufnr = vim.api.nvim_get_current_buf()
      if is_outline_buf(bufnr) then return end
      if S.scope == "file" and bufnr == S.buf then
        refresh_file(bufnr)
      elseif S.scope == "module" then
        local dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":h")
        if dir == S.dir then refresh_ws(bufnr, dir) end
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = aug,
    callback = function(ev)
      if tonumber(ev.match) == S.win then
        S.win = nil; S.view = nil; S.tree = nil
        S.ghost = nil; S.header = nil
      end
    end,
  })
end

-- ── Setup ─────────────────────────────────────────────────────────────────────

function M.setup(opts)
  opts    = opts or {}
  state_mod.load()
  S.scope = opts.scope or S.scope
  S.width = opts.width or S.width
  S.side  = opts.side  or S.side
  if opts.icons ~= nil then S.icons = opts.icons end
  setup_class()
  ensure_autocmds()

  vim.api.nvim_create_user_command("Outlineasy", function(o)
    M.toggle(o.args ~= "" and o.args or nil)
  end, {
    nargs    = "?",
    complete = function() return { "file", "module", "all" } end,
    desc     = "Toggle/switch outlineasy scope (file | module | all)",
  })

  vim.api.nvim_create_user_command("OutlineasyClose", function()
    M.close()
  end, { desc = "Close the outlineasy panel" })

  vim.api.nvim_create_user_command("OutlineasyRefresh", function()
    M.refresh()
  end, { desc = "Force-refresh the outlineasy panel" })
end

-- Register a custom symbol provider for a specific LSP server.
-- provider = { file(bufnr,cb), module(bufnr,dir,cb), all(bufnr,cb) }
-- Each cb receives Symbol[]|nil  where Symbol = { name, kind, uri, range, children? }
function M.set_provider(server_name, provider)
  providers.set_provider(server_name, provider)
end

return M
