-- gopls provider for outlineasy.
--
-- gopls workspace/symbol is unreliable (empty query returns nothing).
-- Strategy: glob *.go in the target dir, ensure each file is loaded,
-- fan-out textDocument/documentSymbol requests.
--
-- Async contract:
--   notify(uri, Symbol[]) is called for each file as its results arrive.
--   done() is called once all files have been processed (success or failure).
--
-- On LspAttach timeout: the timer is purely a safety net for the case where
-- gopls never attaches to a buffer (wrong filetype, file error, etc.).
-- In that case we call notify with nothing for that file and decrement pending
-- so done() is eventually reached. We do NOT attempt a request on an
-- unattached buffer.

local symbols = require("outlineasy.symbols")

local M = {}

-- ── file scope: plain documentSymbol on the current buffer ───────────────────

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

-- ── Ensure a .go file buffer is loaded and has its filetype set ──────────────

local function ensure_loaded(path)
  local bufnr = vim.fn.bufadd(path)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
    -- filetype detect triggers lspconfig FileType autocmd → gopls attaches
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("filetype detect") end)
  end
  return bufnr
end

-- ── Wait for the client to attach to file_bufnr, then call cb ────────────────
-- If LspAttach never fires within 3s, cb() is called with (nil) so the
-- caller can decrement its pending counter and eventually reach done().
-- No request is attempted after timeout — the file is simply skipped.

local function on_attached(file_bufnr, client, cb)
  local fn = vim.lsp.get_clients or vim.lsp.get_active_clients
  for _, c in ipairs(fn({ bufnr = file_bufnr })) do
    if c.id == client.id then cb(client); return end
  end

  local fired = false
  local aug    = "outlineasy_gopls_wait_" .. file_bufnr
  local timer  = vim.loop.new_timer()

  local function give_up()
    if fired then return end
    fired = true
    pcall(timer.stop, timer); pcall(timer.close, timer)
    pcall(vim.api.nvim_del_augroup_by_name, aug)
    cb(nil)  -- signal: skip this file
  end

  local function on_attach()
    if fired then return end
    fired = true
    pcall(timer.stop, timer); pcall(timer.close, timer)
    pcall(vim.api.nvim_del_augroup_by_name, aug)
    cb(client)
  end

  vim.api.nvim_create_augroup(aug, { clear = true })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = aug, buffer = file_bufnr, once = true,
    callback = function() vim.schedule(on_attach) end,
  })
  timer:start(3000, 0, vim.schedule_wrap(give_up))
end

-- ── Fan-out documentSymbol across a list of .go files ────────────────────────

local function fan_out(files, source_bufnr, notify, done)
  if #files == 0 then done(); return end

  local fn = vim.lsp.get_clients or vim.lsp.get_active_clients

  local function find_client()
    for _, c in ipairs(fn({ bufnr = source_bufnr })) do
      if c.server_capabilities and c.server_capabilities.documentSymbolProvider then
        return c
      end
    end
  end

  local function run(client)
    if not client then done(); return end

    local pending = #files

    local function one_done()
      pending = pending - 1
      if pending == 0 then done() end
    end

    for _, path in ipairs(files) do
      local file_bufnr = ensure_loaded(path)
      local uri = vim.uri_from_fname(path)

      on_attached(file_bufnr, client, function(attached_client)
        if not attached_client then
          one_done()
          return
        end
        attached_client.request("textDocument/documentSymbol",
          { textDocument = { uri = uri } },
          function(err, result)
            vim.schedule(function()
              if not err and result and #result > 0 then
                notify(uri, symbols.from_doc(result, uri))
              end
              one_done()
            end)
          end, file_bufnr)
      end)
    end
  end

  -- If gopls is already attached to source_bufnr, run immediately.
  -- Otherwise wait for LspAttach — it fires when gopls finishes attaching
  -- after a buffer switch.
  local client = find_client()
  if client then
    run(client)
    return
  end

  local fired = false
  local aug   = "outlineasy_fanout_wait_" .. source_bufnr
  vim.api.nvim_create_augroup(aug, { clear = true })
  vim.api.nvim_create_autocmd("LspAttach", {
    group  = aug,
    buffer = source_bufnr,
    once   = true,
    callback = function()
      if fired then return end
      fired = true
      pcall(vim.api.nvim_del_augroup_by_name, aug)
      run(find_client())
    end,
  })
end

-- ── module scope: all *.go files in dir ──────────────────────────────────────

M.module = function(bufnr, dir, notify, done)
  local files = vim.fn.glob(dir .. "/*.go", false, true)
  fan_out(files, bufnr, notify, done)
end

-- ── all scope: all loaded .go buffers ────────────────────────────────────────

M.all = function(bufnr, notify, done)
  local files = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" then
      local name = vim.api.nvim_buf_get_name(b)
      if name:match("%.go$") then table.insert(files, name) end
    end
  end
  fan_out(files, bufnr, notify, done)
end

return M
