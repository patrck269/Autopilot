package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local command_ui = require("command_ui")

local state = command_ui.new()
local msg
state, msg = command_ui.key(state, "right", true)
A.eq(msg.type, "stick", "stick type")
A.eq(msg.x, 1, "forward key is right")
state, msg = command_ui.key(state, "right", false)
A.eq(msg.x, 0, "release")

state, msg = command_ui.key(state, "e", true)
A.eq(msg.type, "emergency", "estop")

state, msg = command_ui.key(state, "y", true)
state, msg = command_ui.key(state, "1", true)
state, msg = command_ui.key(state, "0", true)
state, msg = command_ui.key(state, "enter", true)
A.eq(msg.type, "set_altitude", "altitude")
A.eq(msg.y, 10, "altitude value")

state = command_ui.new()
state, msg = command_ui.key(state, "y", true)
state, msg = command_ui.key(state, "one", true)
state, msg = command_ui.key(state, "zero", true)
state, msg = command_ui.key(state, "enter", true)
A.eq(msg.y, 10, "keyboard number names")

state = command_ui.new()
state, msg = command_ui.key(state, "y", true, false)
state, msg = command_ui.key(state, "one", true, false)
state, msg = command_ui.key(state, "one", true, true)
state, msg = command_ui.key(state, "enter", true, false)
A.eq(msg.type, "set_altitude", "held digit is not another altitude digit")
A.eq(msg.y, 1, "a repeated digit does not change the altitude")
state, msg = command_ui.key(state, "m", true, true)
A.eq(msg, nil, "a repeated mode key is not a second command")

state, msg = command_ui.key(state, "v", true)
state, msg = command_ui.key(state, "minus", true)
state, msg = command_ui.key(state, "numPad5", true)
state, msg = command_ui.key(state, "numPadEnter", true)
A.eq(msg.type, "set_speed", "numpad speed")
A.eq(msg.speed, -5, "numpad value")

local function press_mode(name, mode)
  local ui = command_ui.new()
  local pressed
  ui, pressed = command_ui.key(ui, name, true)
  A.eq(pressed.type, "set_mode", name .. " down")
  A.eq(pressed.mode, mode, name .. " mode")
  A.eq(ui.mode, mode, name .. " stays selected")
  local released
  ui, released = command_ui.key(ui, name, false)
  A.eq(released, nil, name .. " release does not clear")
  A.eq(ui.mode, mode, name .. " still selected")
end

press_mode("m", "manual")
press_mode("s", "semi")
press_mode("u", "auto")

state = command_ui.new()
state, msg = command_ui.key(state, "k", true)
A.eq(msg.type, "cancel_jobs", "cancel jobs")
state, msg = command_ui.key(state, "k", false)
A.eq(msg, nil, "cancel release")

state = command_ui.new()
state, msg = command_ui.key(state, "b", true)
state, msg = command_ui.key(state, "1", true)
state, msg = command_ui.key(state, "8", true)
state, msg = command_ui.key(state, "0", true)
state, msg = command_ui.key(state, "enter", true)
A.eq(msg.type, "set_bearing", "bearing field")
A.near(msg.bearing, -math.pi, 1e-9, "180 degrees is a half turn")
