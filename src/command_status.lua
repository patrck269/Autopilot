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
  return {
    mode = message.mode,
    altitude = message.altitude,
    speed = speed,
    su = message.su,
    line = "mode " .. tostring(message.mode)
      .. " alt " .. tostring(message.altitude)
      .. " spd " .. tostring(speed)
      .. " su " .. tostring(message.su),
  }
end

return M
