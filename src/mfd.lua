local M = {}

function M.hit(w, h, x, y, names)
  if y ~= h then
    return nil
  end
  local slot = math.floor(w / 4)
  if slot < 1 then
    return nil
  end
  local index = math.floor((x - 1) / slot) + 1
  if index < 1 or index > 4 then
    return nil
  end
  return names[index]
end

return M
