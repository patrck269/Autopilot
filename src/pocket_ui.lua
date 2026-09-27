local protocol = require("protocol")

local M = {}

local ROOT = {
  { id = "manual", x = 1, y = 8, w = 8, h = 2 },
  { id = "semi", x = 9, y = 8, w = 8, h = 2 },
  { id = "auto", x = 17, y = 8, w = 10, h = 2 },
  { id = "forward", x = 11, y = 11, w = 4, h = 1 },
  { id = "back", x = 11, y = 13, w = 4, h = 1 },
  { id = "port", x = 6, y = 12, w = 4, h = 1 },
  { id = "starboard", x = 16, y = 12, w = 4, h = 1 },
  { id = "up", x = 21, y = 11, w = 5, h = 1 },
  { id = "down", x = 21, y = 13, w = 5, h = 1 },
  { id = "return", x = 1, y = 15, w = 12, h = 2 },
  { id = "diagnostic", x = 14, y = 15, w = 12, h = 2 },
  { id = "emergency", x = 1, y = 18, w = 12, h = 2 },
  { id = "clear", x = 14, y = 18, w = 12, h = 2 },
}

local function inside(button, x, y)
  return x >= button.x and x < button.x + button.w and y >= button.y and y < button.y + button.h
end

local function find(buttons, x, y)
  for _, button in ipairs(buttons) do
    if inside(button, x, y) then
      return button.id
    end
  end
  return nil
end

function M.new()
  return {
    screen = "root",
    gps_error = false,
    device = "rsc2",
    rpm = 0,
    elevation = 0,
    hover = false,
    diag_open = false,
  }
end

local function stick(x, y, z)
  return protocol.validate({ type = "stick", x = x, y = y, z = z })
end

function M.touch(state, x, y, ctx)
  if state.screen == "diagnostic" then
    local id = find({
      { id = "device", x = 1, y = 1, w = 8, h = 1 },
      { id = "plus", x = 10, y = 1, w = 3, h = 1 },
      { id = "minus", x = 14, y = 1, w = 3, h = 1 },
      { id = "hover", x = 1, y = 3, w = 12, h = 1 },
      { id = "elev", x = 1, y = 4, w = 8, h = 1 },
    }, x, y)
    if id == "plus" then
      state.rpm = state.rpm + 1
      return state, protocol.validate({ type = "diagnostic_set", device = state.device, rpm = state.rpm })
    end
    if id == "minus" then
      state.rpm = state.rpm - 1
      return state, protocol.validate({ type = "diagnostic_set", device = state.device, rpm = state.rpm })
    end
    if id == "hover" then
      state.hover = true
      return state, protocol.validate({ type = "diagnostic_enter", hover = true })
    end
    if id == "elev" then
      state.elevation = state.elevation + 1
      return state, protocol.validate({ type = "diagnostic_elevation", rpm = state.elevation })
    end
    if id == "device" and not state.diag_open then
      state.diag_open = true
      return state, protocol.validate({ type = "diagnostic_enter", hover = false })
    end
    return state, nil
  end

  local id = find(ROOT, x, y)
  if id == "forward" then
    return state, stick(1, 0, 0)
  end
  if id == "back" then
    return state, stick(-1, 0, 0)
  end
  if id == "starboard" then
    return state, stick(0, 1, 0)
  end
  if id == "port" then
    return state, stick(0, -1, 0)
  end
  if id == "up" then
    return state, stick(0, 0, 1)
  end
  if id == "down" then
    return state, stick(0, 0, -1)
  end
  if id == "manual" or id == "semi" or id == "auto" then
    return state, protocol.validate({ type = "set_mode", mode = id })
  end
  if id == "emergency" then
    return state, protocol.validate({ type = "emergency" })
  end
  if id == "clear" then
    return state, protocol.validate({ type = "clear_emergency" })
  end
  if id == "return" then
    local gx, gz = ctx.locate()
    if gx == nil then
      state.gps_error = true
      return state, nil
    end
    state.gps_error = false
    return state, protocol.validate({ type = "return_to_user", x = gx, z = gz })
  end
  if id == "diagnostic" then
    state.screen = "diagnostic"
    state.diag_open = true
    return state, protocol.validate({ type = "diagnostic_enter", hover = false })
  end
  return state, nil
end

return M
