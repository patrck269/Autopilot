local M = {}

function M.ramp_rate(current, target)
  return (target - current) / 15
end

function M.apply_ramp(current, target, rate, dt)
  local next_speed = current + rate * dt
  if rate > 0 and next_speed > target then
    return target
  end
  if rate < 0 and next_speed < target then
    return target
  end
  if rate == 0 then
    return target
  end
  return next_speed
end

function M.cap(value, limit)
  if value > limit then
    return limit
  end
  if value < -limit then
    return -limit
  end
  return value
end

function M.brake_distance(spd, accel)
  if accel <= 0 then
    return 0
  end
  return (spd * spd) / (2 * accel)
end

function M.relay2_level(command_speed, ref_speed)
  if ref_speed == 0 then
    return 0
  end
  local level = math.floor(math.abs(command_speed) / ref_speed * 15 + 0.5)
  if level < 0 then
    return 0
  end
  if level > 15 then
    return 15
  end
  return level
end

return M
