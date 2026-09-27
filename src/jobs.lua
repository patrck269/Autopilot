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

function M.elevation_brake_rpm(vertical_speed, mass, hold_rpm)
  if mass == nil or mass <= 0 then
    return 0
  end
  if vertical_speed == nil or math.abs(vertical_speed) < 0.05 then
    if hold_rpm == nil or hold_rpm < 0 then
      return 0
    end
    return config.clamp_rpm(hold_rpm)
  end
  local hover = config.default().hover_equilibrium
  if hover == nil or hover <= 0 then
    hover = 430
  end
  local stopping = (vertical_speed * vertical_speed) / 2
  local thrust_accel = GRAVITY - stopping
  if vertical_speed < 0 then
    thrust_accel = GRAVITY + stopping
  end
  if thrust_accel < 0 then
    thrust_accel = 0
  end
  local ratio = (thrust_accel / GRAVITY) ^ (1 / 1.2)
  return config.clamp_rpm(hover * ratio)
end

function M.hold_stop(captured, speed, mass, rest_rpm, vertical)
  if rest_rpm == nil then
    rest_rpm = 0
  end
  if speed == nil then
    speed = 0
  end
  if captured ~= nil then
    if math.abs(speed) < 0.05 then
      return rest_rpm, nil
    end
    local sign = 1
    if speed < 0 then
      sign = -1
    end
    if sign ~= captured.sign then
      return rest_rpm, nil
    end
    return captured.rpm, captured
  end
  if math.abs(speed) < 0.05 then
    return rest_rpm, nil
  end
  local rpm
  if vertical then
    rpm = M.elevation_brake_rpm(speed, mass, rest_rpm)
  else
    rpm = M.brake_rpm(speed, mass)
  end
  local sign = 1
  if speed < 0 then
    sign = -1
  end
  return rpm, { rpm = rpm, sign = sign }
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
