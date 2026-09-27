local M = {}

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
      return rpm
    end
    local held = rpm - near_gain * vertical_speed
    if held < 0 then
      return 0
    end
    return held
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
  return next_rpm
end

return M
