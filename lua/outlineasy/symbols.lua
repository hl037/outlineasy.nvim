local M = {}

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

return M
