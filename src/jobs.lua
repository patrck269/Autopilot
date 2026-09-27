local config = require("config")

local M = {}

function M.thrust(rpm)
  local ratio = math.abs(rpm) / 256
  return 100000 * (ratio ^ 1.2)
end

function M.brake_rpm(speed, mass)
  if speed == nil or math.abs(speed) < 0.05 or mass == nil or mass <= 0 then
    return 0
  end
  local accel = (speed * speed) / 2
  local force = mass * accel
  local ratio = (force / 100000) ^ (1 / 1.2)
  local rpm = config.clamp_rpm(ratio * 256)
  if speed > 0 then
    return -rpm
  end
  return rpm
end

function M.stopping_distance(speed, rpm, mass)
  if speed == nil or math.abs(speed) < 0.05 then
    return 0
  end
  local force = M.thrust(rpm)
  if force <= 0 or mass == nil or mass <= 0 then
    return math.huge
  end
  local accel = force / mass
  return (speed * speed) / (2 * accel)
end

return M
