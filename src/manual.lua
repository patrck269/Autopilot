local M = {}

function M.velocity(sx, sy, sz)
  local length = math.sqrt(sx * sx + sy * sy + sz * sz)
  if length == 0 then
    return 0, 0, 0
  end
  local scale = 3 / length
  return sx * scale, sy * scale, sz * scale
end

function M.release_effort(velocity)
  if velocity > 0.05 then
    return -1
  end
  if velocity < -0.05 then
    return 1
  end
  return 0
end

function M.x_rpm(current_rpm, current_speed, target_speed, step, hold)
  if current_speed < target_speed - 0.05 then
    return current_rpm + step
  end
  if current_speed > target_speed + 0.05 then
    return current_rpm - step
  end
  if hold then
    return current_rpm
  end
  if math.abs(target_speed) <= 0.05 then
    if current_rpm > step then
      return current_rpm - step
    end
    if current_rpm < -step then
      return current_rpm + step
    end
    if current_rpm ~= 0 then
      return 0
    end
  end
  return current_rpm
end

function M.rcs_rpm(stick, mass)
  if stick == 0 then
    return 0
  end
  local force = mass * 0.25 * math.abs(stick)
  local ratio = (force / 100000) ^ (1 / 1.2)
  return ratio * 256
end

return M
