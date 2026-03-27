-- Provider interface:
--
--   provider.file(bufnr, cb)
--     cb(Symbol[] | nil)  called once
--
--   provider.module(bufnr, dir, notify, done)
--   provider.all(bufnr, notify, done)
--     notify(uri, Symbol[])  called per file as results arrive
--     done()                 called when no more results are coming
--
-- Providers are matched by LSP server name.
-- Auto-loaded from overrides/<server_name>.lua on first use.

local symbols = require("outlineasy.symbols")
local M = {}

local _providers = {}

function M.set_provider(server_name, provider)
  _providers[server_name] = provider
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function get_clients(bufnr)
  local fn = vim.lsp.get_clients or vim.lsp.get_active_clients
  return fn({ bufnr = bufnr })
end

local function client_for(bufnr, capability)
  local clients = get_clients(bufnr)
  for _, c in ipairs(clients) do
    if c.server_capabilities and c.server_capabilities[capability] then
      return c
    end
  end
  return clients[1]
end

-- ── Default provider ──────────────────────────────────────────────────────────

local default_provider = {}

function default_provider.file(bufnr, cb)
  local uri = vim.uri_from_bufnr(bufnr)
  local ok = vim.lsp.buf_request(bufnr, "textDocument/documentSymbol",
    { textDocument = { uri = uri } },
    function(err, result)
      vim.schedule(function()
        if err or not result or #result == 0 then cb(nil); return end
        if result[1].location then
          cb(symbols.from_ws(result))
        else
          cb(symbols.from_doc(result, uri))
        end
      end)
    end)
  if not ok then vim.schedule(function() cb(nil) end) end
end

function default_provider.module(bufnr, dir, notify, done)
  local client = client_for(bufnr, "workspaceSymbolProvider")
  if not client then done(); return end
  client.request("workspace/symbol", { query = "" }, function(err, result)
    vim.schedule(function()
      if not err and result then
        local by_uri = {}
        for _, s in ipairs(result) do
          local uri = s.location and s.location.uri
          if uri and vim.fn.fnamemodify(vim.uri_to_fname(uri), ":h") == dir then
            by_uri[uri] = by_uri[uri] or {}
            table.insert(by_uri[uri], s)
          end
        end
        for uri, syms in pairs(by_uri) do
          notify(uri, symbols.from_ws(syms))
        end
      end
      done()
    end)
  end, bufnr)
end

function default_provider.all(bufnr, notify, done)
  local client = client_for(bufnr, "workspaceSymbolProvider")
  if not client then done(); return end
  client.request("workspace/symbol", { query = "" }, function(err, result)
    vim.schedule(function()
      if not err and result then
        local by_uri = {}
        for _, s in ipairs(result) do
          local uri = s.location and s.location.uri
          if uri then
            by_uri[uri] = by_uri[uri] or {}
            table.insert(by_uri[uri], s)
          end
        end
        for uri, syms in pairs(by_uri) do
          notify(uri, symbols.from_ws(syms))
        end
      end
      done()
    end)
  end, bufnr)
end

-- ── Registry + auto-load ──────────────────────────────────────────────────────

local function find_provider(bufnr)
  local clients = get_clients(bufnr)
  for _, c in ipairs(clients) do
    if _providers[c.name] then return _providers[c.name] end
    local ok, override = pcall(require, "outlineasy.overrides." .. c.name)
    if ok and override then
      _providers[c.name] = override
      return override
    end
  end
  if #clients > 0 then return default_provider end
  return nil  -- no clients attached yet
end

-- Resolve provider, waiting for LspAttach on bufnr if no clients yet.
local function get_provider(bufnr, cb)
  local p = find_provider(bufnr)
  if p then cb(p); return end

  local fired = false
  local aug = "outlineasy_provider_wait_" .. bufnr
  vim.api.nvim_create_augroup(aug, { clear = true })
  vim.api.nvim_create_autocmd("LspAttach", {
    group  = aug,
    buffer = bufnr,
    once   = true,
    callback = function()
      if fired then return end
      fired = true
      pcall(vim.api.nvim_del_augroup_by_name, aug)
      cb(find_provider(bufnr) or default_provider)
    end,
  })
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.file_symbols(bufnr, cb)
  -- file scope: LspAttach in init.lua handles retry, no need to wait here
  local p = find_provider(bufnr)
  if p then p.file(bufnr, cb) else vim.schedule(function() cb(nil) end) end
end

function M.module_symbols(bufnr, dir, notify, done)
  get_provider(bufnr, function(p) p.module(bufnr, dir, notify, done) end)
end

function M.all_symbols(bufnr, notify, done)
  get_provider(bufnr, function(p) p.all(bufnr, notify, done) end)
end

function M.rename(bufnr, position, new_name, cb)
  local client = client_for(bufnr, "renameProvider")
  if not client then
    vim.schedule(function() cb("no LSP client with renameProvider") end)
    return
  end
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position     = position,
    newName      = new_name,
  }
  client.request("textDocument/rename", params, function(err, result)
    vim.schedule(function()
      if err then cb(err.message or tostring(err)); return end
      if result then vim.lsp.util.apply_workspace_edit(result, client.offset_encoding) end
      cb(nil)
    end)
  end, bufnr)
end

return M
