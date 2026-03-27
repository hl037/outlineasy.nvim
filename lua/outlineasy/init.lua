local M = {}

local ok, treeasy = pcall(require, "treeasy")
if not ok then
  vim.notify("outlineasy: requires treeasy.nvim", vim.log.levels.ERROR)
  return M
end

local state_mod          = require("outlineasy.state")
local base_agents        = require("outlineasy.agents.base")
local DocumentBufferAgent = require("outlineasy.agents.document")
local ModuleBufferAgent   = require("outlineasy.agents.module")
local S                  = state_mod.S
local tree_m             = treeasy.tree
local node_m             = treeasy.node
local CLASS              = "outlineasy"

-- ── devicons ──────────────────────────────────────────────────────────────────

local devicons_ok, devicons = pcall(require, "nvim-web-devicons")
local _devicon_cache = {}

local function file_devicon(fname)
  if not S.icons or not devicons_ok then return "", "file_" end
  local icon, hex = devicons.get_icon_color(fname, nil, { default = true })
  if not icon then return "", "file_" end
  local ext = vim.fn.fnamemodify(fname, ":e")
  local key = "devicon_" .. ext
  if not _devicon_cache[key] then
    local colors = treeasy.get_colors(CLASS) or {}
    colors[key] = hex
    treeasy.set_colors(CLASS, colors)
    _devicon_cache[key] = true
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
      warn   = "#e0af68",
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
  [5]="type_",[6]="meth", [7]="field",[8]="field",
  [9]="fn_",  [10]="enum_",[11]="type_",[12]="fn_",
  [13]="var_",[14]="const",[22]="enum_",[23]="type_",
  [26]="type_",
}
local KIND_ICON = {
  [5]="󰠱 ",[6]=" ",[7]=" ",[8]=" ",
  [9]=" ",[10]=" ",[11]=" ",[12]="󰊕 ",
  [13]=" ",[14]=" ",[22]=" ",[23]="󰙅 ",
  [26]="󰊄 ",
}
local KIND_BADGE = {
  [1]="F",[2]="M",[3]="N",[4]="P",[5]="c",[6]="m",[7]="p",[8]="f",
  [9]="C",[10]="e",[11]="i",[12]="f",[13]="v",[14]="K",[15]="s",
  [16]="n",[17]="b",[18]="a",[19]="o",[20]="k",[21]="~",[22]="E",
  [23]="s",[24]="t",[25]="O",[26]="T",
}

local function sym_tag(kind, name)
  local c     = KIND_COLOR[kind] or "var_"
  local icon  = S.icons and (KIND_ICON[kind] or "  ") or ""
  local badge = KIND_BADGE[kind] or "?"
  return "<c:" .. c .. ">[" .. badge .. "] " .. icon .. name .. "</c>"
end

-- ── Global collapse/expand ────────────────────────────────────────────────────

local function walk_set_open(node, open)
  if not node.children then return end
  S.view:set_open(node, open)
  for _, child in ipairs(node.children) do walk_set_open(child, open) end
end

local function on_collapse_all() if S.ghost then for _, c in ipairs(S.ghost.children or {}) do walk_set_open(c, false) end end end
local function on_expand_all()   if S.ghost then for _, c in ipairs(S.ghost.children or {}) do walk_set_open(c, true)  end end end

-- ── Node text/handlers ────────────────────────────────────────────────────────

local SCOPE_CYCLE = { file = "module", module = "all", all = "file" }

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
      M.open(S.scope)
      return
    end
    if a == "refresh" then M.refresh(); return end
  end
end

-- Filter node (checkboxes) --

local FILTER_KINDS = {
  { kinds={12},    badge="f", label="function",    color="fn_"   },
  { kinds={6},     badge="m", label="method",      color="meth"  },
  { kinds={9},     badge="C", label="constructor", color="fn_"   },
  { kinds={5},     badge="c", label="class",       color="type_" },
  { kinds={23},    badge="s", label="struct",      color="type_" },
  { kinds={11},    badge="i", label="interface",   color="type_" },
  { kinds={26},    badge="T", label="type param",  color="type_" },
  { kinds={10},    badge="e", label="enum",        color="enum_" },
  { kinds={22},    badge="E", label="enum member", color="enum_" },
  { kinds={13},    badge="v", label="variable",    color="var_"  },
  { kinds={14},    badge="K", label="constant",    color="const" },
  { kinds={7,8},   badge="p", label="field/prop",  color="field" },
  { kinds={2,3,4}, badge="M", label="module/ns",   color="var_"  },
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
  tree_m.update_node(node)
  tree_m.update_node(S.filter_node)
  state_mod.save()
  M.refresh()
end

local function checkbox_click(node, view, ctx)
  if ctx.label_pos.col_index < 0 then return end
  checkbox_toggle(node, view, ctx)
end

-- Symbol nodes (created by agents via M.new_sym_node) --

local function goto_sym(node)
  if not (node.sym_uri and node.sym_range) then return end
  local path = vim.uri_to_fname(node.sym_uri)
  local line = node.sym_range.start.line
  local col  = node.sym_range.start.character
  local target
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if w ~= S.win and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == "" then
      target = w; break
    end
  end
  if not target then
    vim.cmd((S.side == "left") and "botright vsplit" or "topleft vsplit")
    target = vim.api.nvim_get_current_win()
  end
  local buf = vim.fn.bufadd(path)
  if not vim.api.nvim_buf_is_loaded(buf) then vim.fn.bufload(buf) end
  vim.api.nvim_win_set_buf(target, buf)
  vim.api.nvim_win_set_cursor(target, { line + 1, col })
  vim.api.nvim_set_current_win(target)
end

local function sym_rename(node, _v, _ctx)
  if not (node.sym_uri and node.sym_range) then return end
  vim.ui.input({ prompt = "Rename → ", default = node.sym_name }, function(new_name)
    if not new_name or new_name == "" or new_name == node.sym_name then return end
    local path   = vim.uri_to_fname(node.sym_uri)
    local bufnr  = vim.fn.bufadd(path)
    if not vim.api.nvim_buf_is_loaded(bufnr) then vim.fn.bufload(bufnr) end
    local client = base_agents.client_for(bufnr, "renameProvider")
    if not client then
      vim.notify("outlineasy: no renameProvider", vim.log.levels.WARN)
      return
    end
    client.request("textDocument/rename", {
      textDocument = { uri = node.sym_uri },
      position     = { line = node.sym_range.start.line, character = node.sym_range.start.character },
      newName      = new_name,
    }, function(err, result)
      vim.schedule(function()
        if err then vim.notify("outlineasy rename: " .. (err.message or tostring(err)), vim.log.levels.ERROR); return end
        if result then vim.lsp.util.apply_workspace_edit(result, client.offset_encoding) end
        node.sym_name = new_name
        tree_m.update_node(node)
        vim.defer_fn(M.refresh, 200)
      end)
    end, bufnr)
  end)
end

local function sym_open_text(node, _v)
  local t = sym_tag(node.sym_kind, node.sym_name)
  local sfx = "  <a:rename><c:btn>[r]</c></a>"
  if node._error then sfx = "  <c:warn>⚠</c>" .. sfx end
  if node.children and #node.children > 0 then
    return { t .. "  <a:toggle><c:btn>[-]</c></a>" .. sfx }
  end
  return { t .. sfx }
end

local function sym_collapsed_text(node, _v)
  local t = sym_tag(node.sym_kind, node.sym_name)
  local sfx = "  <a:rename><c:btn>[r]</c></a>"
  if node._error then sfx = "  <c:warn>⚠</c>" .. sfx end
  if node.children and #node.children > 0 then
    return { t .. "  <a:toggle><c:btn>[+]</c></a>" .. sfx }
  end
  return { t .. sfx }
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

-- File nodes (created by ModuleBufferAgent via M.setup_file_node) --

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

-- ── Public node factories (used by agents) ────────────────────────────────────

function M.new_sym_node(sym)
  local n = node_m.new()
  n.sym_kind  = sym.kind
  n.sym_name  = sym.name
  n.sym_uri   = sym.uri
  n.sym_range = sym.range
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
      local cn = M.new_sym_node(child)
      cn.parent = n; cn.index = i
      n.children[i] = cn
    end
  end
  return n
end

function M.setup_file_node(node)
  node.open_text           = file_open_text
  node.collapsed_text      = file_collapsed_text
  node.handler["click"]    = file_click
  node.handler["collapse_all"] = on_collapse_all
  node.handler["expand_all"]   = on_expand_all
end

-- ── Filter (applied on top of tree) ──────────────────────────────────────────

local function filter_node_tree(node)
  if node.sym_kind and S.hidden_kinds[node.sym_kind] then return nil end
  if not node.children then return node end
  local kept = {}
  for _, child in ipairs(node.children) do
    local fc = filter_node_tree(child)
    if fc then table.insert(kept, fc) end
  end
  if #kept == #node.children then return node end
  local copy = {}
  for k, v in pairs(node) do copy[k] = v end
  copy.children = kept
  return copy
end

-- ── Tree / window ─────────────────────────────────────────────────────────────

local function win_valid()
  return S.win and vim.api.nvim_win_is_valid(S.win)
end

local function make_tree()
  local ghost  = node_m.new(); ghost.ghost = true
  local header = node_m.new()
  header.scope             = S.scope
  header.open_text         = header_text
  header.collapsed_text    = header_text
  header.handler["click"]  = header_click
  header.handler["collapse_all"] = on_collapse_all
  header.handler["expand_all"]   = on_expand_all

  local fnode = node_m.new()
  fnode.open_text              = filter_open_text
  fnode.collapsed_text         = filter_collapsed_text
  fnode.handler["click"]       = filter_click
  fnode.handler["collapse_all"] = on_collapse_all
  fnode.handler["expand_all"]   = on_expand_all
  fnode.children = {}
  for i, group in ipairs(FILTER_KINDS) do
    local cb = node_m.new()
    cb.kind_group                  = group
    cb.open_text                   = checkbox_text
    cb.collapsed_text              = checkbox_text
    cb.handler["click"]            = checkbox_click
    cb.handler["toggle_collapse"]  = checkbox_toggle
    cb.handler["jump"]             = checkbox_toggle
    cb.handler["collapse_all"]     = on_collapse_all
    cb.handler["expand_all"]       = on_expand_all
    cb.parent = fnode; cb.index = i
    fnode.children[i] = cb
  end

  -- Content node: ghost, managed by the current agent
  local content = node_m.new(); content.ghost = true
  content.handler["collapse_all"] = on_collapse_all
  content.handler["expand_all"]   = on_expand_all

  ghost.children = { header, fnode, content }
  header.parent  = ghost; header.index  = 1
  fnode.parent   = ghost; fnode.index   = 2
  content.parent = ghost; content.index = 3

  S.ghost       = ghost
  S.header      = header
  S.filter_node = fnode
  S.content     = content
  S.tree        = tree_m.new({ class = CLASS, root = ghost })
end

local function open_win()
  local cmd = (S.side == "right") and "botright " or "topleft "
  vim.cmd(cmd .. S.width .. "vsplit")
  S.win  = vim.api.nvim_get_current_win()
  S.view = treeasy.attach_tree(S.win, S.tree)
end

-- ── Agent management ──────────────────────────────────────────────────────────

local function agent_opts()
  return {
    scope      = S.scope,
    outlineasy = M,
    set_open   = function(node, open) if S.view then S.view:set_open(node, open) end end,
    max_open   = S.max_open  or 20,
    max_files  = S.max_files or 64,
  }
end

local function resolve_agent_class()
  -- scope → default agent class
  if S.scope == "file" then
    return base_agents.get_class("*", "document") or DocumentBufferAgent
  else
    return base_agents.get_class("*", "module") or ModuleBufferAgent
  end
end

local function spawn_agent(bufnr)
  if S.agent then
    S.agent:kill()
    tree_m.replace_node(S.content, nil)
    S.agent = nil
  end
  -- Create a fresh ghost content node for the new agent
  local content = node_m.new(); content.ghost = true
  content.handler["collapse_all"] = on_collapse_all
  content.handler["expand_all"]   = on_expand_all
  local idx = #S.ghost.children + 1
  content.parent = S.ghost; content.index = idx
  S.ghost.children[idx] = content
  tree_m.update_node(S.ghost)
  S.content = content

  S.buf = bufnr
  local AgentClass = resolve_agent_class()
  S.agent = AgentClass.new(S.content)
  S.agent:start(bufnr, agent_opts())
end

local function try_switch_buf(bufnr)
  if not win_valid() then return end
  if vim.bo[bufnr].buftype ~= "" then return end
  local outline_buf = vim.api.nvim_win_get_buf(S.win)
  if bufnr == outline_buf then return end
  if not S.agent then spawn_agent(bufnr); return end
  local opts = agent_opts()
  if S.agent:change(bufnr, opts) then return end  -- agent handles it
  spawn_agent(bufnr)
end

-- ── Autocmds ──────────────────────────────────────────────────────────────────

local function is_normal_buf(bufnr)
  return vim.bo[bufnr].buftype == ""
     and vim.bo[bufnr].modifiable
     and vim.api.nvim_buf_get_name(bufnr) ~= ""
end

local autocmds_ready = false

local function ensure_autocmds()
  if autocmds_ready then return end
  autocmds_ready = true
  local aug = vim.api.nvim_create_augroup("outlineasy", { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = aug,
    callback = function()
      if not win_valid() then return end
      local bufnr = vim.api.nvim_get_current_buf()
      if not is_normal_buf(bufnr) then return end
      local outline_buf = vim.api.nvim_win_get_buf(S.win)
      if bufnr == outline_buf then return end
      try_switch_buf(bufnr)
    end,
  })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = aug,
    callback = function(ev)
      if not win_valid() then return end
      local focused = vim.api.nvim_get_current_buf()
      if ev.buf == focused and is_normal_buf(focused) then
        try_switch_buf(ev.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = aug,
    callback = function()
      if not win_valid() then return end
      if S.agent then S.agent:refresh() end
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = aug,
    callback = function(ev)
      if tonumber(ev.match) == S.win then
        if S.agent then S.agent:kill(); S.agent = nil end
        S.win = nil; S.view = nil; S.tree = nil
        S.ghost = nil; S.header = nil; S.filter_node = nil
        S.content = nil
      end
    end,
  })
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.refresh()
  if not win_valid() then return end
  S.header.scope = S.scope
  tree_m.update_node(S.header)
  if S.agent then S.agent:refresh() end
end

function M.open(scope)
  ensure_autocmds()
  if scope and scope ~= S.scope then S.scope = scope end
  setup_class()
  if win_valid() then
    S.header.scope = S.scope
    tree_m.update_node(S.header)
    state_mod.save()
    local bufnr = S.buf or vim.api.nvim_get_current_buf()
    try_switch_buf(bufnr)
    return
  end
  S.buf = vim.api.nvim_get_current_buf()
  make_tree()
  open_win()
  vim.cmd("wincmd p")
  spawn_agent(S.buf)
end

function M.close()
  if S.agent then S.agent:kill(); S.agent = nil end
  if win_valid() then vim.api.nvim_win_close(S.win, true) end
  S.win = nil; S.view = nil; S.tree = nil
  S.ghost = nil; S.header = nil; S.filter_node = nil; S.content = nil
end

function M.toggle(scope)
  if win_valid() and not scope then M.close()
  else M.open(scope) end
end

function M.setup(opts)
  opts = opts or {}
  state_mod.load()
  S.scope     = opts.scope     or S.scope
  S.width     = opts.width     or S.width
  S.side      = opts.side      or S.side
  S.max_open  = opts.max_open  or 20
  S.max_files = opts.max_files or 64
  if opts.icons ~= nil then S.icons = opts.icons end
  setup_class()
  ensure_autocmds()

  vim.api.nvim_create_user_command("Outlineasy", function(o)
    M.toggle(o.args ~= "" and o.args or nil)
  end, {
    nargs    = "?",
    complete = function() return { "file", "module", "all" } end,
    desc     = "Toggle/switch outlineasy scope",
  })
  vim.api.nvim_create_user_command("OutlineasyClose",   M.close,   { desc = "Close outlineasy" })
  vim.api.nvim_create_user_command("OutlineasyRefresh", M.refresh, { desc = "Refresh outlineasy" })
end

function M.set_provider(server_name, provider)
  -- Compatibility shim — map old provider API to agent registry
  vim.notify("outlineasy: set_provider() is deprecated, use set_agent() instead", vim.log.levels.WARN)
end

-- FT_EXTENSIONS controls which file extensions are globbed per filetype
-- in module scope when the directory has >= max_open files.
-- Patch it directly: require("outlineasy").FT_EXTENSIONS.zig = { "*.zig" }
M.FT_EXTENSIONS = require("outlineasy.agents.module").FT_EXTENSIONS

function M.set_agent(filetype, scope, AgentClass)
  base_agents.register(filetype, scope, AgentClass)
end

return M
