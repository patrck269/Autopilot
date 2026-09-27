local M = {}

function M.velocity(sx, sy, sz)
  local length = math.sqrt(sx * sx + sy * sy + sz * sz)
  if length == 0 then
    return 0, 0, 0
  end
  local scale = 3 / length
  return sx * scale, sy * scale, sz * scale
end

return M
