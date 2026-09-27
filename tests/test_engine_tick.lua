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

local jobs = require("jobs")

local latched, capture = jobs.hold_stop(nil, 8, cfg.ship_mass, 0, false)
local again, capture_again = jobs.hold_stop(capture, 4, cfg.ship_mass, 0, false)
A.eq(again, latched, "held brake ignores the smaller speed")
if again == jobs.brake_rpm(4, cfg.ship_mass) then
  error("held brake recomputed from the new speed")
end
local cleared_rpm, cleared = jobs.hold_stop(capture_again, 0.01, cfg.ship_mass, 0, false)
A.eq(cleared_rpm, 0, "finished horizontal brake is zero")
A.eq(cleared, nil, "finished horizontal brake drops the capture")
local flipped_rpm, flipped = jobs.hold_stop(capture, -1, cfg.ship_mass, 0, false)
A.eq(flipped_rpm, 0, "a speed reversal drops the horizontal brake")
A.eq(flipped, nil, "a speed reversal clears the capture")
local elev_latched, elev_capture = jobs.hold_stop(nil, 4, cfg.ship_mass, 430, true)
local elev_again = jobs.hold_stop(elev_capture, 2, cfg.ship_mass, 430, true)
A.eq(elev_again, elev_latched, "held climb brake ignores the smaller climb")
if elev_again == jobs.elevation_brake_rpm(2, cfg.ship_mass, 430) then
  error("held climb brake recomputed from the new climb")
end
local elev_rest, elev_clear = jobs.hold_stop(elev_capture, 0, cfg.ship_mass, 430, true)
A.eq(elev_rest, 430, "finished climb brake returns to hover")
A.eq(elev_clear, nil, "finished climb brake drops the capture")

local function axis_accel(rpm, mass)
  if rpm == nil or rpm == 0 then
    return 0
  end
  local magnitude = jobs.thrust(rpm, mass) / mass
  if rpm < 0 then
    return -magnitude
  end
  return magnitude
end

local function side_accel(outputs, mass)
  if outputs.rsc.rsc6 > 0 then
    return jobs.thrust(outputs.rsc.rsc6, mass) / mass
  end
  if outputs.rsc.rsc7 > 0 then
    return -(jobs.thrust(outputs.rsc.rsc7, mass) / mass)
  end
  return 0
end

local function coast(pos, vel, accel, dt)
  return pos + vel * dt + 0.5 * accel * dt * dt, vel + accel * dt
end

local function fly_until_rest(state, command)
  local x0, y0, z0 = ship.x, ship.y, ship.z
  local peak_x, peak_y, peak_z = 0, 0, 0
  local outputs
  local fresh = command ~= nil
  for _ = 1, 400 do
    state, outputs = engine_tick.tick(state, {
      ship = ship,
      command = command,
      su = 1,
      ready = true,
      stick_fresh = fresh,
      config = cfg,
      current_elevation_rpm = 430,
    })
    command = nil
    fresh = false
    local ax = axis_accel(outputs.rsc.rsc10, cfg.ship_mass)
    local ay = jobs.thrust(outputs.rsc.rsc11, cfg.ship_mass) / cfg.ship_mass - 10
    local az = side_accel(outputs, cfg.ship_mass)
    ship.x, ship.vx = coast(ship.x, ship.vx, ax, 0.05)
    ship.y, ship.vy = coast(ship.y, ship.vy, ay, 0.05)
    ship.z, ship.vz = coast(ship.z, ship.vz, az, 0.05)
    peak_x = math.max(peak_x, math.abs(ship.x - x0))
    peak_y = math.max(peak_y, math.abs(ship.y - y0))
    peak_z = math.max(peak_z, math.abs(ship.z - z0))
    if math.abs(ship.vx) < 0.05 and math.abs(ship.vy) < 0.05 and math.abs(ship.vz) < 0.05
      and state.brake_x == nil and state.brake_z == nil and state.brake_elev == nil then
      break
    end
  end
  state, outputs = engine_tick.tick(state, {
    ship = ship,
    command = nil,
    su = 1,
    ready = true,
    stick_fresh = false,
    config = cfg,
  })
  return state, outputs, peak_x, peak_y, peak_z
end

local function assert_stopped(label, state, outputs, peak_x, peak_y, peak_z)
  if peak_x > 1 + 1e-6 or peak_y > 1 + 1e-6 or peak_z > 1 + 1e-6 then
    error(label .. " traveled x " .. tostring(peak_x) .. " y " .. tostring(peak_y) .. " z " .. tostring(peak_z))
  end
  A.eq(outputs.rsc.rsc10, 0, label .. " horizontal brake is off")
  A.eq(outputs.rsc.rsc6, 0, label .. " port side is off")
  A.eq(outputs.rsc.rsc7, 0, label .. " starboard side is off")
  A.eq(outputs.relays.relay6, false, label .. " reverser stays off")
  local net = jobs.thrust(outputs.rsc.rsc11, cfg.ship_mass) / cfg.ship_mass - 10
  if math.abs(net) > 1e-6 then
    error(label .. " vertical accel after the stop is " .. tostring(net))
  end
  if state.hover_rpm < 400 then
    error(label .. " stored the brake as the hover rpm " .. tostring(state.hover_rpm))
  end
end

ship.vx = 35
ship.vz = 5
ship.vy = 4
ship.x = 0
ship.y = 180
ship.z = 0
ship.pitch_rate = 0
ship.roll_rate = 0
ship.pitch = 0
state = engine_tick.new_state()
state.mode = "auto"
state.phase = "track"
state.waypoint_x = 800
state.waypoint_z = 900
state, outputs, peak_x, peak_y, peak_z = fly_until_rest(state, { type = "cancel_jobs" })
A.eq(state.job, "hover", "cancel hovers")
A.eq(state.waypoint_x, nil, "cancel clears the waypoint")
assert_stopped("cancel", state, outputs, peak_x, peak_y, peak_z)

ship.vx = 4
ship.vz = 3
ship.vy = 2
ship.x = 0
ship.y = 120
ship.z = 0
state = engine_tick.new_state()
state.mode = "manual"
state, outputs, peak_x, peak_y, peak_z = fly_until_rest(state, nil)
assert_stopped("release", state, outputs, peak_x, peak_y, peak_z)

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
if outputs.rsc.rsc6 < 1000 or outputs.rsc.rsc6 > cfg.max_rpm then
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
if outputs.rsc.rsc2 < 1000 or outputs.rsc.rsc2 > cfg.max_rpm then
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
