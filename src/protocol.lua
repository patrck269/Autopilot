local M = {}

local function is_number(value)
  return type(value) == "number"
end

function M.validate(msg)
  if type(msg) ~= "table" then
    return nil
  end
  local kind = msg.type
  if kind == "stick" and is_number(msg.x) and is_number(msg.y) and is_number(msg.z) then
    return msg
  end
  if kind == "set_mode" and (msg.mode == "manual" or msg.mode == "semi" or msg.mode == "auto") then
    return msg
  end
  if kind == "set_altitude" and is_number(msg.y) then
    return msg
  end
  if kind == "set_bearing" and is_number(msg.bearing) then
    return msg
  end
  if kind == "set_speed" and is_number(msg.speed) then
    return msg
  end
  if kind == "set_waypoint" and is_number(msg.x) and is_number(msg.z) then
    return msg
  end
  if kind == "set_profile" and (msg.profile == "cruise" or msg.profile == "warp") then
    return msg
  end
  if kind == "return_to_user" and is_number(msg.x) and is_number(msg.z) then
    return msg
  end
  if kind == "emergency" or kind == "clear_emergency" or kind == "diagnostic_exit" then
    return msg
  end
  if kind == "diagnostic_enter" and type(msg.hover) == "boolean" then
    return msg
  end
  if kind == "diagnostic_elevation" and is_number(msg.rpm) then
    return msg
  end
  if kind == "diagnostic_set" and type(msg.device) == "string" then
    if is_number(msg.rpm) then
      return msg
    end
    if type(msg.side) == "string" and is_number(msg.level) then
      return msg
    end
  end
  return nil
end

return M
