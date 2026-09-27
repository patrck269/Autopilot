local config = require("config")

local M = {}

local GRAVITY = 10
local STEP = 0.05

local function hover_setting()
  local hover = config.default().hover_equilibrium
  if hover == nil or hover <= 0 then
    return 430
  end
  return hover
end

local function stop_accel(speed)
  local v = math.abs(speed)
  local ticks = math.floor((2 / v) / STEP)
  if ticks < 1 then
    ticks = 1
  end
  return v / (ticks * STEP)
end

local function rpm_for_thrust(thrust_accel)
  if thrust_accel < 0 then
    thrust_accel = 0
  end
  return config.clamp_rpm(hover_setting() * ((thrust_accel / GRAVITY) ^ (1 / 1.2)))
end

function M.thrust(rpm, mass)
  if mass == nil or mass <= 0 then
    return 0
  end
  local ratio = math.abs(rpm) / hover_setting()
  return mass * GRAVITY * (ratio ^ 1.2)
end

function M.brake_rpm(speed, mass)
  if speed == nil or math.abs(speed) < 0.05 or mass == nil or mass <= 0 then
    return 0
  end
  local rpm = rpm_for_thrust(stop_accel(speed))
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
  local stopping = stop_accel(vertical_speed)
  local thrust_accel = GRAVITY - stopping
  if vertical_speed < 0 then
    thrust_accel = GRAVITY + stopping
  end
  return rpm_for_thrust(thrust_accel)
end

local function braking_rate(rpm, mass, speed, vertical)
  if mass == nil or mass <= 0 or rpm == nil or speed == nil then
    return 0
  end
  local specific = M.thrust(rpm, mass) / mass
  local rate
  if vertical then
    if speed > 0 then
      rate = GRAVITY - specific
    else
      rate = specific - GRAVITY
    end
  elseif (speed > 0 and rpm < 0) or (speed < 0 and rpm > 0) then
    rate = specific
  else
    rate = 0
  end
  if rate < 0 then
    return 0
  end
  return rate
end

local function finish_rpm(speed, vertical)
  local finish = math.abs(speed) / STEP
  if vertical then
    local thrust_accel = GRAVITY - finish
    if speed < 0 then
      thrust_accel = GRAVITY + finish
    end
    return rpm_for_thrust(thrust_accel)
  end
  local rpm = rpm_for_thrust(finish)
  if speed > 0 then
    return -rpm
  end
  return rpm
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
      return finish_rpm(speed, vertical), nil
    end
    if math.abs(speed) <= captured.accel * STEP * (1 + 1e-4) then
      return finish_rpm(speed, vertical), nil
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
  local accel = braking_rate(rpm, mass, speed, vertical)
  return rpm, { rpm = rpm, sign = sign, accel = accel }
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
