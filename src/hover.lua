local M = {}

function M.adjust(rpm, vertical_speed, gain)
  return rpm - gain * vertical_speed
end

function M.desired_vertical(altitude, target_altitude, climb_rate)
  local gap = target_altitude - altitude
  if gap > climb_rate then
    return climb_rate
  end
  if gap < -climb_rate then
    return -climb_rate
  end
  return gap
end

function M.seek(rpm, vertical_speed, altitude, target_altitude, gain, step, climb_rate)
  local desired = M.desired_vertical(altitude, target_altitude, climb_rate)
  local gap = target_altitude - altitude
  local next_rpm = rpm + gain * (desired - vertical_speed)
  if math.abs(vertical_speed) < 0.05 and gap > 0.5 then
    next_rpm = next_rpm + step
  end
  if next_rpm < 0 then
    return 0
  end
  return next_rpm
end

return M
