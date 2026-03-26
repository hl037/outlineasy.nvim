local M = {}

local function best_client(bufnr)
  local fn = vim.lsp.get_clients or vim.lsp.get_active_clients
  local clients = fn({ bufnr = bufnr })
  for _, c in ipairs(clients) do
    if c.server_capabilities and c.server_capabilities.documentSymbolProvider then
      return c
    end
  end
  return clients[1]
end

-- cb(DocumentSymbol[] | SymbolInformation[] | nil)
function M.document_symbols(bufnr, cb)
  local params = { textDocument = { uri = vim.uri_from_bufnr(bufnr) } }
  local ok = vim.lsp.buf_request(bufnr, "textDocument/documentSymbol", params,
    function(err, result)
      vim.schedule(function() cb(err and nil or result) end)
    end)
  if not ok then vim.schedule(function() cb(nil) end) end
end

-- cb(nil | err_string) — renames symbol at position in bufnr
function M.rename(bufnr, position, new_name, cb)
  local fn = vim.lsp.get_clients or vim.lsp.get_active_clients
  local clients = fn({ bufnr = bufnr })
  local client
  for _, c in ipairs(clients) do
    if c.server_capabilities and c.server_capabilities.renameProvider then
      client = c; break
    end
  end
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

-- cb(SymbolInformation[] | nil)
-- dir: exact parent directory to match (package scope), nil = whole workspace
function M.workspace_symbols(bufnr, dir, cb)
  local client = best_client(bufnr)
  if not client then
    vim.schedule(function() cb(nil) end)
    return
  end
  client.request("workspace/symbol", { query = "" }, function(err, result)
    vim.schedule(function()
      if err or not result then cb(nil); return end
      if not dir then cb(result); return end
      local out = {}
      for _, sym in ipairs(result) do
        local sym_dir = vim.fn.fnamemodify(vim.uri_to_fname(sym.location.uri), ":h")
        if sym_dir == dir then table.insert(out, sym) end
      end
      cb(out)
    end)
  end, bufnr)
end

return M
