-- Normalized symbol format used throughout outlineasy:
-- {
--   name     = string,
--   kind     = number,      -- LSP SymbolKind
--   uri      = string,      -- file:// URI
--   range    = Range,       -- { start={line,character}, end={line,character} }
--   children = Symbol[],    -- optional
-- }

local M = {}

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

-- SymbolInformation[] → Symbol[] (flat, no children)
function M.from_ws(syms)
  local out = {}
  for _, s in ipairs(syms) do
    local uri = s.location and s.location.uri
    if uri then
      table.insert(out, {
        name  = s.name,
        kind  = s.kind,
        uri   = uri,
        range = s.location.range,
      })
    end
  end
  return out
end

return M
