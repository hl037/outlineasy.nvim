local M = {}

M.S = {
  win         = nil,
  tree        = nil,
  view        = nil,
  ghost       = nil,
  header      = nil,
  filter_node = nil,
  scope       = "file",
  hidden_kinds = {},
  buf         = nil,
  dir         = nil,
  width       = 40,
  side        = "left",
  icons       = true,
  refreshing  = false,  -- true while a module/all refresh is in flight
}

local STATE_FILE = vim.fn.stdpath("data") .. "/outlineasy/state.json"

function M.load()
  local f = io.open(STATE_FILE, "r")
  if not f then return end
  local raw = f:read("*a"); f:close()
  local ok, data = pcall(vim.fn.json_decode, raw)
  if not ok or type(data) ~= "table" then return end
  if data.scope then M.S.scope = data.scope end
  if type(data.hidden_kinds) == "table" then
    M.S.hidden_kinds = {}
    for _, k in ipairs(data.hidden_kinds) do M.S.hidden_kinds[k] = true end
  end
end

function M.save()
  vim.fn.mkdir(vim.fn.fnamemodify(STATE_FILE, ":h"), "p")
  local f = io.open(STATE_FILE, "w")
  if not f then return end
  local hidden_list = {}
  for k in pairs(M.S.hidden_kinds) do table.insert(hidden_list, k) end
  f:write(vim.fn.json_encode({ scope = M.S.scope, hidden_kinds = hidden_list }))
  f:close()
end

return M
