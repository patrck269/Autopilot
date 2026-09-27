local config = require("config")

local M = {}

local GRAVITY = 10

function M.thrust(rpm, mass)
  if mass == nil or mass <= 0 then
    return 0
  end
  local hover = config.default().hover_equilibrium
  if hover == nil or hover <= 0 then
    hover = 430
  end
  local ratio = math.abs(rpm) / hover
  return mass * GRAVITY * (ratio ^ 1.2)
end

function M.brake_rpm(speed, mass)
  if speed == nil or math.abs(speed) < 0.05 or mass == nil or mass <= 0 then
    return 0
  end
  local hover = config.default().hover_equilibrium
  if hover == nil or hover <= 0 then
    hover = 430
  end
  local accel = (speed * speed) / 2
  local force = mass * accel
  local ratio = (force / (mass * GRAVITY)) ^ (1 / 1.2)
  local rpm = config.clamp_rpm(hover * ratio)
  if speed > 0 then
    return -rpm
  end
  return rpm
end

function M.stopping_distance(speed, rpm, mass)
  if speed == nil or math.abs(speed) < 0.05 then
    return 0
  end
  local force = M.thrust(rpm, mass)
  if force <= 0 or mass == nil or mass <= 0 then
    return math.huge
  end
  local accel = force / mass
  return (speed * speed) / (2 * accel)
end

return M
