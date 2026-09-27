local config = require("config")

local M = {}

function M.use_reverser(failed_prop)
  return failed_prop == true
end

function M.remember(memory, altitude, rpm)
  memory[math.floor(altitude + 0.5)] = rpm
end

function M.recall(memory, altitude)
  local key = math.floor(altitude + 0.5)
  if memory[key] ~= nil then
    return memory[key]
  end
  local best = nil
  local best_dist = nil
  for stored, rpm in pairs(memory) do
    local dist = math.abs(stored - key)
    if dist <= 2 and (best_dist == nil or dist < best_dist) then
      best = rpm
      best_dist = dist
    end
  end
  return best
end

local function rpm_for_accel(acceleration, equilibrium)
  local powered = 1 + acceleration / 10
  if powered < 0.05 then
    powered = 0.05
  end
  if equilibrium == nil or equilibrium <= 0 then
    equilibrium = 430
  end
  return equilibrium * (powered ^ (1 / 1.2))
end

function M.descend_rpm(rpm, vertical_speed, altitude, target, deadzone, dt, equilibrium)
  if dt == nil or dt <= 0 then
    dt = 0.05
  end
  local wn = 0.45
  local zeta = 1.6
  local accel = -2 * zeta * wn * vertical_speed - wn * wn * (altitude - target)
  if accel > 3 then
    accel = 3
  end
  if accel < -3 then
    accel = -3
  end
  if altitude < target - deadzone then
    accel = 2
  end
  local commanded = rpm_for_accel(accel, equilibrium)
  local max_step = 120 * dt
  local delta = commanded - rpm
  if delta > max_step then
    delta = max_step
  end
  if delta < -max_step then
    delta = -max_step
  end
  local next_rpm = rpm + delta
  if next_rpm < 0 then
    return 0
  end
  return config.clamp_rpm(next_rpm)
end

function M.simulate_descent(altitude, target, deadzone, rpm, step)
  local equilibrium = rpm
  if equilibrium == nil or equilibrium <= 0 then
    equilibrium = 430
  end
  local y = altitude
  local vertical_speed = 0
  local thrust = rpm or equilibrium
  local lowest = thrust
  local min_y = y
  local top = target + deadzone
  local bottom = target - deadzone
  local dt = 0.05
  if step ~= nil and step > 0 and step < 1 then
    dt = step
  end
  local steps = math.floor(20 / dt + 0.5)
  for _ = 1, steps do
    thrust = M.descend_rpm(thrust, vertical_speed, y, target, deadzone, dt, equilibrium)
    if thrust < lowest then
      lowest = thrust
    end
    local ratio = 0
    if thrust > 0 then
      ratio = thrust / equilibrium
    end
    local acceleration = 10 * (ratio ^ 1.2 - 1)
    vertical_speed = vertical_speed + acceleration * dt
    y = y + vertical_speed * dt
    if y < min_y then
      min_y = y
    end
  end
  return {
    altitude = y,
    rpm = thrust,
    lowest_rpm = lowest,
    reverser = false,
    inside = y <= top and y >= bottom,
    min_altitude = min_y,
  }
end

function M.adjust(rpm, vertical_speed, gain)
  return rpm - gain * vertical_speed
end

function M.desired_vertical(altitude, target_altitude, deadzone, approach)
  local gap = target_altitude - altitude
  local distance = math.abs(gap)
  if distance <= deadzone then
    return 0
  end
  local sign = 1
  if gap < 0 then
    sign = -1
  end
  if distance <= approach then
    return sign * ((distance - deadzone) / 60)
  end
  return sign * ((distance - approach) / 15)
end

function M.seek(rpm, vertical_speed, altitude, target_altitude, gain, step, deadzone, approach, near_gain, near_step)
  local gap = target_altitude - altitude
  local distance = math.abs(gap)
  if distance <= deadzone then
    if math.abs(vertical_speed) < 0.05 then
      return config.clamp_rpm(rpm)
    end
    local held = rpm - near_gain * vertical_speed
    if held < 0 then
      return 0
    end
    return config.clamp_rpm(held)
  end
  local use_gain = gain
  local use_step = step
  if distance <= approach then
    use_gain = near_gain
    use_step = near_step
  end
  local desired = M.desired_vertical(altitude, target_altitude, deadzone, approach)
  local next_rpm = rpm + use_gain * (desired - vertical_speed)
  if math.abs(vertical_speed) < 0.05 and gap > deadzone then
    next_rpm = next_rpm + use_step
  end
  if next_rpm < 0 then
    return 0
  end
  return config.clamp_rpm(next_rpm)
end

return M
