local M = {}

function M.apply(message)
  if type(message) ~= "table" then
    return nil
  end
  if message.mode == nil or message.altitude == nil or message.su == nil then
    return nil
  end
  local speed = message.horizontal_speed
  if speed == nil then
    speed = message.speed
  end
  if speed == nil then
    return nil
  end
  local line = "mode " .. tostring(message.mode)
    .. " alt " .. tostring(message.altitude)
    .. " spd " .. tostring(speed)
    .. " su " .. tostring(message.su)
  if message.su_remaining ~= nil then
    line = line .. " SU remaining " .. tostring(message.su_remaining)
  end
  return {
    mode = message.mode,
    altitude = message.altitude,
    speed = speed,
    su = message.su,
    su_remaining = message.su_remaining,
    line = line,
  }
end

return M
