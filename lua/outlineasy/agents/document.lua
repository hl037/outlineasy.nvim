-- DocumentBufferAgent
--
-- Manages a single buffer in file scope.
-- Monitors LspAttach/LspDetach on the buffer.
-- Spawns one LspDocumentAgent per attached LSP client.
-- Node is ghost — symbols appear directly under it.

local base           = require("outlineasy.agents.base")
local LspDocumentAgent = require("outlineasy.agents.lsp_document")

local DocumentBufferAgent = {}
DocumentBufferAgent.__index = DocumentBufferAgent

function DocumentBufferAgent.new(node)
  return setmetatable({
    node      = node,
    _alive    = false,
    _bufnr    = nil,
    _opts     = nil,
    _lsp_agents = {},  -- client_id → LspDocumentAgent
    _aug      = nil,
  }, DocumentBufferAgent)
end

function DocumentBufferAgent:start(bufnr, opts)
  self._alive = true
  self._bufnr = bufnr
  self._opts  = opts
  self._aug   = "outlineasy_doc_" .. bufnr

  vim.api.nvim_create_augroup(self._aug, { clear = true })

  vim.api.nvim_create_autocmd("LspAttach", {
    group  = self._aug,
    buffer = bufnr,
    callback = function(ev)
      if not self._alive then return end
      self:_on_attach(ev.data and ev.data.client_id)
    end,
  })

  vim.api.nvim_create_autocmd("LspDetach", {
    group  = self._aug,
    buffer = bufnr,
    callback = function(ev)
      if not self._alive then return end
      self:_on_detach(ev.data and ev.data.client_id)
    end,
  })

  -- Attach to already-attached clients
  local fn = vim.lsp.get_clients or vim.lsp.get_active_clients
  for _, c in ipairs(fn({ bufnr = bufnr })) do
    self:_on_attach(c.id)
  end
end

function DocumentBufferAgent:change(bufnr, opts)
  -- Same buffer, same scope → nop
  if bufnr == self._bufnr and opts.scope == (self._opts and self._opts.scope) then
    return true
  end
  return false
end

function DocumentBufferAgent:kill()
  self._alive = false
  local tree_m = require("treeasy").tree
  for _, entry in pairs(self._lsp_agents) do
    entry.agent:kill()
    tree_m.replace_node(entry.node, nil)
  end
  self._lsp_agents = {}
  if self._aug then
    pcall(vim.api.nvim_del_augroup_by_name, self._aug)
    self._aug = nil
  end
end

function DocumentBufferAgent:refresh()
  for _, entry in pairs(self._lsp_agents) do
    entry.agent:refresh()
  end
end

function DocumentBufferAgent:_on_attach(client_id)
  if not client_id or self._lsp_agents[client_id] then return end

  local fn = vim.lsp.get_clients or vim.lsp.get_active_clients
  local client
  for _, c in ipairs(fn({ bufnr = self._bufnr })) do
    if c.id == client_id then client = c; break end
  end
  if not client or not (client.server_capabilities and
      client.server_capabilities.documentSymbolProvider) then return end

  local node_m = require("treeasy").node
  local tree_m = require("treeasy").tree
  local child_node = node_m.new(); child_node.ghost = true

  local AgentClass = base.get_class(client.name, "lsp_document")
                  or LspDocumentAgent
  local agent = AgentClass.new(child_node)

  -- Store agent on node for easy retrieval
  child_node._agent = agent
  self._lsp_agents[client_id] = { agent = agent, node = child_node }

  local child_opts = vim.tbl_extend("force", self._opts or {}, {
    lsp_client = client,
    on_error   = function(_msg)
      child_node._error = true
      tree_m.update_node(child_node)
    end,
  })

  if not self.node.children then self.node.children = {} end
  local idx = #self.node.children + 1
  child_node.parent = self.node; child_node.index = idx
  self.node.children[idx] = child_node
  tree_m.update_node(self.node)

  agent:start(self._bufnr, child_opts)
end

function DocumentBufferAgent:_on_detach(client_id)
  if not client_id then return end
  local entry = self._lsp_agents[client_id]
  if not entry then return end
  entry.agent:kill()
  require("treeasy").tree.replace_node(entry.node, nil)
  self._lsp_agents[client_id] = nil
end

return DocumentBufferAgent
