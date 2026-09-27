package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local command_status = require("command_status")

local shown = command_status.apply({
  mode = "auto",
  altitude = 400,
  horizontal_speed = 50,
  su = 12,
})
A.eq(shown.mode, "auto", "mode")
A.eq(shown.altitude, 400, "altitude")
A.eq(shown.speed, 50, "speed")
A.eq(shown.su, 12, "su")
A.eq(string.find(shown.line, "auto", 1, true) ~= nil, true, "line mode")
A.eq(string.find(shown.line, "400", 1, true) ~= nil, true, "line altitude")
A.eq(string.find(shown.line, "50", 1, true) ~= nil, true, "line speed")
A.eq(string.find(shown.line, "12", 1, true) ~= nil, true, "line su")
A.eq(command_status.apply({ type = "stick", x = 1, y = 0, z = 0 }), nil, "ignore commands")
