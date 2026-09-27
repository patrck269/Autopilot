local protocol = require("protocol")

local M = {}

function M.new()
  return {
    stick = { x = 0, y = 0, z = 0 },
    buffer = "",
    field = nil,
    profile = "warp",
    waypoint_x = 0,
    waypoint_z = 0,
  }
end

local function stick_msg(state)
  return protocol.validate({
    type = "stick",
    x = state.stick.x,
    y = state.stick.y,
    z = state.stick.z,
  })
end

local function set_axis(state, axis, value, down)
  if down then
    state.stick[axis] = value
  elseif state.stick[axis] == value then
    state.stick[axis] = 0
  end
  return stick_msg(state)
end

function M.key(state, name, down)
  if name == "right" then
    return state, set_axis(state, "x", 1, down)
  end
  if name == "left" then
    return state, set_axis(state, "x", -1, down)
  end
  if name == "d" then
    return state, set_axis(state, "y", 1, down)
  end
  if name == "a" then
    return state, set_axis(state, "y", -1, down)
  end
  if name == "space" or name == "up" then
    return state, set_axis(state, "z", 1, down)
  end
  if name == "leftShift" or name == "down" then
    return state, set_axis(state, "z", -1, down)
  end
  if not down then
    return state, nil
  end
  if name == "m" then
    return state, protocol.validate({ type = "set_mode", mode = "manual" })
  end
  if name == "s" then
    return state, protocol.validate({ type = "set_mode", mode = "semi" })
  end
  if name == "u" then
    return state, protocol.validate({ type = "set_mode", mode = "auto" })
  end
  if name == "e" then
    return state, protocol.validate({ type = "emergency" })
  end
  if name == "c" then
    return state, protocol.validate({ type = "clear_emergency" })
  end
  if name == "w" then
    if state.profile == "warp" then
      state.profile = "cruise"
    else
      state.profile = "warp"
    end
    return state, protocol.validate({ type = "set_profile", profile = state.profile })
  end
  local fields = { x = "x", z = "z", y = "y", b = "bearing", v = "speed" }
  if fields[name] ~= nil then
    state.field = fields[name]
    state.buffer = ""
    return state, nil
  end
  if state.field ~= nil and (name == "-" or name == "." or (name >= "0" and name <= "9")) then
    state.buffer = state.buffer .. name
    return state, nil
  end
  if name == "backspace" and state.field ~= nil then
    state.buffer = string.sub(state.buffer, 1, #state.buffer - 1)
    return state, nil
  end
  if name == "enter" and state.field ~= nil then
    local number = tonumber(state.buffer)
    local field = state.field
    state.field = nil
    state.buffer = ""
    if number == nil then
      return state, nil
    end
    if field == "x" then
      state.waypoint_x = number
      return state, protocol.validate({ type = "set_waypoint", x = number, z = state.waypoint_z })
    end
    if field == "z" then
      state.waypoint_z = number
      return state, protocol.validate({ type = "set_waypoint", x = state.waypoint_x, z = number })
    end
    if field == "y" then
      return state, protocol.validate({ type = "set_altitude", y = number })
    end
    if field == "bearing" then
      return state, protocol.validate({ type = "set_bearing", bearing = number })
    end
    return state, protocol.validate({ type = "set_speed", speed = number })
  end
  return state, nil
end

return M
