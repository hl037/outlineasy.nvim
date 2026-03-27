-- LspDocumentAgent
--
-- Manages a single LSP client on an already-attached buffer.
-- Receives a ghost node and populates it with symbol nodes.
-- Can be overridden per lsp_name via the registry in base.lua.
-- Notifies parent of errors via opts.on_error(msg) if provided.

local base    = require("outlineasy.agents.base")
local symbols = require("outlineasy.symbols")

local LspDocumentAgent = {}
LspDocumentAgent.__index = LspDocumentAgent

function LspDocumentAgent.new(node)
  return setmetatable({
    node    = node,
    _alive  = false,
    _bufnr  = nil,
    _client = nil,
    _opts   = nil,
  }, LspDocumentAgent)
end

function LspDocumentAgent:start(bufnr, opts)
  self._alive  = true
  self._bufnr  = bufnr
  self._opts   = opts
  self._client = opts.lsp_client
  self:_query()
end

function LspDocumentAgent:change(_bufnr, _opts)
  return false  -- always replaced by parent
end

function LspDocumentAgent:kill()
  self._alive = false
end

function LspDocumentAgent:refresh()
  if self._alive then self:_query() end
end

function LspDocumentAgent:_query()
  local bufnr  = self._bufnr
  local client = self._client
  local node   = self.node
  if not (bufnr and client and node) then return end

  local uri = vim.uri_from_bufnr(bufnr)
  local self_ref = self

  client.request("textDocument/documentSymbol",
    { textDocument = { uri = uri } },
    function(err, result)
      vim.schedule(function()
        if not self_ref._alive then return end
        if err or not result or #result == 0 then
          if err and self_ref._opts and self_ref._opts.on_error then
            self_ref._opts.on_error(err.message or tostring(err))
          end
          return
        end
        self_ref:_populate(symbols.from_doc(result, uri))
      end)
    end, bufnr)
end

function LspDocumentAgent:_populate(syms)
  if not self._alive then return end
  local node   = self.node
  local oa     = self._opts and self._opts.outlineasy
  local tree_m = require("treeasy").tree
  local node_m = require("treeasy").node

  -- Sort by line
  table.sort(syms, function(a, b)
    return (a.range and a.range.start.line or 0)
         < (b.range and b.range.start.line or 0)
  end)

  node.children = {}
  for i, sym in ipairs(syms) do
    local sn = oa and oa.new_sym_node(sym) or _make_sym_node(sym, node_m)
    sn.parent = node; sn.index = i
    node.children[i] = sn
  end

  tree_m.update_node(node)
end

-- Fallback node builder if outlineasy ref not available
local function _make_sym_node(sym, node_m)
  local n = node_m.new()
  n.sym_kind  = sym.kind
  n.sym_name  = sym.name
  n.sym_uri   = sym.uri
  n.sym_range = sym.range
  return n
end

return LspDocumentAgent
