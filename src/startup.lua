local M = {}

function M.missing(present, required)
  local found = {}
  for _, name in ipairs(required) do
    if present[name] ~= true then
      found[#found + 1] = name
    end
  end
  return found
end

return M
