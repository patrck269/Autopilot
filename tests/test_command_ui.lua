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
