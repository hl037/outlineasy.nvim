-- gopls provider for outlineasy.
--
-- gopls workspace/symbol is unreliable (empty query returns nothing).
-- Strategy: glob *.go, load each as a buffer, set up a per-buffer LspAttach
-- autocmd, and send documentSymbol immediately when gopls attaches.
-- Results are aggregated incrementally via notify/done.

local symbols = require("outlineasy.symbols")
local M = {}

-- ── file scope ────────────────────────────────────────────────────────────────

M.file = function(bufnr, cb)
  local uri = vim.uri_from_bufnr(bufnr)
  local ok = vim.lsp.buf_request(bufnr, "textDocument/documentSymbol",
    { textDocument = { uri = uri } },
    function(err, result)
      vim.schedule(function()
        if err or not result or #result == 0 then cb(nil); return end
        cb(symbols.from_doc(result, uri))
      end)
    end)
  if not ok then vim.schedule(function() cb(nil) end) end
end

-- ── shared fan-out ────────────────────────────────────────────────────────────

local function fan_out(paths, source_bufnr, notify, done)
  if #paths == 0 then done(); return end

  local function find_gopls()
    local fn = vim.lsp.get_clients or vim.lsp.get_active_clients
    for _, c in ipairs(fn()) do
      if c.name == "gopls" then return c end
    end
  end

  local client = find_gopls()
  if not client then done(); return end

  local pending   = #paths
  local requested = {}  -- bufnr → true, guard double requests

  local function one_done()
    pending = pending - 1
    if pending == 0 then done() end
  end

  local function request_for(file_bufnr, uri)
    if requested[file_bufnr] then return end
    requested[file_bufnr] = true
    client.request("textDocument/documentSymbol",
      { textDocument = { uri = uri } },
      function(err, result)
        vim.schedule(function()
          if not err and result and #result > 0 then
            notify(uri, symbols.from_doc(result, uri))
          end
          one_done()
        end)
      end, file_bufnr)
  end

  for _, path in ipairs(paths) do
    local file_bufnr = vim.fn.bufadd(path)
    local uri        = vim.uri_from_fname(path)

    if not vim.api.nvim_buf_is_loaded(file_bufnr) then
      vim.fn.bufload(file_bufnr)
      vim.bo[file_bufnr].filetype = "go"
    end

    -- Check if gopls is already attached to this buffer
    local fn = vim.lsp.get_clients or vim.lsp.get_active_clients
    local attached = false
    for _, c in ipairs(fn({ bufnr = file_bufnr })) do
      if c.id == client.id then attached = true; break end
    end

    if attached then
      request_for(file_bufnr, uri)
    else
      -- Per-buffer LspAttach: scoped to this buffer only, fires once
      vim.api.nvim_create_autocmd("LspAttach", {
        buffer = file_bufnr,
        once   = true,
        callback = function(ev)
          if ev.data and ev.data.client_id == client.id then
            request_for(file_bufnr, uri)
          end
        end,
      })
    end
  end
end

-- ── module scope ──────────────────────────────────────────────────────────────

M.module = function(bufnr, dir, notify, done)
  local paths = vim.fn.glob(dir .. "/*.go", false, true)
  fan_out(paths, bufnr, notify, done)
end

-- ── all scope ─────────────────────────────────────────────────────────────────

M.all = function(bufnr, notify, done)
  local paths = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" then
      local name = vim.api.nvim_buf_get_name(b)
      if name:match("%.go$") then table.insert(paths, name) end
    end
  end
  fan_out(paths, bufnr, notify, done)
end

return M
