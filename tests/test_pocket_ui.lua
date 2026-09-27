package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local pocket_ui = require("pocket_ui")

local state = pocket_ui.new()
local msg
state, msg = pocket_ui.touch(state, 12, 11, {})
A.eq(msg.type, "stick", "forward")
A.eq(msg.x, 1, "forward axis")

state, msg = pocket_ui.touch(state, 2, 15, { locate = function() return nil end })
A.eq(msg, nil, "no fix")
A.eq(state.gps_error, true, "gps error")

state, msg = pocket_ui.touch(state, 2, 15, { locate = function() return 4, 5 end })
A.eq(msg.type, "return_to_user", "return")
A.eq(msg.x, 4, "return x")
A.eq(msg.z, 5, "return z")

state, msg = pocket_ui.touch(state, 15, 15, {})
A.eq(msg.type, "diagnostic_enter", "enter diag")
state, msg = pocket_ui.touch(state, 11, 1, {})
A.eq(msg.rpm, 1, "plus")
A.eq(msg.device, "rsc2", "device")
