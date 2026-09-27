package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local engine_tick = require("engine_tick")
local config = require("config")

local cfg = config.default()
local ship = {
  y = 100, x = 0, z = 0, vx = 0, vy = 0, vz = 0,
  pitch = 0, roll = 0, heading = 0, pitch_rate = 0, roll_rate = 0, dt = 0.05,
}

local state = engine_tick.new_state()
local blocked, outputs, status = engine_tick.tick(state, {
  ship = ship, command = { type = "set_mode", mode = "manual" },
  su = 10, ready = false, stick_fresh = false, config = cfg,
})
A.eq(blocked.mode, "blocked", "not ready")
A.eq(outputs.rsc.rsc10, 0, "no thrust when blocked")

state = engine_tick.new_state()
state, outputs, status = engine_tick.tick(state, {
  ship = ship,
  command = { type = "stick", x = 1, y = 0, z = 0 },
  su = 12, ready = true, stick_fresh = true, config = cfg,
})
A.eq(state.mode, "manual", "stick selects manual")
A.eq(outputs.rsc.rsc10, cfg.hover_step, "x rpm rises toward the forward target")
A.eq(status.su, 12, "su status")
A.eq(status.mode, "manual", "status mode")

state, outputs = engine_tick.tick(state, {
  ship = ship, command = nil, su = 12, ready = true, stick_fresh = false, config = cfg,
})
A.eq(outputs.rsc.rsc10, 0, "stick timeout")

state = engine_tick.new_state()
state.mode = "manual"
state, outputs = engine_tick.tick(state, {
  ship = ship, command = { type = "emergency" },
  su = 0, ready = true, stick_fresh = true, config = cfg,
})
A.eq(state.emergency, true, "latched")
A.eq(outputs.rsc.rsc11, 0, "estop elevation")

state, outputs = engine_tick.tick(state, {
  ship = ship, command = { type = "stick", x = 1, y = 0, z = 0 },
  su = 0, ready = true, stick_fresh = true, config = cfg,
})
A.eq(outputs.rsc.rsc10, 0, "estop holds")

state, outputs = engine_tick.tick(state, {
  ship = ship, command = { type = "clear_emergency" },
  su = 0, ready = true, stick_fresh = false, config = cfg,
})
A.eq(state.emergency, false, "cleared")

ship.pitch_rate = 0.4
ship.roll_rate = -0.4
state = engine_tick.new_state()
state.mode = "auto"
state.phase = "hold"
state, outputs, status = engine_tick.tick(state, {
  ship = ship, command = nil, su = 1, ready = true, stick_fresh = false, config = cfg,
})
A.eq(outputs.relays.relay9, true, "cut opposite corner")
A.eq(outputs.relays.relay5, false, "master Z stays off")
A.eq(outputs.rsc.rsc2, 64, "live starboard bow")
A.eq(outputs.rsc.rsc5, 64, "live port stern")
A.eq(outputs.rsc.rsc3, 0, "failed corner thruster stays off")
A.eq(status.outage, "port_bow", "outage status")

ship.pitch_rate = 0.05
ship.roll_rate = -0.5
ship.y = 400
ship.vy = 0
state = engine_tick.new_state()
state.mode = "auto"
state.phase = "hold"
state.hover_rpm = 64
state, outputs = engine_tick.tick(state, {
  ship = ship, command = nil, su = 1, ready = true, stick_fresh = false, config = cfg,
})
A.eq(outputs.rsc.rsc3, 64, "port bow thruster replaces lost props")
A.eq(outputs.rsc.rsc5, 64, "port stern thruster replaces lost props")
A.eq(outputs.rsc.rsc11, 32, "live props scaled to 0.5")
A.eq(outputs.relays.relay5, false, "side balance does not cut all")

state.balance_time = 5
state.balance_side = "port"
state, outputs = engine_tick.tick(state, {
  ship = ship, command = nil, su = 1, ready = true, stick_fresh = false, config = cfg,
})
A.eq(outputs.relays.relay5, true, "fail time cuts master Z")
A.eq(outputs.relays.relay7, true, "fail time cuts port bow")
A.eq(outputs.relays.relay8, true, "fail time cuts starboard bow")
A.eq(outputs.relays.relay9, true, "fail time cuts starboard stern")
A.eq(outputs.relays.relay10, true, "fail time cuts port stern")
A.eq(outputs.rsc.rsc2, 0, "up thrust zero")
A.eq(outputs.rsc.rsc11, 0, "elevation zero")

ship.pitch_rate = 0
ship.roll_rate = 0
ship.pitch = 1
ship.vx = 25
ship.y = 400
state = engine_tick.new_state()
state.mode = "auto"
state.phase = "hold"
state.waypoint_x = 0
state.waypoint_z = 0
state, outputs = engine_tick.tick(state, {
  ship = ship, command = nil, su = 1, ready = true, stick_fresh = false, config = cfg,
})
A.eq(outputs.rsc.rsc2, 5, "nose down fires bow starboard")
A.eq(outputs.rsc.rsc3, 5, "nose down fires bow port")

ship.pitch = 0
ship.vx = 0
ship.y = 400
ship.vy = 0
state = engine_tick.new_state()
state.mode = "auto"
state.phase = "descend"
state.waypoint_x = 0
state.waypoint_z = 0
state, outputs = engine_tick.tick(state, {
  ship = ship, command = nil, su = 1, ready = true, stick_fresh = false, config = cfg,
})
A.eq(outputs.relays.relay6, false, "auto descend does not reverse elevation")
if not (outputs.rsc.rsc11 > 0) then
  error("descend rpm: expected positive rsc11 got " .. tostring(outputs.rsc.rsc11))
end

ship.pitch_rate = 0
ship.roll_rate = 0
ship.pitch = 0
ship.vx = 0
ship.vy = 0
ship.y = 100
state = engine_tick.new_state()
state.mode = "auto"
state.phase = "climb"
state.hover_rpm = 400
state, outputs = engine_tick.tick(state, {
  ship = ship, command = nil, su = 1, ready = true, stick_fresh = false, config = cfg,
})
if not (outputs.rsc.rsc11 > 400) then
  error("stuck climb should raise elevation rpm, got " .. tostring(outputs.rsc.rsc11))
end
A.eq(outputs.relays.relay6, false, "stuck climb stays forward")

ship.pitch_rate = 0
ship.roll_rate = 0
ship.pitch = 0
ship.vx = 12
ship.vy = 0
ship.vz = 0
ship.y = 180
ship.x = 10
ship.z = 20
state = engine_tick.new_state()
state.mode = "auto"
state.phase = "track"
state.waypoint_x = 800
state.waypoint_z = 900
state.bearing = 1.2
local kept_mode
state, outputs, status = engine_tick.tick(state, {
  ship = ship,
  command = { type = "set_altitude", y = 250 },
  su = 4,
  ready = true,
  stick_fresh = false,
  config = cfg,
  current_elevation_rpm = 430,
})
kept_mode = state.mode
A.eq(kept_mode, "auto", "altitude does not require a mode change")
A.eq(state.altitude, 250, "new altitude replaces the job")
A.eq(state.job, "altitude", "altitude job")
A.eq(state.waypoint_x, nil, "waypoint cleared")
A.eq(state.waypoint_z, nil, "waypoint z cleared")

state = engine_tick.new_state()
state.mode = "auto"
state.phase = "track"
state.waypoint_x = 800
state.waypoint_z = 900
state.bearing = 1.2
state.rpm_memory[250] = 455
ship.y = 250
ship.vy = 0
ship.vx = 0
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = { type = "set_altitude", y = 250 },
  su = 4,
  ready = true,
  stick_fresh = false,
  config = cfg,
})
A.eq(state.hover_rpm, 455, "remembered rpm is used for that altitude")

ship.vx = 8
ship.vy = 0
ship.y = 180
ship.x = 10
ship.z = 20
state = engine_tick.new_state()
state.mode = "auto"
state.phase = "track"
state.waypoint_x = 800
state.waypoint_z = 900
state, outputs, status = engine_tick.tick(state, {
  ship = ship,
  command = { type = "cancel_jobs" },
  su = 4,
  ready = true,
  stick_fresh = false,
  config = cfg,
  current_elevation_rpm = 430,
})
A.eq(state.job, "hover", "cancel hovers")
A.eq(state.phase, "hold", "cancel holds")
A.eq(state.target_speed, 0, "cancel stops the speed job")
A.eq(state.waypoint_x, nil, "cancel clears the waypoint")
A.eq(state.waypoint_z, nil, "cancel clears waypoint z")
if status.stop_distance > 1 then
  error("stop distance should be within 1 m, got " .. tostring(status.stop_distance))
end
if not (outputs.rsc.rsc10 < 0) then
  error("cancel should command a stop, rsc10 " .. tostring(outputs.rsc.rsc10))
end

ship.vx = 4
ship.vy = 0
ship.y = 120
state = engine_tick.new_state()
state.mode = "manual"
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = nil,
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
  current_elevation_rpm = 430,
})
if not (outputs.rsc.rsc10 < 0) then
  error("released stick should oppose velocity, rsc10 " .. tostring(outputs.rsc.rsc10))
end

ship.vx = 0
ship.vy = 0
ship.y = 120
state = engine_tick.new_state()
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = { type = "stick", x = 0, y = 1, z = 0 },
  su = 1,
  ready = true,
  stick_fresh = true,
  config = cfg,
})
if outputs.rsc.rsc6 < 1000 or outputs.rsc.rsc6 > 100000 then
  error("full sideways command rpm out of range: " .. tostring(outputs.rsc.rsc6))
end

state = engine_tick.new_state()
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = { type = "stick", x = 0, y = 0, z = 1 },
  su = 1,
  ready = true,
  stick_fresh = true,
  config = cfg,
})
if outputs.rsc.rsc2 < 1000 or outputs.rsc.rsc2 > 100000 then
  error("full vertical command rpm out of range: " .. tostring(outputs.rsc.rsc2))
end
A.eq(outputs.relays.relay6, false, "manual vertical does not reverse elevation")

ship.vx = 0
ship.vy = 0
ship.y = 120
state = engine_tick.new_state()
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = nil,
  su = 1,
  ready = false,
  stick_fresh = false,
  config = cfg,
  current_elevation_rpm = 430,
})
A.eq(outputs.rsc.rsc11, 430, "startup keeps the current elevation rpm")
A.eq(outputs.rsc.rsc10, 0, "startup does not add x thrust")
