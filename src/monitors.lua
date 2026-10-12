local M = {}

local COMMAND = {
  monitor_4 = "Flight",
  monitor_5 = "Navigation",
  monitor_6 = "Engines",
  monitor_7 = "Emergency",
}

function M.assign(list)
  local pages = {}
  for _, item in ipairs(list) do
    local page = COMMAND[item.name]
    if page ~= nil then
      pages[item.name] = page
    end
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
