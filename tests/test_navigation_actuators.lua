package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local engine = require("engine_tick")
local protocol = require("protocol")
local config = require("config")

A.eq(protocol.validate({ type = "set_waypoint", x = 120, z = 80 }), nil, "waypoint is not a semi command")
local state = engine.new_state()
state, _ = engine.tick(state, {
  ship = {
    x = 0, y = 400, z = 0, vx = 0, vy = 0, vz = 0,
    heading = 0, pitch_rate = 0, roll_rate = 0, yaw_rate = 0, dt = 0.05,
  },
  command = { type = "set_waypoint", x = 120, z = 80 },
  config = config.default(),
  ready = true,
  su = 0,
})
A.eq(state.mode, "semi", "a waypoint does not leave semi")
A.eq(state.waypoint_x, nil, "a waypoint does not start navigation")
print("waypoint navigation is not a semi feature")
