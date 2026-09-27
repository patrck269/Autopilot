local M = {}

local ORDER = { "Flight", "Navigation", "Engines", "Emergency" }

function M.assign(list)
  local items = {}
  for i, item in ipairs(list) do
    items[i] = item
  end
  table.sort(items, function(a, b)
    local as = a.w * a.h
    local bs = b.w * b.h
    if as ~= bs then
      return as > bs
    end
    return a.name < b.name
  end)
  local pages = {}
  for i, item in ipairs(items) do
    pages[item.name] = ORDER[i]
  end
  return pages
end

function M.swap(map, from_name, to_name)
  local next_map = {}
  for name, page in pairs(map) do
    next_map[name] = page
  end
  if next_map[from_name] == nil or next_map[to_name] == nil then
    return next_map
  end
  next_map[from_name], next_map[to_name] = next_map[to_name], next_map[from_name]
  return next_map
end

return M
