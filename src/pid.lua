local config = require("config")

local M = {}

function M.calibrate(equilibrium, step)
  if equilibrium == nil or equilibrium <= 0 then
    equilibrium = 430
  end
  if step == nil or step <= 0 then
    step = 0.05
  end
  local follow = 8
  local rate = 1
  return {
    kp = 1 / (follow * rate),
    ki = 0.015,
    kd = 1 / rate,
    equilibrium = equilibrium,
    max_rate = 16,
    integral_limit = 80,
    step = step,
  }
end

function M.command(gains, integral, altitude, target, vertical_speed, dt)
  if gains == nil then
    gains = M.calibrate(430, 0.05)
  end
  if dt == nil or dt <= 0 then
    dt = gains.step or 0.05
  end
  if integral == nil then
    integral = 0
  end
  if vertical_speed == nil then
    vertical_speed = 0
  end
  if altitude == nil then
    altitude = 0
  end
  if target == nil then
    target = altitude
  end
  local err = target - altitude
  local max_err = gains.max_rate * gains.kd / gains.kp
  if err > max_err then
    err = max_err
  elseif err < -max_err then
    err = -max_err
  end
  local accel = gains.kp * err - gains.kd * vertical_speed + gains.ki * integral
  local next_integral = integral + (target - altitude) * dt
  if next_integral > gains.integral_limit then
    next_integral = gains.integral_limit
  elseif next_integral < -gains.integral_limit then
    next_integral = -gains.integral_limit
  end
  local reverser = false
  local specific
  if accel < -10 and vertical_speed > 0.05 then
    reverser = true
    specific = -accel - 10
  else
    if accel < -9.5 then
      accel = -9.5
    end
    specific = 10 + accel
  end
  if specific < 0 then
    specific = 0
  end
  local rpm = gains.equilibrium * ((specific / 10) ^ (1 / 1.2))
  return config.clamp_rpm(rpm), next_integral, reverser
end

return M
