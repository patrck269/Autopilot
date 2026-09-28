package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local engine_tick = require("engine_tick")
local config = require("config")
local pid = require("pid")
local stress = require("stress")

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
local held_rpm = pid.command(pid.calibrate(cfg.hover_equilibrium, 0.05), 0, ship.y, 400, ship.vy, ship.dt)
A.near(outputs.rsc.rsc11, held_rpm * 0.5, 1e-4, "live props scaled to 0.5")
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
state.rpm_memory = { [250] = 455 }
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
if state.hover_rpm == 455 or outputs.rsc.rsc11 == 455 then
  error("altitude hold reused a remembered rpm")
end

local jobs = require("jobs")
local hover = require("hover")

local function elevation_accel(rpm, reverser)
  local specific = jobs.thrust(rpm, cfg.ship_mass) / cfg.ship_mass
  local reference = pid.air_density(pid.reference_y())
  local here = pid.air_density(ship.y)
  if reference > 0 then
    specific = specific * (here / reference)
  end
  if reverser then
    return -(specific + 10)
  end
  return specific - 10
end

ship.y = 450
ship.vy = 0
ship.vx = 0
ship.vz = 0
ship.x = 0
ship.z = 0
ship.pitch = 0
ship.roll = 0
ship.heading = 0
ship.pitch_rate = 0
ship.roll_rate = 0
ship.dt = 0.05
state = engine_tick.new_state()
state.mode = "manual"
state.phase = "track"
state.waypoint_x = 800
state.waypoint_z = 900
state.bearing = 1.2
state.hover_rpm = 430
local descent_floor = ship.y
local descent_ceiling = pid.command(pid.calibrate(cfg.hover_equilibrium, 0.05), 0, ship.y, ship.y, 0, 0.05)
local descent_rpm = descent_ceiling
local reverser_on = false
local inside = false
local function descend_step(command)
  local stepped
  state, stepped = engine_tick.tick(state, {
    ship = ship,
    command = command,
    su = 1,
    ready = true,
    stick_fresh = false,
    config = cfg,
    current_elevation_rpm = 430,
  })
  if stepped.relays.relay6 == true then
    reverser_on = true
  end
  if stepped.rsc.rsc11 < descent_rpm then
    descent_rpm = stepped.rsc.rsc11
  end
  local net = elevation_accel(stepped.rsc.rsc11, stepped.relays.relay6 == true)
  ship.y = ship.y + ship.vy * 0.05 + 0.5 * net * 0.0025
  ship.vy = ship.vy + net * 0.05
  if ship.y < descent_floor then
    descent_floor = ship.y
  end
  if ship.y <= 408 and ship.y >= 392 then
    inside = true
  end
  return stepped
end
descend_step({ type = "set_altitude", y = 400 })
A.eq(state.mode, "manual", "altitude from above does not change mode")
A.eq(state.job, "altitude", "altitude from above replaces the waypoint")
A.eq(state.altitude, 400, "altitude from above is the new target")
A.eq(state.waypoint_x, nil, "altitude from above clears the waypoint")
A.eq(state.waypoint_z, nil, "altitude from above clears the waypoint z")
for _ = 1, 399 do
  descend_step(nil)
end
A.eq(state.mode, "manual", "released stick keeps the altitude mode")
A.eq(state.job, "altitude", "released stick keeps the altitude job")
A.eq(state.brake_elev, nil, "released stick does not latch the elevation brake")
A.eq(reverser_on, false, "altitude descent keeps the reverser off")
if descent_rpm >= descent_ceiling then
  error("altitude descent did not lower elevation rpm, got " .. tostring(descent_rpm))
end
if not inside then
  error("altitude descent missed the deadzone, y " .. tostring(ship.y))
end
if descent_floor < 392 then
  error("altitude descent crossed the far side at " .. tostring(descent_floor))
end

ship.y = 400
ship.vy = 0
state = engine_tick.new_state()
state.mode = "manual"
state.job = "altitude"
state.altitude = 400
state.altitude_set = true
state.hover_rpm = 430
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = nil,
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
  current_elevation_rpm = 430,
})
local density_hover = pid.command(pid.calibrate(cfg.hover_equilibrium, 0.05), 0, ship.y, ship.y, 0, ship.dt)
A.near(outputs.rsc.rsc11, density_hover, 1e-3, "steady altitude holds the density hover")
A.eq(outputs.relays.relay6, false, "steady altitude keeps the reverser off")
local calibrated = pid.calibrate(cfg.hover_equilibrium, 0.05)
A.eq(state.pid_gains.kp, calibrated.kp, "hold uses the calibrated kp")
A.eq(state.pid_gains.ki, calibrated.ki, "hold uses the calibrated ki")
A.eq(state.pid_gains.kd, calibrated.kd, "hold uses the calibrated kd")

state.rpm_memory = { [400] = 900 }
state.hover_rpm = 100
ship.y = 180
ship.vy = 0
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = { type = "set_altitude", y = 400 },
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
})
if state.hover_rpm == 900 or outputs.rsc.rsc11 == 900 then
  error("a new altitude restored a stored rpm")
end
A.eq(state.altitude, 400, "new altitude is applied")
if math.abs(outputs.rsc.rsc11 - 430) < 5 then
  error("altitude hold left the hover rpm in place, got " .. tostring(outputs.rsc.rsc11))
end

local function fly_band(start_y, target, steps, label)
  ship.x = 0
  ship.y = start_y
  ship.z = 0
  ship.vx = 0
  ship.vy = 0
  ship.vz = 0
  ship.heading = 0
  ship.pitch = 0
  ship.roll = 0
  ship.pitch_rate = 0
  ship.roll_rate = 0
  ship.dt = 0.05
  state = engine_tick.new_state()
  state.mode = "manual"
  local moved = false
  local entered = false
  local gains = pid.calibrate(cfg.hover_equilibrium, 0.05)
  for i = 1, steps do
    local command = nil
    if i == 1 then
      command = { type = "set_altitude", y = target }
    end
    local stepped
    state, stepped = engine_tick.tick(state, {
      ship = ship,
      command = command,
      su = 1,
      ready = true,
      stick_fresh = false,
      config = cfg,
      current_elevation_rpm = 430,
    })
    if math.abs(stepped.rsc.rsc11 - cfg.hover_equilibrium) > 5 then
      moved = true
    end
    local net = elevation_accel(stepped.rsc.rsc11, stepped.relays.relay6 == true)
    ship.y = ship.y + ship.vy * 0.05 + 0.5 * net * 0.0025
    ship.vy = ship.vy + net * 0.05
    local inside = ship.y >= target - cfg.altitude_deadzone and ship.y <= target + cfg.altitude_deadzone
    if inside then
      entered = true
    elseif entered then
      error(label .. " left the deadzone at " .. tostring(ship.y))
    end
  end
  if not moved then
    error(label .. " never moved elevation rpm off hover")
  end
  if not entered then
    error(label .. " never entered the deadzone, y " .. tostring(ship.y))
  end
  if ship.y < target - cfg.altitude_deadzone or ship.y > target + cfg.altitude_deadzone then
    error(label .. " finished outside the band at " .. tostring(ship.y))
  end
  A.eq(state.pid_gains.kp, gains.kp, label .. " uses calibrated kp")
  A.eq(state.pid_gains.ki, gains.ki, label .. " uses calibrated ki")
  A.eq(state.pid_gains.kd, gains.kd, label .. " uses calibrated kd")
end
fly_band(100, 400, 4000, "climb")
fly_band(450, 400, 800, "descent")

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
if flipped_rpm == 0 then
  error("a reversal must not coast at rest rpm while speed remains")
end
A.eq(flipped, nil, "a speed reversal clears the old capture")
local reverse_accel = jobs.thrust(flipped_rpm, cfg.ship_mass) / cfg.ship_mass
if math.abs(1 - reverse_accel * 0.05) > 1e-6 then
  error("a reversal must be gone after one step, leftover " .. tostring(1 - reverse_accel * 0.05))
end
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
  local min_vx, max_vx = ship.vx, ship.vx
  local min_vy = ship.vy
  local reverser_steps = 0
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
    local ay = elevation_accel(outputs.rsc.rsc11, outputs.relays.relay6 == true)
    local az = side_accel(outputs, cfg.ship_mass)
    ship.x, ship.vx = coast(ship.x, ship.vx, ax, 0.05)
    ship.y, ship.vy = coast(ship.y, ship.vy, ay, 0.05)
    ship.z, ship.vz = coast(ship.z, ship.vz, az, 0.05)
    peak_x = math.max(peak_x, math.abs(ship.x - x0))
    peak_y = math.max(peak_y, math.abs(ship.y - y0))
    peak_z = math.max(peak_z, math.abs(ship.z - z0))
    if outputs.relays.relay6 == true then
      reverser_steps = reverser_steps + 1
    end
    if ship.vx < min_vx then
      min_vx = ship.vx
    end
    if ship.vx > max_vx then
      max_vx = ship.vx
    end
    if ship.vy < min_vy then
      min_vy = ship.vy
    end
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
  return state, outputs, peak_x, peak_y, peak_z, min_vx, max_vx, min_vy, reverser_steps
end

local function assert_stopped(label, state, outputs, peak_x, peak_y, peak_z)
  if peak_x > 1 + 1e-6 or peak_y > 1 + 1e-6 or peak_z > 1 + 1e-6 then
    error(label .. " traveled x " .. tostring(peak_x) .. " y " .. tostring(peak_y) .. " z " .. tostring(peak_z))
  end
  A.eq(outputs.rsc.rsc10, 0, label .. " horizontal brake is off")
  A.eq(outputs.rsc.rsc6, 0, label .. " port side is off")
  A.eq(outputs.rsc.rsc7, 0, label .. " starboard side is off")
  A.eq(outputs.relays.relay6, false, label .. " reverser stays off")
  local net = elevation_accel(outputs.rsc.rsc11, outputs.relays.relay6 == true)
  if math.abs(net) > 1e-6 then
    error(label .. " vertical accel after the stop is " .. tostring(net))
  end
  if state.hover_rpm < 400 then
    error(label .. " stored the brake as the hover rpm " .. tostring(state.hover_rpm))
  end
end

ship.vx = 0
ship.vz = 0
ship.vy = 0
ship.x = 0
ship.y = 62
ship.z = 0
ship.pitch_rate = 0
ship.roll_rate = 0
ship.pitch = 0
state = engine_tick.new_state()
local function semi_step(command)
  local stepped
  state, stepped = engine_tick.tick(state, {
    ship = ship,
    command = command,
    su = 1,
    ready = true,
    stick_fresh = false,
    config = cfg,
    current_elevation_rpm = 430,
  })
  local accel = axis_accel(stepped.rsc.rsc10, cfg.ship_mass)
  ship.x, ship.vx = coast(ship.x, ship.vx, accel, 0.05)
  local lift = elevation_accel(stepped.rsc.rsc11, stepped.relays.relay6 == true)
  ship.y, ship.vy = coast(ship.y, ship.vy, lift, 0.05)
  local side = side_accel(stepped, cfg.ship_mass)
  ship.z, ship.vz = coast(ship.z, ship.vz, side, 0.05)
end
semi_step({ type = "set_mode", mode = "semi" })
semi_step({ type = "set_speed", speed = 80 })
local spun = 0
while ship.vx < 35 and spun < 20000 do
  semi_step(nil)
  spun = spun + 1
end
if ship.vx < 35 then
  error("semi-automatic did not reach the 35 m/s cap, vx " .. tostring(ship.vx))
end
local before_cancel
state, before_cancel = engine_tick.tick(state, {
  ship = ship,
  command = nil,
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
  current_elevation_rpm = 430,
})
local speed_altitude = state.altitude
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = { type = "cancel_jobs" },
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
  current_elevation_rpm = 430,
})
A.eq(state.job, nil, "cancel clears the speed job")
A.eq(state.mode, "idle", "cancel does not start a hover mode")
A.eq(state.altitude_set, false, "cancel does not latch an altitude")
A.eq(state.altitude, speed_altitude, "cancel does not aim at a new altitude")
A.eq(state.waypoint_x, nil, "cancel clears the waypoint")
A.eq(state.target_speed, 0, "cancel clears the speed")
A.eq(outputs.rsc.rsc10, 0, "cancel drops the speed command")
A.eq(outputs.relays.relay6, false, "cancel does not reverse elevation")
A.near(outputs.rsc.rsc11, before_cancel.rsc.rsc11, 1e-6, "cancel leaves the elevation throttle alone")

ship.vx = 0
ship.vz = 0
ship.vy = 0
ship.x = 0
ship.y = 100
ship.z = 0
ship.pitch = 0
ship.roll = 0
ship.heading = 0
ship.pitch_rate = 0
ship.roll_rate = 0
ship.dt = 0.05
state = engine_tick.new_state()
local function climb_step(command)
  local stepped
  state, stepped = engine_tick.tick(state, {
    ship = ship,
    command = command,
    su = 1,
    ready = true,
    stick_fresh = false,
    config = cfg,
    current_elevation_rpm = 430,
  })
  if stepped.relays.relay6 == true then
    error("climb turned the elevation reverser on")
  end
  local accel = axis_accel(stepped.rsc.rsc10, cfg.ship_mass)
  ship.x, ship.vx = coast(ship.x, ship.vx, accel, 0.05)
  local lift = elevation_accel(stepped.rsc.rsc11, stepped.relays.relay6 == true)
  ship.y, ship.vy = coast(ship.y, ship.vy, lift, 0.05)
  local side = side_accel(stepped, cfg.ship_mass)
  ship.z, ship.vz = coast(ship.z, ship.vz, side, 0.05)
end
local shell = pid.calibrate(cfg.hover_equilibrium, 0.05).max_rate * 0.9
climb_step({ type = "set_altitude", y = 400 })
A.eq(state.mode, "idle", "altitude climb does not change mode")
A.eq(state.job, "altitude", "altitude climb is the active job")
local climbed = 0
while ship.vy < shell and climbed < 20000 do
  climb_step(nil)
  climbed = climbed + 1
end
if ship.vy < shell then
  error("climb did not reach the shell rate, vy " .. tostring(ship.vy))
end
local climbing
state, climbing = engine_tick.tick(state, {
  ship = ship,
  command = nil,
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
  current_elevation_rpm = 430,
})
local climb_altitude = state.altitude
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = { type = "cancel_jobs" },
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
  current_elevation_rpm = 430,
})
A.eq(state.job, nil, "climb cancel clears the altitude job")
A.eq(state.mode, "idle", "climb cancel does not start a hover")
A.eq(state.altitude_set, false, "climb cancel does not latch the ship altitude")
A.eq(state.altitude, climb_altitude, "climb cancel keeps the old number without chasing it")
A.eq(outputs.relays.relay6, false, "climb cancel does not reverse elevation")
A.near(outputs.rsc.rsc11, climbing.rsc.rsc11, 1e-6, "climb cancel does not retarget elevation")

ship.vx = 4
ship.vz = 3
ship.vy = 2
ship.x = 0
ship.y = 120
ship.z = 0
state = engine_tick.new_state()
state.mode = "manual"
state, outputs, peak_x, peak_y, peak_z, min_vx, max_vx = fly_until_rest(state, nil)
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
  current_elevation_rpm = 430,
})
if outputs.rsc.rsc6 < 1000 or outputs.rsc.rsc6 > cfg.max_rpm then
  error("full sideways command rpm out of range: " .. tostring(outputs.rsc.rsc6))
end
if outputs.rsc.rsc11 < 400 then
  error("sideways command cut the elevation props: " .. tostring(outputs.rsc.rsc11))
end

state = engine_tick.new_state()
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = { type = "stick", x = 0, y = 0, z = 1 },
  su = 1,
  ready = true,
  stick_fresh = true,
  config = cfg,
  current_elevation_rpm = 430,
})
if outputs.rsc.rsc2 < 1000 or outputs.rsc.rsc2 > cfg.max_rpm then
  error("full vertical command rpm out of range: " .. tostring(outputs.rsc.rsc2))
end
if outputs.rsc.rsc11 <= cfg.hover_equilibrium then
  error("manual up did not raise elevation rpm: " .. tostring(outputs.rsc.rsc11))
end
A.eq(outputs.relays.relay6, false, "manual vertical does not reverse elevation")
local up_su = stress.consumed(outputs)
if up_su > stress.USABLE then
  error("manual up exceeds usable SU: " .. tostring(up_su))
end
if outputs.rsc.rsc2 < 1000 then
  error("manual up left the thrusters too slow to move the ship: " .. tostring(outputs.rsc.rsc2))
end

ship.vy = 0
ship.y = 120
state = engine_tick.new_state()
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = { type = "stick", x = 0, y = 0, z = 1 },
  su = 0,
  su_capacity = 200000,
  ready = true,
  stick_fresh = true,
  config = cfg,
  current_elevation_rpm = 430,
})
local z_room = 200000 * stress.USABLE / stress.CAPACITY
local z_su = stress.consumed(outputs)
if z_su > z_room + 1 then
  error("z thrusters called for more SU than available: " .. tostring(z_su))
end
if outputs.rsc.rsc2 <= 0 or outputs.rsc.rsc3 <= 0 or outputs.rsc.rsc4 <= 0 or outputs.rsc.rsc5 <= 0 then
  error("z thrusters were shut off to satisfy the stress limit")
end
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = { type = "stick", x = 0, y = 0, z = 1 },
  su = z_su,
  su_capacity = 200000,
  ready = true,
  stick_fresh = true,
  config = cfg,
  current_elevation_rpm = 430,
})
z_su = stress.consumed(outputs)
if z_su > z_room + 1 then
  error("z thrusters still called for more SU than available: " .. tostring(z_su))
end

ship.vy = 0
ship.y = 62
state = engine_tick.new_state()
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = { type = "stick", x = 0, y = 1, z = 1 },
  su = 1,
  ready = true,
  stick_fresh = true,
  config = cfg,
  current_elevation_rpm = 430,
})
local both_su = stress.consumed(outputs)
if both_su > stress.USABLE then
  error("manual up and sideways exceed usable SU: " .. tostring(both_su))
end
if outputs.rsc.rsc11 < 400 then
  error("su limit cut the elevation props: " .. tostring(outputs.rsc.rsc11))
end

ship.heading = 0
ship.vy = 0
ship.y = 120
state = engine_tick.new_state()
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = { type = "set_bearing", bearing = math.pi },
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
  current_elevation_rpm = 430,
})
if outputs.rsc.rsc6 < 1000 or outputs.rsc.rsc6 > cfg.max_rpm then
  error("bearing rcs out of range: " .. tostring(outputs.rsc.rsc6))
end
if outputs.rsc.rsc7 < 1000 or outputs.rsc.rsc7 > cfg.max_rpm then
  error("bearing rcs pair out of range: " .. tostring(outputs.rsc.rsc7))
end
if outputs.rsc.rsc11 < 400 then
  error("bearing command cut the elevation props: " .. tostring(outputs.rsc.rsc11))
end
local plus = jobs.thrust(outputs.rsc.rsc6, cfg.ship_mass) + jobs.thrust(outputs.rsc.rsc7, cfg.ship_mass)
local minus = jobs.thrust(outputs.rsc.rsc8, cfg.ship_mass) + jobs.thrust(outputs.rsc.rsc9, cfg.ship_mass)
local alpha = (plus - minus) * 8 / (cfg.ship_mass * 400)
local turned = 0.5 * alpha * 0.05 * 0.05
if turned <= 0 then
  error("heading did not turn toward the bearing")
end

local function assert_bearing_rcs(label, prior)
  ship.heading = 0
  ship.vy = 0
  ship.vz = 0
  ship.vx = 0
  ship.y = 120
  state, outputs = engine_tick.tick(prior, {
    ship = ship,
    command = { type = "set_bearing", bearing = math.pi },
    su = 1,
    ready = true,
    stick_fresh = false,
    config = cfg,
    current_elevation_rpm = 430,
  })
  if outputs.rsc.rsc6 < 1000 or outputs.rsc.rsc6 > cfg.max_rpm then
    error(label .. " bearing rcs out of range: " .. tostring(outputs.rsc.rsc6))
  end
  if outputs.rsc.rsc7 < 1000 or outputs.rsc.rsc7 > cfg.max_rpm then
    error(label .. " bearing rcs pair out of range: " .. tostring(outputs.rsc.rsc7))
  end
end

local manual_only = engine_tick.new_state()
manual_only.mode = "manual"
assert_bearing_rcs("manual", manual_only)

local after_hold = engine_tick.new_state()
after_hold.mode = "manual"
engine_tick.tick(after_hold, {
  ship = ship,
  command = { type = "set_altitude", y = 120 },
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
  current_elevation_rpm = 430,
})
assert_bearing_rcs("after altitude hold", after_hold)

local hovering = engine_tick.new_state()
hovering.job = "hover"
hovering.mode = "semi"
assert_bearing_rcs("hover", hovering)

local function hover_brake(heading)
  local braking = engine_tick.new_state()
  braking.job = "hover"
  braking.mode = "semi"
  ship.heading = heading
  ship.bearing = 0
  ship.vx = 0
  ship.vy = 0
  ship.vz = 4
  ship.y = 120
  local _
  braking, outputs = engine_tick.tick(braking, {
    ship = ship,
    command = { type = "set_bearing", bearing = 0 },
    su = 1,
    ready = true,
    stick_fresh = false,
    config = cfg,
    current_elevation_rpm = 430,
  })
  return outputs
end
local exact_brake = hover_brake(0)
local near_brake = hover_brake(0.01)
if exact_brake.rsc.rsc7 == 0 or exact_brake.rsc.rsc7 ~= exact_brake.rsc.rsc9 then
  error("exact heading did not brake both sides: " .. tostring(exact_brake.rsc.rsc7) .. " " .. tostring(exact_brake.rsc.rsc9))
end
A.eq(near_brake.rsc.rsc7, exact_brake.rsc.rsc7, "a tiny heading error keeps the brake pair")
A.eq(near_brake.rsc.rsc9, exact_brake.rsc.rsc9, "a tiny heading error keeps the other brake thruster")

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

local density_gains = pid.calibrate(cfg.hover_equilibrium, 0.05)
local function density_hold(world_y)
  return pid.command(density_gains, 0, world_y, world_y, 0, 0.05)
end
local function tick_hold(world_y)
  ship.y = world_y
  ship.vy = 0
  ship.vx = 0
  ship.vz = 0
  ship.heading = 0
  ship.dt = 0.05
  local holding = engine_tick.new_state()
  holding.mode = "manual"
  holding.job = "altitude"
  holding.altitude = world_y
  holding.altitude_set = true
  holding.pid_integral = 80
  local stepped
  holding, stepped = engine_tick.tick(holding, {
    ship = ship,
    command = nil,
    su = 1,
    ready = true,
    stick_fresh = false,
    config = cfg,
    current_elevation_rpm = cfg.hover_equilibrium,
  })
  return stepped.rsc.rsc11, holding
end
local low_rpm = tick_hold(62)
local below_sea = tick_hold(0)
local mid_rpm = tick_hold(100)
local high_rpm, high_state = tick_hold(1000)
A.near(low_rpm, cfg.hover_equilibrium, 1e-3, "hover rpm at sea level is the equilibrium")
A.near(below_sea, cfg.hover_equilibrium, 1e-3, "hover rpm below sea level is the equilibrium")
A.near(low_rpm, density_hold(62), 1e-3, "engine tick uses the density command")
if not (low_rpm < mid_rpm and mid_rpm < high_rpm) then
  error("elevation rpm did not rise with altitude: " .. tostring(low_rpm) .. " " .. tostring(mid_rpm) .. " " .. tostring(high_rpm))
end
if high_rpm < 25000 or high_rpm > 27000 then
  error("y=1000 hover is outside 25000-27000 for equilibrium 430: " .. tostring(high_rpm))
end
if high_rpm > cfg.max_rpm then
  error("y=1000 hover exceeded the rpm cap: " .. tostring(high_rpm))
end
A.near(high_rpm, density_hold(1000), 1e-2, "y=1000 hover is the density scale, not the integral")
ship.y = 1000
ship.vy = 0
local again
high_state, again = engine_tick.tick(high_state, {
  ship = ship,
  command = nil,
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
})
A.near(again.rsc.rsc11, high_rpm, 1e-2, "a second tick at y=1000 does not ratchet")
A.eq(high_state.pid_gains.equilibrium, cfg.hover_equilibrium, "density rpm is not stored as the equilibrium")

local function settle_then(next_altitude, label)
  ship.x = 0
  ship.y = 100
  ship.z = 0
  ship.vx = 0
  ship.vy = 0
  ship.vz = 0
  ship.heading = 0
  ship.dt = 0.05
  state = engine_tick.new_state()
  state.mode = "manual"
  local target = 400
  for _ = 1, 6000 do
    local command = nil
    if state.job ~= "altitude" then
      command = { type = "set_altitude", y = target }
    end
    local stepped
    state, stepped = engine_tick.tick(state, {
      ship = ship,
      command = command,
      su = 1,
      ready = true,
      stick_fresh = false,
      config = cfg,
      current_elevation_rpm = cfg.hover_equilibrium,
    })
    local net = elevation_accel(stepped.rsc.rsc11, stepped.relays.relay6 == true)
    ship.y = ship.y + ship.vy * 0.05 + 0.5 * net * 0.0025
    ship.vy = ship.vy + net * 0.05
    if math.abs(ship.y - target) <= 0.5 and math.abs(ship.vy) < 0.05 then
      break
    end
  end
  if math.abs(ship.y - target) > 0.5 or math.abs(ship.vy) >= 0.05 then
    error(label .. " did not settle, y " .. tostring(ship.y) .. " vy " .. tostring(ship.vy))
  end
  local settled_rpm
  state, outputs = engine_tick.tick(state, {
    ship = ship,
    command = nil,
    su = 1,
    ready = true,
    stick_fresh = false,
    config = cfg,
  })
  settled_rpm = outputs.rsc.rsc11
  local hover_rpm = density_hold(ship.y)
  if math.abs(settled_rpm - hover_rpm) / hover_rpm > 0.02 then
    error(label .. " kept climbing after arrival, rpm " .. tostring(settled_rpm) .. " hover " .. tostring(hover_rpm))
  end
  state, outputs = engine_tick.tick(state, {
    ship = ship,
    command = { type = "set_altitude", y = next_altitude },
    su = 1,
    ready = true,
    stick_fresh = false,
    config = cfg,
  })
  A.eq(state.altitude, next_altitude, label .. " stores the new altitude")
  if next_altitude > target and outputs.rsc.rsc11 <= settled_rpm then
    error(label .. " did not climb toward the new altitude, rpm " .. tostring(outputs.rsc.rsc11))
  end
  if next_altitude < target and outputs.rsc.rsc11 >= settled_rpm then
    error(label .. " did not descend toward the new altitude, rpm " .. tostring(outputs.rsc.rsc11))
  end
end
settle_then(500, "higher altitude")
settle_then(300, "lower altitude")

local protocol = require("protocol")
local command_ui = require("command_ui")

local function fresh_ship(y, vy)
  ship.x = 0
  ship.y = y
  ship.z = 0
  ship.vx = 0
  ship.vy = vy or 0
  ship.vz = 0
  ship.pitch = 0
  ship.roll = 0
  ship.heading = 0.4
  ship.pitch_rate = 0
  ship.roll_rate = 0
  ship.dt = 0.05
end

local function step_ship(state, command, ready, fresh)
  return engine_tick.tick(state, {
    ship = ship,
    command = command,
    su = 1,
    ready = ready ~= false,
    stick_fresh = fresh == true,
    config = cfg,
    current_elevation_rpm = cfg.hover_equilibrium,
  })
end

local function cruise_state()
  local holding = engine_tick.new_state()
  holding.mode = "auto"
  holding.phase = "climb"
  holding.profile = "cruise"
  holding.waypoint_x = 2000
  holding.waypoint_z = 1600
  return holding
end

local function apply_physics(outputs)
  local ay = elevation_accel(outputs.rsc.rsc11, outputs.relays.relay6 == true)
  ship.y = ship.y + ship.vy * 0.05 + 0.5 * ay * 0.0025
  ship.vy = ship.vy + ay * 0.05
  return ay
end

local function assert_killed(state, outputs, before_alt, before_rpm, label)
  A.eq(state.job, nil, label .. " clears the job")
  A.eq(state.mode, "idle", label .. " does not enter hover")
  A.eq(state.altitude_set, false, label .. " does not latch an altitude")
  A.eq(state.altitude, before_alt, label .. " does not choose a new altitude")
  A.eq(state.waypoint_x, nil, label .. " clears the waypoint")
  A.eq(state.target_speed, 0, label .. " clears the speed")
  A.eq(outputs.relays.relay6, false, label .. " leaves the reverser off")
  A.near(outputs.rsc.rsc11, before_rpm, 1e-4, label .. " leaves elevation where it was")
  if state.altitude >= 2000 or state.altitude >= 999999 then
    error(label .. " stored an impossible altitude " .. tostring(state.altitude))
  end
  local kept = state.altitude
  state, outputs = step_ship(state, nil, true, false)
  A.eq(state.job, nil, label .. " stays cleared")
  A.eq(state.mode, "idle", label .. " stays idle")
  A.eq(state.altitude, kept, label .. " does not adopt a cruise altitude")
  A.near(outputs.rsc.rsc11, before_rpm, 1e-4, label .. " still does not retarget elevation")
  return state, outputs
end

fresh_ship(120, 1)
state = cruise_state()
local outputs
for _ = 1, 25 do
  state, outputs = step_ship(state, nil, true, false)
  apply_physics(outputs)
end
if ship.y >= 400 or ship.vy <= 0 then
  error("automatic cruise was not climbing, y " .. tostring(ship.y) .. " vy " .. tostring(ship.vy))
end
if state.job ~= nil then
  error("automatic cruise invented an altitude job")
end
local cruise_altitude = state.altitude
local cruise_rpm = outputs.rsc.rsc11
state, outputs = step_ship(state, { type = "cancel_jobs" }, true, false)
state, outputs = assert_killed(state, outputs, cruise_altitude, cruise_rpm, "cruise cancel")

fresh_ship(140, 0)
state = engine_tick.new_state()
state, outputs = step_ship(state, { type = "set_altitude", y = 600 }, true, false)
local climbed = 0
while ship.vy < 3 and climbed < 400 do
  apply_physics(outputs)
  state, outputs = step_ship(state, nil, true, false)
  climbed = climbed + 1
end
if ship.vy < 3 or ship.y >= 600 then
  error("altitude climb did not get underway, y " .. tostring(ship.y) .. " vy " .. tostring(ship.vy))
end
local approach_altitude = state.altitude
local approach_rpm = outputs.rsc.rsc11
state, outputs = step_ship(state, { type = "cancel_jobs" }, true, false)
state, outputs = assert_killed(state, outputs, approach_altitude, approach_rpm, "altitude-job cancel")

fresh_ship(150, 0)
state = cruise_state()
state.phase = "hold"
state, outputs = step_ship(state, nil, true, false)
local level_altitude = state.altitude
local level_rpm = outputs.rsc.rsc11
state, outputs = step_ship(state, { type = "cancel_jobs" }, true, false)
state, outputs = assert_killed(state, outputs, level_altitude, level_rpm, "level cancel")

fresh_ship(450, -1)
state = cruise_state()
state.phase = "descend"
state, outputs = step_ship(state, nil, true, false)
local descent_altitude = state.altitude
local descent_rpm = outputs.rsc.rsc11
state, outputs = step_ship(state, { type = "cancel_jobs" }, true, false)
state, outputs = assert_killed(state, outputs, descent_altitude, descent_rpm, "descent cancel")

fresh_ship(1000, 2)
state = cruise_state()
state, outputs = step_ship(state, nil, true, false)
local high_altitude = state.altitude
local high_rpm = outputs.rsc.rsc11
state, outputs = step_ship(state, { type = "cancel_jobs" }, true, false)
state, outputs = assert_killed(state, outputs, high_altitude, high_rpm, "high cancel")

local function expect_track(state, outputs, wanted, label)
  A.eq(state.altitude, wanted, label .. " target")
  local hover = density_hold(ship.y)
  if wanted > ship.y + 0.5 and outputs.rsc.rsc11 <= hover then
    error(label .. " did not climb toward " .. tostring(wanted) .. ", rpm " .. tostring(outputs.rsc.rsc11) .. " hover " .. tostring(hover))
  end
  if wanted < ship.y - 0.5 and outputs.rsc.rsc11 >= hover then
    error(label .. " did not descend toward " .. tostring(wanted) .. ", rpm " .. tostring(outputs.rsc.rsc11) .. " hover " .. tostring(hover))
  end
  state, outputs = step_ship(state, nil, true, false)
  A.eq(state.altitude, wanted, label .. " held")
  hover = density_hold(ship.y)
  if wanted > ship.y + 0.5 and outputs.rsc.rsc11 <= hover then
    error(label .. " dropped the climb on the next step, rpm " .. tostring(outputs.rsc.rsc11))
  end
  if wanted < ship.y - 0.5 and outputs.rsc.rsc11 >= hover then
    error(label .. " dropped the descent on the next step, rpm " .. tostring(outputs.rsc.rsc11))
  end
  return state, outputs
end

fresh_ship(180, 3)
state = cruise_state()
state, outputs = step_ship(state, nil, true, false)
state, outputs = step_ship(state, { type = "set_altitude", y = 250 }, true, false)
state, outputs = expect_track(state, outputs, 250, "set altitude during cruise")

fresh_ship(450, -1)
state = cruise_state()
state.phase = "descend"
state, outputs = step_ship(state, nil, true, false)
state, outputs = step_ship(state, { type = "set_altitude", y = 360 }, true, false)
state, outputs = expect_track(state, outputs, 360, "set altitude during descent")

fresh_ship(180, 2)
state = cruise_state()
state, outputs = step_ship(state, { type = "cancel_jobs" }, true, false)
state, outputs = step_ship(state, { type = "set_altitude", y = 240 }, true, false)
state, outputs = expect_track(state, outputs, 240, "set altitude after cancel")

fresh_ship(160, 0)
state = engine_tick.new_state()
state, outputs = step_ship(state, { type = "set_altitude", y = 500 }, true, false)
climbed = 0
while ship.vy < 2 and climbed < 400 do
  apply_physics(outputs)
  state, outputs = step_ship(state, nil, true, false)
  climbed = climbed + 1
end
if ship.vy < 2 then
  error("approach never left the hover")
end
state, outputs = step_ship(state, { type = "set_altitude", y = 120 }, true, false)
state, outputs = expect_track(state, outputs, 120, "set altitude during an approach")

fresh_ship(180, 1)
state = cruise_state()
state, outputs = step_ship(state, nil, true, false)
state, outputs = step_ship(state, { type = "set_altitude", y = 260 }, true, false)
state, outputs = step_ship(state, { type = "stick", x = 1, y = 0, z = 0 }, true, true)
state, outputs = step_ship(state, nil, true, false)
state, outputs = expect_track(state, outputs, 260, "set altitude after a stick")

fresh_ship(200, 0)
state = engine_tick.new_state()
state.mode = "auto"
state, outputs = step_ship(state, { type = "cancel_jobs" }, false, false)
state, outputs = step_ship(state, { type = "set_altitude", y = 275 }, true, false)
state, outputs = expect_track(state, outputs, 275, "set altitude over a waiting cancel")

local queued = protocol.keep({ type = "set_altitude", y = 275 }, { noise = true })
A.eq(queued.type, "set_altitude", "a non-command leaves the queued altitude")
A.eq(queued.y, 275, "a non-command keeps the queued number")
fresh_ship(190, 0)
state = cruise_state()
state, outputs = step_ship(state, queued, true, false)
state, outputs = step_ship(state, nil, true, false)
A.eq(state.altitude, 275, "a following empty step keeps the set altitude")

local ui = command_ui.new()
local typed
ui, typed = command_ui.key(ui, "y", true)
ui, typed = command_ui.key(ui, "one", true)
ui, typed = command_ui.key(ui, "five", true)
ui, typed = command_ui.key(ui, "zero", true)
ui, typed = command_ui.key(ui, "enter", true)
A.eq(typed.type, "set_altitude", "Y then digits then enter")
A.eq(typed.y, 150, "typed altitude")
fresh_ship(110, 1)
state = cruise_state()
state, outputs = step_ship(state, nil, true, false)
state, outputs = step_ship(state, typed, true, false)
A.eq(state.altitude, 150, "typed altitude replaces the cruise target")

local function mode_ship()
  fresh_ship(180, 0)
  ship.heading = 0
end

local function enter_mode(mode)
  mode_ship()
  local entered = engine_tick.new_state()
  local entry
  entered, entry = step_ship(entered, { type = "set_mode", mode = mode }, true, false)
  return entered, entry.rsc.rsc11
end

local function side_of(rpm, hover)
  if rpm > hover + 0.5 then
    return "above"
  end
  if rpm < hover - 0.5 then
    return "below"
  end
  return "hold"
end

local function assert_altitude_move(mode, target, entry_rpm, state, outputs, label)
  local hover = density_hold(ship.y)
  A.eq(state.altitude, target, label .. " stores the altitude")
  A.eq(state.job, "altitude", label .. " tracks altitude")
  local want = "above"
  if target < ship.y then
    want = "below"
  end
  local got = side_of(outputs.rsc.rsc11, hover)
  if got ~= want then
    error(label .. " rpm " .. tostring(outputs.rsc.rsc11) .. " is " .. got .. " hover " .. tostring(hover))
  end
  if math.abs(outputs.rsc.rsc11 - entry_rpm) <= 0.5 then
    error(label .. " kept the mode rpm " .. tostring(entry_rpm))
  end
  local followed
  state, followed = step_ship(state, nil, true, false)
  A.eq(state.altitude, target, label .. " keeps the altitude")
  if side_of(followed.rsc.rsc11, density_hold(ship.y)) ~= want then
    error(label .. " left the altitude on the next step, rpm " .. tostring(followed.rsc.rsc11))
  end
  return state, followed
end

for _, mode in ipairs({ "manual", "semi", "auto" }) do
  local entered, entry_rpm = enter_mode(mode)
  local above
  entered, above = step_ship(entered, { type = "set_altitude", y = 500 }, true, false)
  entered = assert_altitude_move(mode, 500, entry_rpm, entered, above, mode .. " altitude above")
  entered, entry_rpm = enter_mode(mode)
  local below
  entered, below = step_ship(entered, { type = "set_altitude", y = 80 }, true, false)
  assert_altitude_move(mode, 80, entry_rpm, entered, below, mode .. " altitude below")

  entered, entry_rpm = enter_mode(mode)
  entered, above = step_ship(entered, { type = "set_altitude", y = 500 }, true, false)
  local opposite
  entered, opposite = step_ship(entered, { type = "set_altitude", y = 80 }, true, false)
  assert_altitude_move(mode, 80, above.rsc.rsc11, entered, opposite, mode .. " second altitude")
  local kept = protocol.keep({ type = "set_altitude", y = 80 }, { noise = true })
  A.eq(kept.y, 80, mode .. " non-command keeps the queued altitude")
  entered, opposite = step_ship(entered, nil, true, false)
  A.eq(entered.altitude, 80, mode .. " non-command step keeps the target")
end

local latched, latched_out = enter_mode("manual")
latched, latched_out = step_ship(latched, { type = "set_altitude", y = 320 }, true, false)
for _, mode in ipairs({ "semi", "auto", "manual" }) do
  latched, latched_out = step_ship(latched, { type = "set_mode", mode = mode }, true, false)
  latched, latched_out = step_ship(latched, nil, true, false)
  A.eq(latched.altitude, 320, "mode " .. mode .. " keeps the latched altitude")
  if side_of(latched_out.rsc.rsc11, density_hold(ship.y)) ~= "above" then
    error("mode " .. mode .. " froze elevation at " .. tostring(latched_out.rsc.rsc11))
  end
end

local typed_ui = command_ui.new()
local typed_msg
typed_ui, typed_msg = command_ui.key(typed_ui, "y", true)
typed_ui, typed_msg = command_ui.key(typed_ui, "two", true)
typed_ui, typed_msg = command_ui.key(typed_ui, "six", true)
typed_ui, typed_msg = command_ui.key(typed_ui, "zero", true)
typed_ui, typed_msg = command_ui.key(typed_ui, "enter", true)
A.eq(typed_msg.type, "set_altitude", "typed altitude command")
A.eq(typed_msg.y, 260, "typed altitude number")
local typed_state, typed_entry = enter_mode("semi")
local typed_out
typed_state, typed_out = step_ship(typed_state, typed_msg, true, false)
assert_altitude_move("semi", 260, typed_entry, typed_state, typed_out, "typed altitude after semi")

local function assert_cancel_holds(label)
  local before_alt = state.altitude
  local before_rpm = outputs.rsc.rsc11
  state, outputs = step_ship(state, { type = "cancel_jobs" }, true, false)
  A.eq(state.job, nil, label .. " clears the job")
  A.eq(state.altitude_set, false, label .. " does not latch a hover")
  A.eq(state.altitude, before_alt, label .. " does not write a new altitude")
  A.near(outputs.rsc.rsc11, before_rpm, 1e-4, label .. " does not retarget elevation")
  A.eq(outputs.relays.relay6, false, label .. " does not reverse into a hover")
  state, outputs = step_ship(state, { type = "set_altitude", y = 260 }, true, false)
  assert_altitude_move("idle", 260, before_rpm, state, outputs, label .. " altitude after cancel")
end

mode_ship()
state = engine_tick.new_state()
state, outputs = step_ship(state, { type = "set_mode", mode = "auto" }, true, false)
for _ = 1, 8 do
  apply_physics(outputs)
  state, outputs = step_ship(state, nil, true, false)
end
assert_cancel_holds("cancel from a climb")

mode_ship()
state = engine_tick.new_state()
state, outputs = step_ship(state, { type = "set_mode", mode = "manual" }, true, false)
state, outputs = step_ship(state, nil, true, false)
assert_cancel_holds("cancel after manual chose an rpm")
