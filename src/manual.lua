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

-- Heading errors smaller than 1/30 of a degree are left alone.
local BEARING_DEADZONE = math.rad(1 / 30)

function M.bearing_rpm(error_rad, mass)
  if error_rad == nil or math.abs(error_rad) < BEARING_DEADZONE then
    return 0
  end
  local portion = math.abs(error_rad) / math.pi
  if portion > 1 then
    portion = 1
  end
  return M.rcs_rpm(portion, mass)
end

-- Below this the damper is chasing numerical noise, not a real heading error.
local YAW_RPM_DEADZONE = 0.05

function M.yaw_rpm(error_rad, yaw_rate, mass, damping)
  local portion = 0
  if math.abs(error_rad) >= BEARING_DEADZONE then portion = error_rad / math.pi end
  portion = math.max(-1, math.min(1, portion - (yaw_rate or 0) * (damping or 2)))
  if portion == 0 then
    return 0
  end
  local rpm = M.rcs_rpm(portion, mass)
  if portion < 0 then
    rpm = -rpm
  end
  if math.abs(rpm) < YAW_RPM_DEADZONE then
    return 0
  end
  return rpm
end

-- Control gain only. Clockwork propeller thrust is not 100000 N at 256 RPM.
function M.rcs_rpm(stick, mass)
  if stick == 0 then
    return 0
  end
  local force = mass * 0.25 * math.abs(stick)
  local ratio = (force / 100000) ^ (1 / 1.2)
  return config.clamp_rpm(ratio * 256)
end

return M
