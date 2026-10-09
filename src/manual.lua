local config = require("config")

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
  local next_rpm = current_rpm
  if current_speed < target_speed - 0.05 then
    next_rpm = current_rpm + step
  elseif current_speed > target_speed + 0.05 then
    next_rpm = current_rpm - step
  elseif hold then
    next_rpm = current_rpm
  elseif math.abs(target_speed) <= 0.05 then
    if current_rpm > step then
      next_rpm = current_rpm - step
    elseif current_rpm < -step then
      next_rpm = current_rpm + step
    elseif current_rpm ~= 0 then
      next_rpm = 0
    end
  end
  return config.clamp_rpm(next_rpm)
end

function M.bearing_rpm(error_rad, mass)
  if error_rad == nil or math.abs(error_rad) < 0.02 then
    return 0
  end
  local portion = math.abs(error_rad) / math.pi
  if portion > 1 then
    portion = 1
  end
  return M.rcs_rpm(portion, mass)
end

function M.yaw_rpm(error_rad, yaw_rate, mass, damping)
  local portion = 0
  if math.abs(error_rad) >= 0.02 then portion = error_rad / math.pi end
  portion = math.max(-1, math.min(1, portion - (yaw_rate or 0) * (damping or 2)))
  local rpm = M.rcs_rpm(portion, mass)
  return portion < 0 and -rpm or rpm
end

function M.rcs_rpm(stick, mass)
  if stick == 0 then
    return 0
  end
  local force = mass * 0.25 * math.abs(stick)
  local ratio = (force / 100000) ^ (1 / 1.2)
  return config.clamp_rpm(ratio * 256)
end

return M
