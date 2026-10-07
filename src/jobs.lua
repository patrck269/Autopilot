local config = require("config")

local M = {}

local GRAVITY = 10
local STEP = 0.05
-- Same bound the altitude hold already uses. A faster vertical stop flips the
-- reverser or steps the elevation integer on every sign change, and Create
-- deletes that speed controller.
local VERTICAL_ACCEL = 4

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

local function cap_vertical(accel)
  if accel > VERTICAL_ACCEL then
    return VERTICAL_ACCEL
  end
  if accel < 0 then
    return 0
  end
  return accel
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
    return 0, false
  end
  if vertical_speed == nil or math.abs(vertical_speed) < 0.05 then
    if hold_rpm == nil or hold_rpm < 0 then
      return 0, false
    end
    return config.clamp_rpm(hold_rpm), false
  end
  local stopping = cap_vertical(stop_accel(vertical_speed))
  if vertical_speed > 0 then
    -- The cap stays under 1 g, so gravity finishes the climb and the reverser
    -- stays off. Flipping it walks the controller through zero.
    if stopping > GRAVITY then
      return rpm_for_thrust(stopping - GRAVITY), true
    end
    return rpm_for_thrust(GRAVITY - stopping), false
  end
  return rpm_for_thrust(GRAVITY + stopping), false
end

function M.arrest_climb(vertical_speed, distance)
  if vertical_speed == nil or vertical_speed <= 0.05 then
    return nil, false
  end
  if distance == nil or distance <= 0 then
    return nil, false
  end
  local gravity_room = (vertical_speed * vertical_speed) / (2 * GRAVITY)
  if gravity_room + 2 < distance then
    return nil, false
  end
  if GRAVITY * STEP >= vertical_speed then
    return nil, false
  end
  local needed = (vertical_speed * vertical_speed) / (2 * distance)
  local stopping = stop_accel(vertical_speed)
  if needed > stopping then
    needed = stopping
  end
  if needed <= GRAVITY then
    return 0, false
  end
  return rpm_for_thrust(needed - GRAVITY), true
end

local function braking_rate(rpm, mass, speed, vertical, reverser)
  if mass == nil or mass <= 0 or rpm == nil or speed == nil then
    return 0
  end
  local specific = M.thrust(rpm, mass) / mass
  local rate
  if vertical then
    if speed > 0 then
      if reverser then
        rate = GRAVITY + specific
      else
        rate = GRAVITY - specific
      end
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
  if not vertical then
    local rpm = rpm_for_thrust(finish)
    if speed > 0 then
      return -rpm, false
    end
    return rpm, false
  end
  finish = cap_vertical(finish)
  if speed > 0 and finish > GRAVITY then
    return rpm_for_thrust(finish - GRAVITY), true
  end
  if speed > 0 then
    return rpm_for_thrust(GRAVITY - finish), false
  end
  return rpm_for_thrust(GRAVITY + finish), false
end

function M.hold_stop(captured, speed, mass, rest_rpm, vertical)
  if rest_rpm == nil then
    rest_rpm = 0
  end
  if speed == nil then
    speed = 0
  end
  if vertical and captured ~= nil then
    local captured_accel = captured.accel or 0
    if captured.reverser == true or captured_accel > VERTICAL_ACCEL + 1 then
      captured = nil
    end
  end
  if captured ~= nil then
    local grew = vertical and math.abs(speed) > math.abs(captured.speed or 0) + 0.5
    if not grew then
      if math.abs(speed) < 0.05 then
        return rest_rpm, nil, false
      end
      local sign = 1
      if speed < 0 then
        sign = -1
      end
      if sign ~= captured.sign then
        local rpm, reverser = finish_rpm(speed, vertical)
        return rpm, nil, reverser
      end
      if math.abs(speed) <= captured.accel * STEP * (1 + 1e-4) then
        local rpm, reverser = finish_rpm(speed, vertical)
        return rpm, nil, reverser
      end
      return captured.rpm, captured, captured.reverser == true
    end
  end
  if math.abs(speed) < 0.05 then
    return rest_rpm, nil, false
  end
  local rpm, reverser = 0, false
  if vertical then
    rpm, reverser = M.elevation_brake_rpm(speed, mass, rest_rpm)
  else
    rpm = M.brake_rpm(speed, mass)
  end
  local sign = 1
  if speed < 0 then
    sign = -1
  end
  local accel = braking_rate(rpm, mass, speed, vertical, reverser)
  return rpm, { rpm = rpm, sign = sign, accel = accel, reverser = reverser, speed = speed }, reverser
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
