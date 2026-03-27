-- Base agent helpers and registry.
--
-- Agents are matched by (filetype, scope). Override with:
--   require("outlineasy.agents.base").register(filetype, scope, AgentClass)
-- Pass "*" as filetype for the default.

local M = {}

-- ── Symbol normalisation ──────────────────────────────────────────────────────

-- DocumentSymbol tree → Symbol[] (recursive, preserves children)
function M.from_doc(syms, uri)
  local function walk(list)
    local out = {}
    for _, s in ipairs(list) do
      local sym = {
        name  = s.name,
        kind  = s.kind,
        uri   = uri,
        range = s.selectionRange or s.range,
      }
      if s.children and #s.children > 0 then
        sym.children = walk(s.children)
      end
      table.insert(out, sym)
    end
    return out
  end
  return walk(syms)
end

-- ── LSP helpers ───────────────────────────────────────────────────────────────

function M.get_clients(bufnr)
  local fn = vim.lsp.get_clients or vim.lsp.get_active_clients
  if bufnr then return fn({ bufnr = bufnr }) end
  return fn()
end

function M.client_for(bufnr, capability)
  for _, c in ipairs(M.get_clients(bufnr)) do
    if c.server_capabilities and c.server_capabilities[capability] then
      return c
    end
  end
end

-- ── Registry ──────────────────────────────────────────────────────────────────

local _registry = {}  -- [filetype][scope] = AgentClass

function M.register(filetype, scope, AgentClass)
  _registry[filetype] = _registry[filetype] or {}
  _registry[filetype][scope] = AgentClass
end

function M.get_class(filetype, scope)
  local ft = _registry[filetype]
  if ft and ft[scope] then return ft[scope] end
  local any = _registry["*"]
  if any and any[scope] then return any[scope] end
  return nil
end

-- ── Base class ────────────────────────────────────────────────────────────────

local Base = {}
Base.__index = Base

function Base.new(node)
  return setmetatable({ node = node, _alive = false }, Base)
end

function Base:start(_bufnr, _opts) self._alive = true end
function Base:change(_bufnr, _opts) return false end
function Base:kill() self._alive = false end
function Base:refresh() end

M.Base = Base

return M
