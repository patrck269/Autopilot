local M = {}

function M.stop_distance(speed)
  local accel = (speed * speed) / 2
  if accel < 1 then
    accel = 1
  end
  local distance = (speed * speed) / (2 * accel)
  if distance > 1 then
    return 1
  end
  return distance
end

return M
