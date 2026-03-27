-- ModuleBufferAgent
--
-- Manages a directory (scope=module) or all loaded buffers (scope=all).
-- Filetype-aware: only processes files matching the source buffer's filetype.
--
-- Three tiers based on file count in the directory:
--   < opts.max_open  (default 20): glob all, open unknown files, close those
--                                  with wrong ft after detection
--   < opts.max_files (default 64): use FT_EXTENSIONS map to glob only
--                                  relevant extensions
--   >= max_files: show a "too many files" placeholder node

local base                = require("outlineasy.agents.base")
local DocumentBufferAgent = require("outlineasy.agents.document")

-- ft → list of glob extensions
local FT_EXTENSIONS = {
  go         = { "*.go" },
  lua        = { "*.lua" },
  python     = { "*.py" },
  javascript = { "*.js", "*.mjs", "*.cjs" },
  typescript = { "*.ts", "*.mts" },
  rust       = { "*.rs" },
  c          = { "*.c", "*.h" },
  cpp        = { "*.cpp", "*.cc", "*.cxx", "*.hpp", "*.hxx" },
  java       = { "*.java" },
  ruby       = { "*.rb" },
  php        = { "*.php" },
  cs         = { "*.cs" },
  swift      = { "*.swift" },
  kotlin     = { "*.kt" },
  zig        = { "*.zig" },
  ocaml      = { "*.ml", "*.mli" },
  haskell    = { "*.hs" },
  elixir     = { "*.ex", "*.exs" },
}

local ModuleBufferAgent = {}
ModuleBufferAgent.__index = ModuleBufferAgent
ModuleBufferAgent.FT_EXTENSIONS = FT_EXTENSIONS

function ModuleBufferAgent.new(node)
  return setmetatable({
    node          = node,
    _alive        = false,
    _bufnr        = nil,
    _dir          = nil,
    _ft           = nil,
    _opts         = nil,
    _file_agents  = {},   -- path → { agent, file_node }
    _opened_bufs  = {},   -- bufnr → true, bufs we loaded (to close wrong-ft ones)
    _aug          = nil,
  }, ModuleBufferAgent)
end

function ModuleBufferAgent:start(bufnr, opts)
  self._alive = true
  self._bufnr = bufnr
  self._opts  = opts
  self._dir   = opts.scope == "module"
    and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":h")
    or nil

  local ft = vim.bo[bufnr].filetype
  self._ft = ft ~= "" and ft or nil

  if not self._ft then
    -- No filetype yet: wait for FileType on this buffer
    self._aug = "outlineasy_module_ftwait_" .. bufnr
    vim.api.nvim_create_augroup(self._aug, { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
      group  = self._aug,
      buffer = bufnr,
      once   = true,
      callback = function()
        if not self._alive then return end
        pcall(vim.api.nvim_del_augroup_by_name, self._aug)
        self._ft = vim.bo[bufnr].filetype
        if self._ft ~= "" then self:_rebuild() end
      end,
    })
    self:_show_empty()
    return
  end

  self:_rebuild()
end

function ModuleBufferAgent:change(bufnr, opts)
  if opts.scope ~= (self._opts and self._opts.scope) then return false end
  if opts.scope == "module" then
    local new_dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":h")
    if new_dir ~= self._dir then return false end
    -- Same dir: nop (also handles same bufnr case)
    return true
  end
  return bufnr == self._bufnr
end

function ModuleBufferAgent:kill()
  self._alive = false
  local tree_m = require("treeasy").tree
  for _, entry in pairs(self._file_agents) do
    entry.agent:kill()
    tree_m.replace_node(entry.file_node, nil)
  end
  self._file_agents = {}
  if self._aug then
    pcall(vim.api.nvim_del_augroup_by_name, self._aug)
    self._aug = nil
  end
  for bnr in pairs(self._opened_bufs) do
    if vim.api.nvim_buf_is_valid(bnr) then
      pcall(vim.api.nvim_buf_delete, bnr, { force = false, unload = true })
    end
  end
  self._opened_bufs = {}
end

function ModuleBufferAgent:refresh()
  for _, entry in pairs(self._file_agents) do entry.agent:kill() end
  self._file_agents = {}
  self:_rebuild()
end

function ModuleBufferAgent:_show_empty()
  if not self._alive then return end
  local node_m = require("treeasy").node
  local tree_m = require("treeasy").tree
  local n = node_m.new()
  n.open_text      = function() return { "<c:dim>  no filetype detected</c>" } end
  n.collapsed_text = n.open_text
  n.parent = self.node; n.index = 1
  self.node.children = { n }
  tree_m.update_node(self.node)
end

function ModuleBufferAgent:_show_too_many()
  if not self._alive then return end
  local node_m = require("treeasy").node
  local tree_m = require("treeasy").tree
  local n = node_m.new()
  n.open_text      = function() return { "<c:dim>  too many files in directory</c>" } end
  n.collapsed_text = n.open_text
  n.parent = self.node; n.index = 1
  self.node.children = { n }
  tree_m.update_node(self.node)
end

function ModuleBufferAgent:_rebuild()
  if not self._alive then return end

  local ft        = self._ft
  local dir       = self._dir
  local max_open  = (self._opts and self._opts.max_open)  or 20
  local max_files = (self._opts and self._opts.max_files) or 64

  local paths
  if dir then
    local all = vim.fn.glob(dir .. "/*", false, true)
    local count = #all

    if count >= max_files then
      self:_show_too_many(); return
    end

    if count < max_open then
      -- Open all, detect ft, discard wrong ones
      paths = self:_open_and_filter(all, ft)
    else
      -- Use extension map to glob only relevant files
      local exts = ft and FT_EXTENSIONS[ft]
      if exts then
        paths = {}
        for _, ext in ipairs(exts) do
          for _, p in ipairs(vim.fn.glob(dir .. "/" .. ext, false, true)) do
            table.insert(paths, p)
          end
        end
      else
        -- Unknown ft: fall back to opening all
        paths = self:_open_and_filter(all, ft)
      end
    end
  else
    -- scope=all: use loaded buffers with matching ft
    paths = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" then
        if not ft or vim.bo[b].filetype == ft then
          local name = vim.api.nvim_buf_get_name(b)
          if name ~= "" then table.insert(paths, name) end
        end
      end
    end
  end

  if not paths or #paths == 0 then
    self:_show_empty(); return
  end

  -- Sort alphabetically by basename
  table.sort(paths, function(a, b)
    return vim.fn.fnamemodify(a, ":t") < vim.fn.fnamemodify(b, ":t")
  end)

  local tree_m = require("treeasy").tree
  local node_m = require("treeasy").node
  local oa     = self._opts and self._opts.outlineasy

  self.node.children = {}

  for i, path in ipairs(paths) do
    local file_bufnr = vim.fn.bufadd(path)
    if not vim.api.nvim_buf_is_loaded(file_bufnr) then
      vim.fn.bufload(file_bufnr)
      if ft then vim.bo[file_bufnr].filetype = ft end
      self._opened_bufs[file_bufnr] = true
    end

    local entry = self._file_agents[path]
    local file_node
    if entry then
      file_node = entry.file_node
    else
      file_node = node_m.new()
      file_node.ghost    = false
      file_node.file_uri = vim.uri_from_fname(path)
      if oa then oa.setup_file_node(file_node) end
    end

    file_node.parent = self.node; file_node.index = i
    self.node.children[i] = file_node

    if not entry then
      local file_ft    = vim.bo[file_bufnr].filetype
      local AgentClass = base.get_class(file_ft, "document") or DocumentBufferAgent
      local agent      = AgentClass.new(file_node)
      self._file_agents[path] = { agent = agent, file_node = file_node }
      local child_opts = vim.tbl_extend("force", self._opts or {}, { scope = "file" })
      agent:start(file_bufnr, child_opts)
    end
  end

  tree_m.update_node(self.node)

  -- Auto-expand each file node so symbol roots are immediately visible
  local set_open = self._opts and self._opts.set_open
  if set_open then
    for _, entry in pairs(self._file_agents) do
      set_open(entry.file_node, true)
    end
  end
end

-- Open all files, detect their filetype, keep only those matching ft.
-- Closes (unloads) buffers we opened that don't match.
function ModuleBufferAgent:_open_and_filter(all_paths, ft)
  local kept = {}
  for _, path in ipairs(all_paths) do
    if vim.fn.isdirectory(path) == 0 then
      local file_bufnr = vim.fn.bufadd(path)
      local was_loaded = vim.api.nvim_buf_is_loaded(file_bufnr)
      if not was_loaded then
        vim.fn.bufload(file_bufnr)
        self._opened_bufs[file_bufnr] = true
        -- Detect filetype
        vim.api.nvim_buf_call(file_bufnr, function()
          if vim.bo[file_bufnr].filetype == "" then
            vim.cmd("filetype detect")
          end
        end)
      end
      local buf_ft = vim.bo[file_bufnr].filetype
      if not ft or buf_ft == ft then
        table.insert(kept, path)
      else
        -- Wrong ft: unload if we just loaded it
        if self._opened_bufs[file_bufnr] then
          self._opened_bufs[file_bufnr] = nil
          pcall(vim.api.nvim_buf_delete, file_bufnr, { force = false, unload = true })
        end
      end
    end
  end
  return kept
end

return ModuleBufferAgent
