local protocol = require("protocol")
local numeric = require("numeric")

local M = {}

function M.new()
  return {
    stick = { x = 0, y = 0, z = 0 },
    pressed = {},
    press_order = 0,
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

function M.key(state, name, down, held)
  local axes = {
    right = { "x", 1 }, left = { "x", -1 },
    d = { "y", 1 }, a = { "y", -1 },
    space = { "z", 1 }, up = { "z", 1 },
    leftShift = { "z", -1 }, down = { "z", -1 },
  }
  local axis = axes[name]
  if axis then
    if down then
      state.press_order = state.press_order + 1
      state.pressed[name] = state.press_order
    else
      state.pressed[name] = nil
    end
    local newest, value = 0, 0
    for key, order in pairs(state.pressed) do
      if axes[key] and axes[key][1] == axis[1] and order > newest then
        newest, value = order, axes[key][2]
      end
    end
    state.stick[axis[1]] = value
    return state, stick_msg(state)
  end
  if held then
    return state, nil
  end
  if not down then
    return state, nil
  end
  if name == "m" or name == "s" or name == "u" or name == "k" or name == "e" then
    state.stick = { x = 0, y = 0, z = 0 }
    state.pressed = {}
  end
  if name == "m" then
    state.mode = "manual"
    return state, protocol.validate({ type = "set_mode", mode = "manual" })
  end
  if name == "s" then
    state.mode = "semi"
    return state, protocol.validate({ type = "set_mode", mode = "semi" })
  end
  if name == "u" then
    state.mode = "auto"
    return state, protocol.validate({ type = "set_mode", mode = "auto" })
  end
  if name == "k" then
    state.entered_altitude = nil
    return state, protocol.validate({ type = "cancel_jobs" })
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
  local typed = ({
    one = "1", two = "2", three = "3", four = "4", five = "5",
    six = "6", seven = "7", eight = "8", nine = "9", zero = "0",
    numPad1 = "1", numPad2 = "2", numPad3 = "3", numPad4 = "4", numPad5 = "5",
    numPad6 = "6", numPad7 = "7", numPad8 = "8", numPad9 = "9", numPad0 = "0",
    minus = "-", numPadSubtract = "-",
    period = ".", numPadDecimal = ".",
  })[name]
  if typed == nil and (name == "-" or name == "." or (type(name) == "string" and #name == 1 and name >= "0" and name <= "9")) then
    typed = name
  end
  if state.field ~= nil and typed ~= nil then
    if #state.buffer < 32 then
      state.buffer = state.buffer .. typed
    end
    return state, nil
  end
  if name == "backspace" and state.field ~= nil then
    state.buffer = string.sub(state.buffer, 1, #state.buffer - 1)
    return state, nil
  end
  if (name == "enter" or name == "numPadEnter") and state.field ~= nil then
    local number = tonumber(state.buffer)
    local field = state.field
    state.field = nil
    state.buffer = ""
    if not numeric.finite(number) then
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
      state.entered_altitude = number
      return state, protocol.validate({ type = "set_altitude", y = number })
    end
    if field == "bearing" then
      local degrees = number % 360
      if degrees < 0 then
        degrees = degrees + 360
      end
      return state, protocol.validate({ type = "set_bearing", bearing = degrees * math.pi / 180 })
    end
    return state, protocol.validate({ type = "set_speed", speed = number })
  end
  return state, nil
end

function M.repeat_stick(state)
  if state.stick.x ~= 0 or state.stick.y ~= 0 or state.stick.z ~= 0 then
    return stick_msg(state)
  end
end

return M
