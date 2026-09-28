local config = require("config")

local M = {}

local SEA_LEVEL = 62
local MAX_Y = 2000
local GEOMETRIC_SPAN = 71000
local DENSITY_TOP = 84852
local GRAVITY = 10
local MOLAR_MASS = 0.0289644
local GAS_CONSTANT = 8.314
-- The configured equilibrium RPM cancels gravity at this world Y, not at sea level.
local REFERENCE_Y = 100

local LAYERS = {
  { height = 0, density = 1.225, temperature = 288.15, lapse = 0.0065, top = 11000 },
  { height = 11000, density = 0.36391, temperature = 216.65, lapse = 0, top = 20000 },
  { height = 20000, density = 0.08803, temperature = 216.65, lapse = -0.001, top = 32000 },
  { height = 32000, density = 0.01322, temperature = 228.65, lapse = -0.0028, top = 47000 },
  { height = 47000, density = 0.00143, temperature = 270.65, lapse = 0, top = 51000 },
  { height = 51000, density = 0.00086, temperature = 270.65, lapse = 0.0028, top = 71000 },
  { height = 71000, density = 6.4e-5, temperature = 214.65, lapse = 0.002, top = DENSITY_TOP },
}

local function geometric_height(world_y)
  if MAX_Y <= 0 then
    return GEOMETRIC_SPAN
  end
  local height = (world_y - SEA_LEVEL) * GEOMETRIC_SPAN / (MAX_Y - SEA_LEVEL)
  if height < 0 then
    return 0
  end
  return height
end

function M.air_density(world_y)
  if world_y == nil then
    world_y = REFERENCE_Y
  end
  local height = geometric_height(world_y)
  if height >= DENSITY_TOP then
    return 0
  end
  local layer = LAYERS[#LAYERS]
  for _, candidate in ipairs(LAYERS) do
    if height < candidate.top then
      layer = candidate
      break
    end
  end
  local rise = height - layer.height
  if layer.lapse == 0 then
    return layer.density * math.exp((-GRAVITY * MOLAR_MASS * rise) / (layer.temperature * GAS_CONSTANT))
  end
  local temperature = layer.temperature - rise * layer.lapse
  local exponent = (GRAVITY * MOLAR_MASS) / (layer.lapse * GAS_CONSTANT) - 1
  return layer.density * ((temperature / layer.temperature) ^ exponent)
end

function M.reference_y()
  return REFERENCE_Y
end

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
  local raw_err = target - altitude
  local err = raw_err
  local max_err = gains.max_rate * gains.kd / gains.kp
  if err > max_err then
    err = max_err
  elseif err < -max_err then
    err = -max_err
  end
  local settled = math.abs(raw_err) <= 0.5 and math.abs(vertical_speed) < 0.05
  local used_integral = integral
  local next_integral = integral + raw_err * dt
  if next_integral > gains.integral_limit then
    next_integral = gains.integral_limit
  elseif next_integral < -gains.integral_limit then
    next_integral = -gains.integral_limit
  end
  if settled then
    used_integral = 0
    next_integral = 0
  end
  local accel = gains.kp * err - gains.kd * vertical_speed + gains.ki * used_integral
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
  local density = M.air_density(altitude)
  local reference = M.air_density(REFERENCE_Y)
  local scale = 1
  if density > 0 and reference > 0 then
    scale = reference / density
  else
    scale = 1e6
  end
  local rpm = gains.equilibrium * (((specific / 10) * scale) ^ (1 / 1.2))
  return config.clamp_rpm(rpm), next_integral, reverser
end

return M
