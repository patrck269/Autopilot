package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local engine_tick = require("engine_tick")
local config = require("config")
local pid = require("pid")
local stress = require("stress")
local speed = require("speed")

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
A.eq(blocked.mode, "manual", "a mode command survives while not ready")
A.eq(status.mode, "blocked", "status reports blocked while not ready")
A.eq(outputs.rsc.rsc10, 0, "no thrust when blocked")
local resumed
blocked, resumed = engine_tick.tick(blocked, {
  ship = ship, command = nil,
  su = 10, ready = true, stick_fresh = false, config = cfg,
})
A.eq(blocked.mode, "manual", "the mode is still there once the ship is ready")

state = engine_tick.new_state()
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = { type = "diagnostic_enter", hover = false },
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
})
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = { type = "set_altitude", y = 300 },
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
})
A.eq(state.diagnostic, true, "diagnostic ignores altitude until it is closed")
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = { type = "diagnostic_exit" },
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
})
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = { type = "set_altitude", y = 300 },
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
})
A.eq(state.diagnostic, false, "diagnostic exit returns to flight")
A.eq(state.altitude, 300, "altitude after diagnostic exit")
A.eq(state.job, "altitude", "altitude job after diagnostic exit")

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
A.eq(outputs.rsc.rsc2, 0, "bottom bow stays off")
A.eq(outputs.rsc.rsc5, 0, "bottom stern stays off")
A.eq(outputs.rsc.rsc3, 0, "bottom port stays off")
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
A.eq(outputs.rsc.rsc3, 0, "no bottom thruster on the dead side")
A.eq(outputs.rsc.rsc5, 0, "no bottom thruster on the live side")
A.eq(outputs.rsc.rsc11, 0, "a side outage cuts elevation without bottom thrusters")
A.eq(outputs.relays.relay5, true, "a side outage cuts the master Z relay")

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
A.eq(outputs.rsc.rsc2, 0, "pitch does not fire a bottom thruster")
A.eq(outputs.rsc.rsc3, 0, "pitch does not fire the other bottom thruster")

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
local weak_rpm, weak_capture = jobs.hold_stop(nil, 0.2, cfg.ship_mass, 430, true)
local stronger_rpm = jobs.hold_stop(weak_capture, 2, cfg.ship_mass, 430, true)
if stronger_rpm == weak_rpm then
  error("a faster climb kept the weak brake")
end

local function released_stick(start_y, start_vy, label)
  ship.x = 0
  ship.y = start_y
  ship.z = 0
  ship.vx = 0
  ship.vy = start_vy
  ship.vz = 0
  ship.pitch = 0
  ship.roll = 0
  ship.heading = 0
  ship.pitch_rate = 0
  ship.roll_rate = 0
  ship.dt = 0.05
  state = engine_tick.new_state()
  state.mode = "manual"
  state.job = nil
  state.stick = { x = 0, y = 0, z = 0 }
  state.seeded = true
  state.hover_rpm = 430
  state.brake_elev = { rpm = 4000, sign = 1, accel = 80, reverser = true }
  local hover0 = pid.command(pid.calibrate(cfg.hover_equilibrium, 0.05), 0, start_y, start_y, 0, 0.05)
  local max_rpm = 0
  local peak_vy = math.abs(start_vy)
  local reversed = false
  for _ = 1, 300 do
    local stepped
    state, stepped = engine_tick.tick(state, {
      ship = ship,
      command = nil,
      su = 1,
      ready = true,
      stick_fresh = false,
      config = cfg,
      current_elevation_rpm = 430,
    })
    local rpm = stepped.rsc.rsc11
    if rpm > max_rpm then
      max_rpm = rpm
    end
    if stepped.relays.relay6 == true then
      reversed = true
    end
    local net = elevation_accel(rpm, stepped.relays.relay6 == true)
    ship.y = ship.y + ship.vy * 0.05 + 0.5 * net * 0.0025
    ship.vy = ship.vy + net * 0.05
    if math.abs(ship.vy) > peak_vy then
      peak_vy = math.abs(ship.vy)
    end
  end
  if reversed then
    error(label .. " reversed elevation, max rpm " .. tostring(max_rpm))
  end
  if max_rpm > hover0 * 1.5 then
    error(label .. " elevation ran away to " .. tostring(max_rpm) .. " hover " .. tostring(hover0))
  end
  if peak_vy > math.abs(start_vy) + 0.5 then
    error(label .. " vertical speed grew to " .. tostring(peak_vy))
  end
  if math.abs(ship.vy) > 0.5 then
    error(label .. " did not settle, vy " .. tostring(ship.vy) .. " y " .. tostring(ship.y))
  end
end
released_stick(366, 8, "climb release")
released_stick(366, -8, "fall release")

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

local function signed_accel(rpm, mass)
  if rpm == nil or rpm == 0 then
    return 0
  end
  local accel = jobs.thrust(rpm, mass) / mass
  if rpm < 0 then
    return -accel
  end
  return accel
end

local function side_accel(outputs, mass)
  local rsc = outputs.rsc
  return signed_accel(rsc.rsc6, mass) + signed_accel(rsc.rsc8, mass)
    - signed_accel(rsc.rsc7, mass) - signed_accel(rsc.rsc9, mass)
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
if outputs.rsc.rsc8 < 1000 then
  error("full sideways command left the aft port prop off: " .. tostring(outputs.rsc.rsc8))
end
if outputs.rsc.rsc7 >= 0 or outputs.rsc.rsc9 >= 0 then
  error("starboard command did not reverse the starboard props")
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
if outputs.rsc.rsc2 ~= 0 or outputs.rsc.rsc3 ~= 0 or outputs.rsc.rsc4 ~= 0 or outputs.rsc.rsc5 ~= 0 then
  error("manual up commanded a bottom thruster, rsc2 " .. tostring(outputs.rsc.rsc2))
end
if outputs.rsc.rsc11 <= cfg.hover_equilibrium then
  error("manual up did not raise elevation rpm: " .. tostring(outputs.rsc.rsc11))
end
A.eq(outputs.relays.relay6, false, "manual vertical does not reverse elevation")
state = engine_tick.new_state()
state.command_queue = { type = "stick", x = 0, y = 0, z = 1 }
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = nil,
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
  current_elevation_rpm = 430,
})
A.eq(state.command_queue, nil, "queued stick is consumed")
A.eq(state.mode, "manual", "queued stick selects manual")
if outputs.rsc.rsc11 <= cfg.hover_equilibrium then
  error("queued stick up did not raise elevation rpm: " .. tostring(outputs.rsc.rsc11))
end
A.eq(outputs.relays.relay6, false, "queued stick up does not reverse elevation")
local up_su = stress.consumed(outputs)
if up_su > stress.USABLE then
  error("manual up exceeds usable SU: " .. tostring(up_su))
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
if outputs.rsc.rsc2 ~= 0 or outputs.rsc.rsc3 ~= 0 or outputs.rsc.rsc4 ~= 0 or outputs.rsc.rsc5 ~= 0 then
  error("stress limit commanded a bottom thruster")
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
if outputs.rsc.rsc8 >= 0 or outputs.rsc.rsc9 >= 0 then
  error("bearing did not reverse the other side pair")
end
local yaw_force = signed_accel(outputs.rsc.rsc6, cfg.ship_mass) + signed_accel(outputs.rsc.rsc7, cfg.ship_mass)
  - signed_accel(outputs.rsc.rsc8, cfg.ship_mass) - signed_accel(outputs.rsc.rsc9, cfg.ship_mass)
local alpha = yaw_force * 8 / 400
local turned = 0.5 * alpha * 0.05 * 0.05
if turned <= 0 then
  error("heading did not turn toward the bearing")
end

ship.heading = 2
state = engine_tick.new_state()
state.job = "altitude"
state.altitude = 120
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = nil,
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
  current_elevation_rpm = 430,
})
if outputs.rsc.rsc6 ~= 0 or outputs.rsc.rsc7 ~= 0 or outputs.rsc.rsc8 ~= 0 or outputs.rsc.rsc9 ~= 0 then
  error("idle altitude hold yawed without a bearing command, rsc6 " .. tostring(outputs.rsc.rsc6))
end
A.eq(state.bearing_set, nil, "boot bearing is not a commanded course")

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
  if outputs.rsc.rsc8 >= 0 or outputs.rsc.rsc9 >= 0 then
    error(label .. " bearing did not reverse the other side pair")
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
if exact_brake.rsc.rsc6 >= 0 or exact_brake.rsc.rsc8 >= 0 then
  error("side brake did not reverse the other pair")
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
A.eq(outputs.rsc.rsc11, 0, "not ready keeps elevation at zero")
A.eq(outputs.rsc.rsc10, 0, "startup does not add x thrust")
A.eq(state.hover_rpm, 0, "not ready does not store the controller rpm")
A.eq(state.seeded, false, "not ready leaves startup unseeded")
for name, rpm in pairs(outputs.rsc) do
  if rpm ~= 0 then
    error("not ready commanded " .. name .. " " .. tostring(rpm))
  end
end
if outputs.relays.relay2 ~= 0 then
  error("not ready set relay 2 to " .. tostring(outputs.relays.relay2))
end
for name, value in pairs(outputs.relays) do
  if name ~= "relay2" and value ~= false then
    error("not ready set " .. name)
  end
end

ship.heading = 0
ship.pitch_rate = 0
ship.roll_rate = 0
state = engine_tick.new_state()
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = nil,
  su = 1,
  ready = true,
  stick_fresh = false,
  config = cfg,
  current_elevation_rpm = 430,
})
A.eq(state.hover_rpm, 430, "startup keeps the current elevation rpm")
A.eq(outputs.rsc.rsc11, 430, "a ready startup commands that rpm")

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
local steady_sea = low_rpm
local steady_high = high_rpm
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

-- The arrival wobble latches approach_cap to that small peak. The next
-- setpoint has to clear it. This state is the one the acquire left behind;
-- the test does not nil the cap.
do
  ship.x = 0
  ship.y = 120
  ship.z = 0
  ship.vx = 0
  ship.vy = 0
  ship.vz = 0
  ship.heading = 0
  ship.dt = 0.05
  local held = engine_tick.new_state()
  held.mode = "semi"
  held.seeded = true
  held.hover_rpm = density_hold(120)
  local target = 160
  local sent = held.hover_rpm
  for _ = 1, 6000 do
    local command = nil
    if held.job ~= "altitude" then
      command = { type = "set_altitude", y = target }
    end
    local stepped
    held, stepped = engine_tick.tick(held, {
      ship = ship,
      command = command,
      su = 1,
      ready = true,
      stick_fresh = false,
      config = cfg,
      current_elevation_rpm = sent,
    })
    sent = stepped.rsc.rsc11
    local net = elevation_accel(sent, stepped.relays.relay6 == true)
    ship.y = ship.y + ship.vy * 0.05 + 0.5 * net * 0.0025
    ship.vy = ship.vy + net * 0.05
    if math.abs(ship.y - target) <= 0.5 and math.abs(ship.vy) < 0.05 then
      break
    end
  end
  if math.abs(ship.y - target) > 0.5 or math.abs(ship.vy) >= 0.05 then
    error("second setpoint did not settle, y " .. tostring(ship.y) .. " vy " .. tostring(ship.vy))
  end
  local function wobble(vy)
    ship.vy = vy
    local stepped
    held, stepped = engine_tick.tick(held, {
      ship = ship,
      command = nil,
      su = 1,
      ready = true,
      stick_fresh = false,
      config = cfg,
      current_elevation_rpm = sent,
    })
    sent = stepped.rsc.rsc11
  end
  wobble(0.20)
  wobble(-0.065)
  wobble(0.08)
  ship.vy = 0.02
  if held.approach_cap == nil or held.approach_cap > 0.1 then
    error("arrival wobble was not latched, cap " .. tostring(held.approach_cap))
  end
  local latched_cap = held.approach_cap
  local descent = ship.y - 8
  local stepped
  held, stepped = engine_tick.tick(held, {
    ship = ship,
    command = { type = "set_altitude", y = descent },
    su = 1,
    ready = true,
    stick_fresh = false,
    config = cfg,
    current_elevation_rpm = sent,
  })
  A.eq(held.altitude, descent, "second setpoint stores the new altitude")
  if held.approach_cap == latched_cap then
    error("set_altitude kept the arrival cap " .. tostring(latched_cap))
  end
  local hover = density_hold(ship.y)
  local ratio = stepped.rsc.rsc11 / hover
  local accel = 10 * (ratio ^ 1.2) - 10
  if accel > -0.5 then
    error("second setpoint kept the noise cap, accel " .. tostring(accel) .. " rpm " .. tostring(stepped.rsc.rsc11) .. " hover " .. tostring(hover))
  end
  local function queued_tick(vy)
    ship.vy = vy
    local stepped
    held, stepped = engine_tick.tick(held, {
      ship = ship,
      command = nil,
      su = 1,
      ready = true,
      stick_fresh = false,
      config = cfg,
      current_elevation_rpm = sent,
    })
    sent = stepped.rsc.rsc11
  end
  queued_tick(0.20)
  queued_tick(-0.065)
  queued_tick(0.08)
  ship.vy = 0.02
  if held.approach_cap == nil or held.approach_cap > 0.1 then
    error("queued arrival wobble was not latched, cap " .. tostring(held.approach_cap))
  end
  local queued_cap = held.approach_cap
  local queued_descent = ship.y - 8
  held.command_queue = { type = "set_altitude", y = queued_descent }
  held, stepped = engine_tick.tick(held, {
    ship = ship,
    command = nil,
    su = 1,
    ready = true,
    stick_fresh = false,
    config = cfg,
    current_elevation_rpm = sent,
  })
  A.eq(held.command_queue, nil, "queued altitude is consumed")
  A.eq(held.altitude, queued_descent, "queued altitude stores the new setpoint")
  if held.approach_cap == queued_cap then
    error("queued set_altitude kept the arrival cap " .. tostring(queued_cap))
  end
  local queued_hover = density_hold(ship.y)
  local queued_ratio = stepped.rsc.rsc11 / queued_hover
  local queued_accel = 10 * (queued_ratio ^ 1.2) - 10
  if queued_accel > -0.5 then
    error("queued setpoint kept the noise cap, accel " .. tostring(queued_accel))
  end
  local function waypoint_tick(vy)
    ship.vy = vy
    local stepped
    held, stepped = engine_tick.tick(held, {
      ship = ship,
      command = nil,
      su = 1,
      ready = true,
      stick_fresh = false,
      config = cfg,
      current_elevation_rpm = sent,
    })
    sent = stepped.rsc.rsc11
  end
  waypoint_tick(0.20)
  waypoint_tick(-0.065)
  waypoint_tick(0.08)
  ship.vy = 0.02
  if held.approach_cap == nil or held.approach_cap > 0.1 then
    error("waypoint arrival wobble was not latched, cap " .. tostring(held.approach_cap))
  end
  local waypoint_cap = held.approach_cap
  held, stepped = engine_tick.tick(held, {
    ship = ship,
    command = { type = "set_waypoint", x = ship.x + 40, z = ship.z },
    su = 1,
    ready = true,
    stick_fresh = false,
    config = cfg,
    current_elevation_rpm = sent,
  })
  A.eq(held.mode, "auto", "waypoint selects auto")
  A.eq(held.phase, "climb", "waypoint starts a climb")
  if math.abs(ship.y - 160) > 1 or math.abs(ship.vy - 0.02) > 1e-9 then
    error("waypoint case left the latched state, y " .. tostring(ship.y) .. " vy " .. tostring(ship.vy))
  end
  if held.approach_cap ~= nil then
    error("set_waypoint kept an approach cap " .. tostring(held.approach_cap))
  end
  local waypoint_hover = density_hold(ship.y)
  local waypoint_ratio = stepped.rsc.rsc11 / waypoint_hover
  local waypoint_accel = 10 * (waypoint_ratio ^ 1.2) - 10
  -- The noise cap leaves about 0.03 m/s^2. A new climb from this height is the
  -- full 4 m/s^2, about 1.32 times the density hover.
  if waypoint_accel < 3.5 or stepped.rsc.rsc11 < waypoint_hover * 1.3 then
    error("set_waypoint kept the noise cap, accel " .. tostring(waypoint_accel) .. " rpm " .. tostring(stepped.rsc.rsc11) .. " hover " .. tostring(waypoint_hover))
  end
  print(string.format("waypoint climb y=%.3f vy=%.3f accel=%.3f rpm=%.3f hover=%.3f", ship.y, ship.vy, waypoint_accel, stepped.rsc.rsc11, waypoint_hover))
end

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

fresh_ship(450, 0)
ship.vx = 20
ship.x = 0
ship.z = 0
state = engine_tick.new_state()
state.mode = "auto"
state.phase = "climb"
state.waypoint_x = 80
state.waypoint_z = 0
state, outputs = step_ship(state, nil, true, false)
if state.measured_accel ~= nil and state.measured_accel > 50 then
  error("first speed sample was stored as acceleration " .. tostring(state.measured_accel))
end
ship.vx = 20.2
state, outputs = step_ship(state, nil, true, false)
if state.measured_accel == nil or state.measured_accel < 3 or state.measured_accel > 5 then
  error("cruise did not record the real acceleration, got " .. tostring(state.measured_accel))
end
ship.x = 40
state, outputs = step_ship(state, nil, true, false)
A.eq(state.phase, "brake", "cruise brakes inside the measured stopping distance")

fresh_ship(450, 0)
ship.vx = 20
ship.x = -400
ship.z = 0
state = engine_tick.new_state()
state.mode = "auto"
state.phase = "climb"
state.waypoint_x = 0
state.waypoint_z = 0
state, outputs = step_ship(state, nil, true, false)
ship.vx = 20.2
state, outputs = step_ship(state, nil, true, false)
local stop = speed.brake_distance(ship.vx, state.measured_accel)
ship.x = -(stop + 100)
ship.vx = ship.vx + 0.01
state, outputs = step_ship(state, nil, true, false)
A.eq(state.phase, "track", "a smaller speed gain does not brake outside the demonstrated stop")
if outputs.rsc.rsc10 < 0 then
  error("cruise reversed outside the demonstrated stopping distance, rsc10 " .. tostring(outputs.rsc.rsc10))
end

fresh_ship(120, 0)
ship.x = 2000
ship.z = -800
state = engine_tick.new_state()
state, outputs = step_ship(state, { type = "set_mode", mode = "auto" }, true, false)
local mode_hover = density_hold(ship.y)
if outputs.rsc.rsc11 > mode_hover + 50 then
  error("automatic mode climbed without an altitude or a waypoint, rpm " .. tostring(outputs.rsc.rsc11))
end
A.eq(state.altitude, 120, "automatic mode keeps the altitude the ship is at")
A.eq(state.waypoint_x, nil, "automatic mode does not invent a waypoint")
for _ = 1, 200 do
  apply_physics(outputs)
  state, outputs = step_ship(state, nil, true, false)
end
if ship.y > 160 then
  error("automatic mode left the ship altitude for the cruise band, y " .. tostring(ship.y))
end
state, outputs = step_ship(state, { type = "set_altitude", y = 150 }, true, false)
A.eq(state.altitude, 150, "set altitude replaces the mode")
if outputs.rsc.rsc11 <= density_hold(ship.y) then
  error("set altitude after automatic did not climb, rpm " .. tostring(outputs.rsc.rsc11))
end
for _ = 1, 400 do
  apply_physics(outputs)
  state, outputs = step_ship(state, nil, true, false)
end
if ship.y > 190 then
  error("set altitude after automatic ran away, y " .. tostring(ship.y))
end

fresh_ship(120, 0)
state = engine_tick.new_state()
state, outputs = step_ship(state, { type = "set_mode", mode = "semi" }, true, false)
mode_hover = density_hold(ship.y)
if math.abs(outputs.rsc.rsc11 - mode_hover) > 1 then
  error("semi mode did not hold altitude, rpm " .. tostring(outputs.rsc.rsc11) .. " hover " .. tostring(mode_hover))
end
state, outputs = step_ship(state, nil, true, false)
if math.abs(outputs.rsc.rsc11 - density_hold(ship.y)) > 1 then
  error("semi mode left the altitude on the next step, rpm " .. tostring(outputs.rsc.rsc11))
end

fresh_ship(120, 0)
state = engine_tick.new_state()
state, outputs = step_ship(state, { type = "stick", x = 0, y = 0, z = -1 }, true, true)
if outputs.rsc.rsc2 < 0 or outputs.rsc.rsc3 < 0 or outputs.rsc.rsc4 < 0 or outputs.rsc.rsc5 < 0 then
  error("down command spun the upward thrusters the other way, rsc2 " .. tostring(outputs.rsc.rsc2))
end
if outputs.rsc.rsc11 >= cfg.hover_equilibrium then
  error("down command did not lower elevation, rpm " .. tostring(outputs.rsc.rsc11))
end

fresh_ship(120, 0)
state = engine_tick.new_state()
state.mode = "auto"
state.job = "altitude"
state.altitude = 180
state.altitude_set = true
local blocked_state, blocked_outputs, blocked_status = step_ship(state, nil, false, false)
A.eq(blocked_state.mode, "auto", "a missing peripheral does not erase the flight mode")
A.eq(blocked_state.altitude, 180, "a missing peripheral keeps the altitude")
A.eq(blocked_status.mode, "blocked", "status reports blocked while not ready")
A.eq(blocked_outputs.rsc.rsc10, 0, "not ready does not cruise")
blocked_state, blocked_outputs = step_ship(blocked_state, nil, true, false)
A.eq(blocked_state.mode, "auto", "flight mode returns when the peripheral returns")
A.eq(blocked_state.altitude, 180, "the altitude is still the command")
if blocked_outputs.rsc.rsc11 <= density_hold(ship.y) then
  error("the altitude command was dropped while a peripheral was missing, rpm " .. tostring(blocked_outputs.rsc.rsc11))
end

fresh_ship(120, 0)
state = engine_tick.new_state()
state, outputs = engine_tick.tick(state, {
  ship = ship,
  command = { type = "emergency" },
  su = 1,
  ready = false,
  stick_fresh = false,
  config = cfg,
  current_elevation_rpm = 430,
})
A.eq(outputs.rsc.rsc11, 0, "emergency cuts elevation while a peripheral is missing")
A.eq(state.emergency, true, "emergency latches while a peripheral is missing")

fresh_ship(120, 0)
state = engine_tick.new_state()
state.mode = "auto"
state.job = "altitude"
state.altitude = 160
state.altitude_set = true
state, outputs = step_ship(state, { type = "diagnostic_enter", hover = false }, true, false)
state, outputs = step_ship(state, { type = "emergency" }, true, false)
state, outputs = step_ship(state, { type = "clear_emergency" }, true, false)
A.eq(state.diagnostic, false, "emergency closes diagnostic")
A.eq(state.mode, "idle", "emergency does not leave the ship in diagnostic")
A.eq(state.emergency, false, "clear releases the stop")
state, outputs = step_ship(state, { type = "set_altitude", y = 200 }, true, false)
A.eq(state.altitude, 200, "altitude works after emergency leaves diagnostic")
A.eq(state.job, "altitude", "altitude job works after emergency leaves diagnostic")

fresh_ship(120, 0)
state = engine_tick.new_state()
state, outputs = step_ship(state, { type = "set_altitude", y = 2000 }, true, false)
if outputs.rsc.rsc11 <= density_hold(ship.y) then
  error("setup altitude did not climb, rpm " .. tostring(outputs.rsc.rsc11))
end
local cancelled_rpm = outputs.rsc.rsc11
state, outputs = step_ship(state, { type = "cancel_jobs" }, true, false)
A.eq(state.altitude, 2000, "cancel leaves the old altitude number")
A.near(outputs.rsc.rsc11, cancelled_rpm, 1e-4, "cancel leaves elevation rpm")
state, outputs = step_ship(state, { type = "set_mode", mode = "auto" }, true, false)
if outputs.rsc.rsc11 > density_hold(ship.y) + 50 then
  error("automatic after cancel resumed the cancelled altitude, rpm " .. tostring(outputs.rsc.rsc11))
end
A.eq(state.altitude, ship.y, "automatic after cancel holds the ship altitude")
state, outputs = step_ship(state, nil, true, false)
if outputs.rsc.rsc11 > density_hold(ship.y) + 50 then
  error("automatic after cancel climbed on the next step, rpm " .. tostring(outputs.rsc.rsc11))
end

fresh_ship(120, 0)
state = engine_tick.new_state()
state, outputs = step_ship(state, { type = "set_mode", mode = "auto" }, true, false)
ship.y = 180
ship.vy = 0
state, outputs = step_ship(state, { type = "set_mode", mode = "auto" }, true, false)
if outputs.rsc.rsc11 < density_hold(ship.y) - 50 then
  error("automatic after the ship moved returned to the old altitude, rpm " .. tostring(outputs.rsc.rsc11))
end
A.eq(state.altitude, ship.y, "automatic after the ship moved holds that altitude")
local held_y = ship.y
for _ = 1, 200 do
  apply_physics(outputs)
  state, outputs = step_ship(state, nil, true, false)
end
if math.abs(ship.y - held_y) > 20 then
  error("automatic after the ship moved left that altitude, y " .. tostring(ship.y))
end

fresh_ship(120, 0)
state = engine_tick.new_state()
state, outputs = step_ship(state, { type = "set_mode", mode = "semi" }, true, false)
ship.y = 180
ship.vy = 0
state, outputs = step_ship(state, { type = "set_mode", mode = "semi" }, true, false)
if math.abs(outputs.rsc.rsc11 - density_hold(ship.y)) > 1 then
  error("semi after the ship moved did not hold that altitude, rpm " .. tostring(outputs.rsc.rsc11))
end
A.eq(state.altitude, ship.y, "semi after the ship moved holds that altitude")

fresh_ship(120, 0)
ship.x = 0
ship.z = 0
ship.vx = 0
ship.vz = 0
state = engine_tick.new_state()
state, outputs = step_ship(state, { type = "set_waypoint", x = 400, z = 0 }, true, false)
local cruise_ticks = 0
while state.phase ~= "track" and cruise_ticks < 8000 do
  apply_physics(outputs)
  state, outputs = step_ship(state, nil, true, false)
  cruise_ticks = cruise_ticks + 1
end
if state.phase ~= "track" or ship.y < 400 then
  error("cruise did not reach track, phase " .. tostring(state.phase) .. " y " .. tostring(ship.y))
end
local track_ticks = 0
while (math.abs(ship.y - 400) > 15 or math.abs(ship.vy) > 1) and track_ticks < 4000 do
  apply_physics(outputs)
  state, outputs = step_ship(state, nil, true, false)
  track_ticks = track_ticks + 1
end
if state.phase ~= "track" or math.abs(ship.y - 400) > 15 or math.abs(ship.vy) > 1 then
  error("track did not hold 400, phase " .. tostring(state.phase) .. " y " .. tostring(ship.y) .. " vy " .. tostring(ship.vy))
end
if outputs.rsc.rsc11 < density_hold(ship.y) - 150 then
  error("track left the cruise altitude of 400, rpm " .. tostring(outputs.rsc.rsc11))
end
for _ = 1, 80 do
  ship.vx = ship.vx + 0.1
  apply_physics(outputs)
  state, outputs = step_ship(state, nil, true, false)
end
ship.x = 388
ship.vx = 8
apply_physics(outputs)
state, outputs = step_ship(state, nil, true, false)
if state.phase ~= "brake" then
  error("cruise did not brake, phase " .. tostring(state.phase) .. " accel " .. tostring(state.measured_accel))
end
if math.abs(ship.y - 400) <= 30 and outputs.rsc.rsc11 < density_hold(ship.y) - 150 then
  error("brake left the cruise altitude of 400, rpm " .. tostring(outputs.rsc.rsc11))
end
ship.x = 400
ship.vx = 0
ship.vz = 0
local arrived = false
for _ = 1, 8000 do
  apply_physics(outputs)
  state, outputs = step_ship(state, nil, true, false)
  if state.phase == "hold" and ship.y <= 329 then
    arrived = true
    break
  end
end
if not arrived then
  error("cruise did not arrive, phase " .. tostring(state.phase) .. " y " .. tostring(ship.y))
end
local arrival_hover = density_hold(ship.y)
if outputs.rsc.rsc11 > arrival_hover + 50 then
  error("arrival climbed toward 400, rpm " .. tostring(outputs.rsc.rsc11) .. " hover " .. tostring(arrival_hover))
end
local arrival_y = ship.y
for _ = 1, 600 do
  apply_physics(outputs)
  state, outputs = step_ship(state, nil, true, false)
end
if ship.y > 360 or ship.y > arrival_y + 30 then
  error("hold after descent climbed toward 400, y " .. tostring(ship.y))
end
A.eq(state.phase, "hold", "arrival stays in hold")
A.eq(state.waypoint_x, 400, "arrival keeps the waypoint")

-- Closed loop through the shipped tick and the shipped speed hold. The plant
-- integrates the RPM apply actually sent, so a held integer cannot be refreshed
-- every tick. os.clock is pinned so the 1.5s limit does not depend on wall time;
-- the hold still releases by its apply countdown.
local function held_altitude(start_y, start_vy, target, label)
  package.loaded.runtime = nil
  local runtime = require("runtime")
  local pinned = os.clock()
  local real_clock = os.clock
  os.clock = function()
    return pinned
  end
  fresh_ship(start_y, start_vy)
  local holding = engine_tick.new_state()
  local sent = cfg.hover_equilibrium
  local devices = {
    rsc11 = {
      setTargetSpeed = function(rpm)
        sent = rpm
      end,
      getTargetSpeed = function()
        return sent
      end,
    },
  }
  local band = 4
  local arrived = false
  local left_band = false
  local worst_after = 0
  local past = false
  local back = false
  local first_peak = nil
  local later_peak = 0
  local peak = 0
  local quiet = 0
  local quiet_best = 0
  local steps = 5000
  for i = 1, steps do
    local command = nil
    if i == 1 then
      command = { type = "set_altitude", y = target }
    end
    local stepped
    holding, stepped = engine_tick.tick(holding, {
      ship = ship,
      command = command,
      su = 1,
      ready = true,
      stick_fresh = false,
      config = cfg,
      current_elevation_rpm = cfg.hover_equilibrium,
    })
    runtime.apply(stepped, devices)
    if ship.y > target and sent <= 0 then
      os.clock = real_clock
      error(label .. " held elevation at zero while still above the target, y " .. tostring(ship.y))
    end
    local net = elevation_accel(sent, stepped.relays.relay6 == true)
    ship.y = ship.y + ship.vy * 0.05 + 0.5 * net * 0.0025
    ship.vy = ship.vy + net * 0.05
    local err = ship.y - target
    local abs_err = math.abs(err)
    if not past then
      local beyond = (start_y < target and err > 0) or (start_y > target and err < 0)
      if beyond then
        past = true
        peak = abs_err
      end
    elseif not back then
      if abs_err > peak then
        peak = abs_err
      end
      local returned = (start_y < target and err <= 0) or (start_y > target and err >= 0)
      if returned then
        back = true
        first_peak = peak
        peak = abs_err
      end
    elseif abs_err > later_peak then
      later_peak = abs_err
    end
    if not arrived then
      if abs_err <= band then
        arrived = true
        worst_after = abs_err
      end
    else
      if abs_err > worst_after then
        worst_after = abs_err
      end
      if abs_err > band then
        left_band = true
      end
    end
    if abs_err <= band and math.abs(ship.vy) < 0.2 then
      quiet = quiet + 1
      if quiet > quiet_best then
        quiet_best = quiet
      end
    else
      quiet = 0
    end
  end
  os.clock = real_clock
  if not arrived then
    error(label .. " never arrived, y " .. tostring(ship.y) .. " vy " .. tostring(ship.vy))
  end
  if left_band then
    error(label .. " left the arrival band, worst " .. tostring(worst_after) .. " y " .. tostring(ship.y))
  end
  if quiet_best < 400 then
    error(label .. " vertical speed did not stay near zero, quiet " .. tostring(quiet_best) .. " vy " .. tostring(ship.vy))
  end
  if first_peak ~= nil and later_peak >= first_peak then
    error(label .. " later excursion " .. tostring(later_peak) .. " reached the first overshoot " .. tostring(first_peak))
  end
  if math.abs(ship.y - target) > band or math.abs(ship.vy) >= 0.2 then
    error(label .. " did not settle, y " .. tostring(ship.y) .. " vy " .. tostring(ship.vy))
  end
  print(string.format("held-altitude %s settled y=%.6f vy=%.6f", label, ship.y, ship.vy))
end

held_altitude(80, 0, 120, "below")
held_altitude(140, 8, 120, "climb")

-- A 0.05s flight tick must accumulate a trim sample. This hull hovers at 460
-- RPM where the density curve commands about 514, the clock advances one step
-- per apply, and the next tick sees the RPM setTargetSpeed actually received.
local function held_altitude_hull(start_y, start_vy, target, label)
  package.loaded.runtime = nil
  local runtime = require("runtime")
  local real_clock = os.clock
  local clock = 0
  os.clock = function()
    return clock
  end
  fresh_ship(start_y, start_vy)
  local holding = engine_tick.new_state()
  local sent = cfg.hover_equilibrium
  local devices = {
    rsc11 = {
      setTargetSpeed = function(rpm)
        sent = rpm
      end,
      getTargetSpeed = function()
        return sent
      end,
    },
  }
  local density_at_target = cfg.hover_equilibrium * pid.thrust_scale(target)
  local true_hover = 460
  local function hull_accel(rpm, reverser)
    local model_eq = cfg.hover_equilibrium * pid.thrust_scale(ship.y)
    local true_eq = true_hover * model_eq / density_at_target
    if true_eq <= 0 then
      return elevation_accel(rpm, reverser)
    end
    return elevation_accel(rpm * (model_eq / true_eq), reverser)
  end
  local band = 4
  local arrived = false
  local left_band = false
  local worst_after = 0
  local quiet = 0
  local quiet_best = 0
  local steps = 5000
  for i = 1, steps do
    clock = clock + 0.05
    local command = nil
    if i == 1 then
      command = { type = "set_altitude", y = target }
    end
    local stepped
    holding, stepped = engine_tick.tick(holding, {
      ship = ship,
      command = command,
      su = 1,
      ready = true,
      stick_fresh = false,
      config = cfg,
      current_elevation_rpm = sent,
    })
    runtime.apply(stepped, devices)
    if ship.y > target and sent <= 0 then
      os.clock = real_clock
      error(label .. " held elevation at zero while still above the target, y " .. tostring(ship.y))
    end
    local net = hull_accel(sent, stepped.relays.relay6 == true)
    ship.y = ship.y + ship.vy * 0.05 + 0.5 * net * 0.0025
    ship.vy = ship.vy + net * 0.05
    local abs_err = math.abs(ship.y - target)
    if not arrived then
      if abs_err <= band then
        arrived = true
        worst_after = abs_err
      end
    else
      if abs_err > worst_after then
        worst_after = abs_err
      end
      if abs_err > band then
        left_band = true
      end
    end
    if abs_err <= band and math.abs(ship.vy) < 0.2 then
      quiet = quiet + 1
      if quiet > quiet_best then
        quiet_best = quiet
      end
    else
      quiet = 0
    end
  end
  os.clock = real_clock
  if not arrived then
    error(label .. " never arrived, y " .. tostring(ship.y) .. " vy " .. tostring(ship.vy))
  end
  if left_band then
    error(label .. " left the arrival band, worst " .. tostring(worst_after) .. " y " .. tostring(ship.y))
  end
  if quiet_best < 400 then
    error(label .. " vertical speed did not stay near zero, quiet " .. tostring(quiet_best) .. " vy " .. tostring(ship.vy))
  end
  if math.abs(ship.y - target) > band or math.abs(ship.vy) >= 0.2 then
    error(label .. " did not settle, y " .. tostring(ship.y) .. " vy " .. tostring(ship.vy))
  end
  print(string.format("held-altitude %s settled y=%.6f vy=%.6f", label, ship.y, ship.vy))
end

held_altitude_hull(120, 0, 120, "hull")

-- A cruise that is still climbing leaves the forward controller running.
-- The uncapped high climb is the server maximum, so a hover-only RPM cannot pass.
local function cruise_climb(world_y)
  ship.x = 0
  ship.y = world_y
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
  local climbing = engine_tick.new_state()
  climbing.mode = "auto"
  climbing.phase = "track"
  climbing.profile = "cruise"
  climbing.waypoint_x = 5000
  climbing.waypoint_z = 0
  climbing.altitude = 5000
  climbing.altitude_set = true
  climbing.hover_rpm = cfg.hover_equilibrium
  local outputs
  climbing, outputs = engine_tick.tick(climbing, {
    ship = ship,
    command = nil,
    su = 1,
    ready = true,
    stick_fresh = false,
    config = cfg,
    current_elevation_rpm = cfg.hover_equilibrium,
  })
  return outputs
end

local function uncapped_climb_rpm(world_y)
  local eq = cfg.hover_equilibrium * pid.thrust_scale(world_y)
  local specific = 14
  return config.clamp_rpm(eq * ((specific / 10) ^ (1 / 1.2)))
end

local function assert_budget_climb(label, world_y, outputs)
  if not (stress.USABLE < stress.CAPACITY) then
    error("usable budget is not below capacity")
  end
  local hover = density_hold(world_y)
  local elev_per_rpm = stress.ELEVATION_PROPS * stress.ELEVATION_IMPACT
  local hover_room = stress.USABLE / elev_per_rpm
  local kept_hover = hover
  if kept_hover > hover_room then
    kept_hover = hover_room
  end
  local elev = outputs.rsc.rsc11
  if elev <= hover then
    error(label .. " elevation stayed at hover rpm " .. tostring(elev))
  end
  if elev + 1e-6 < kept_hover then
    error(label .. " elevation " .. tostring(elev) .. " dropped below the hover this height can keep " .. tostring(kept_hover))
  end
  if elev <= 0 then
    error(label .. " elevation climb was not positive")
  end
  if elev > cfg.max_rpm then
    error(label .. " elevation exceeded the server maximum " .. tostring(elev))
  end
  if outputs.relays.relay6 ~= false then
    error(label .. " reversed the elevation controller")
  end
  local total = stress.consumed(outputs)
  if total > stress.USABLE then
    error(label .. " stress " .. tostring(total) .. " exceeds usable " .. tostring(stress.USABLE))
  end
  for name, rpm in pairs(outputs.rsc) do
    if rpm ~= 0 then
      local stripped = { rsc = {} }
      for other, value in pairs(outputs.rsc) do
        stripped.rsc[other] = value
      end
      stripped.rsc[name] = 0
      if stress.consumed(stripped) >= total - 1e-6 then
        error(label .. " " .. name .. " is nonzero but missing from the stress total")
      end
    end
  end
  print(string.format("climb %s elevation=%.6f stress=%.6f", label, elev, total))
  return total
end

local low_climb = cruise_climb(120)
if uncapped_climb_rpm(120) >= cfg.max_rpm then
  error("low climb was not below the server maximum")
end
assert_budget_climb("low", 120, low_climb)

local high_climb = cruise_climb(1000)
local high_uncapped = uncapped_climb_rpm(1000)
if high_uncapped ~= cfg.max_rpm then
  error("high climb uncapped elevation was not the server maximum, got " .. tostring(high_uncapped))
end
local high_hover = density_hold(1000)
if high_hover < 25000 or high_hover > 27000 then
  error("high climb is not at a density hover inside 25000-27000")
end
assert_budget_climb("high", 1000, high_climb)
print(string.format("steady hover sea=%.6f high=%.6f", steady_sea, steady_high))

local function integrate_sent(rpm, reverser, true_over_model, step)
  if step == nil or step <= 0 then
    step = 0.05
  end
  local net = elevation_accel(rpm, reverser)
  if true_over_model ~= nil and true_over_model > 0 then
    net = elevation_accel(rpm / true_over_model, reverser)
  end
  ship.y = ship.y + ship.vy * step + 0.5 * net * step * step
  ship.vy = ship.vy + net * step
  return net
end

local function run_mode(label, opts)
  package.loaded.runtime = nil
  local runtime = require("runtime")
  local real_clock = os.clock
  local clock = 0
  os.clock = function()
    return clock
  end
  fresh_ship(opts.y, opts.vy or 0)
  local state = engine_tick.new_state()
  state.mode = opts.mode or "idle"
  state.job = opts.job
  state.seeded = true
  state.hover_rpm = opts.hover_rpm or density_hold(opts.y)
  if opts.elev_scale ~= nil then
    state.elev_scale = opts.elev_scale
  end
  if opts.elev_anchor ~= nil then
    state.elev_anchor = opts.elev_anchor
    state.elev_anchor_y = opts.y
  end
  if opts.altitude ~= nil then
    state.altitude = opts.altitude
    state.altitude_set = true
    state.job = opts.job or "altitude"
  end
  if opts.waypoint_x ~= nil then
    state.waypoint_x = opts.waypoint_x
    state.waypoint_z = opts.waypoint_z or 0
    state.phase = opts.phase or "climb"
    state.mode = "auto"
  end
  local sent = state.hover_rpm
  local devices = {
    rsc11 = {
      setTargetSpeed = function(rpm)
        sent = rpm
      end,
      getTargetSpeed = function()
        return sent
      end,
    },
  }
  local reversed = false
  local peak_vy = math.abs(ship.vy)
  local prev_sign = 0
  if ship.vy > 0.05 then
    prev_sign = 1
  elseif ship.vy < -0.05 then
    prev_sign = -1
  end
  local grew = false
  local max_rpm = 0
  local min_rpm = 1e12
  local above = false
  local below = false
  local hover0 = density_hold(opts.y)
  local biggest = 0
  local prev_cmd = nil
  local step = opts.tick or 0.05
  for i = 1, opts.steps do
    clock = clock + step
    local command = nil
    if i == 1 and opts.command ~= nil then
      command = opts.command
    elseif opts.stick ~= nil then
      command = { type = "stick", x = 0, y = 0, z = opts.stick }
    end
    local stepped
    state, stepped = engine_tick.tick(state, {
      ship = ship,
      command = command,
      su = 1,
      ready = true,
      stick_fresh = command ~= nil and command.type == "stick",
      config = cfg,
      current_elevation_rpm = sent,
    })
    runtime.apply(stepped, devices)
    if stepped.relays.relay6 == true then
      reversed = true
    end
    if sent > max_rpm then
      max_rpm = sent
    end
    if sent < min_rpm then
      min_rpm = sent
    end
    local commanded = stepped.rsc.rsc11
    if prev_cmd ~= nil and math.abs(commanded - prev_cmd) > biggest then
      biggest = math.abs(commanded - prev_cmd)
    end
    prev_cmd = commanded
    if sent > hover0 + 5 then
      above = true
    end
    if sent < hover0 - 5 then
      below = true
    end
    integrate_sent(sent, stepped.relays.relay6 == true, opts.true_over_model, step)
    local sign = 0
    if ship.vy > 0.05 then
      sign = 1
    elseif ship.vy < -0.05 then
      sign = -1
    end
    if prev_sign ~= 0 and sign ~= 0 and sign ~= prev_sign and math.abs(ship.vy) > peak_vy + 0.5 then
      grew = true
    end
    if sign ~= 0 then
      prev_sign = sign
    end
    if math.abs(ship.vy) > peak_vy then
      peak_vy = math.abs(ship.vy)
    end
  end
  os.clock = real_clock
  return {
    y = ship.y,
    vy = ship.vy,
    reversed = reversed,
    peak_vy = peak_vy,
    grew = grew,
    max_rpm = max_rpm,
    min_rpm = min_rpm,
    above = above,
    below = below,
    biggest = biggest,
    hover0 = hover0,
    scale = state.elev_scale,
    mode = state.mode,
    job = state.job,
    sent = sent,
  }
end

local stick_up = run_mode("stick up", {
  y = 120, vy = 0, mode = "manual", stick = 1, steps = 80,
  hover_rpm = density_hold(120),
})
if stick_up.reversed or not stick_up.above then
  error("stick up did not climb above the density hover, rpm " .. tostring(stick_up.max_rpm))
end

local stick_down = run_mode("stick down", {
  y = 120, vy = 0, mode = "manual", stick = -1, steps = 80,
  hover_rpm = density_hold(120),
})
if stick_down.reversed or not stick_down.below then
  error("stick down did not descend below the density hover, rpm " .. tostring(stick_down.min_rpm))
end
if stick_down.biggest > cfg.hover_step + 1 then
  error("stick down took a one-tick stop, step " .. tostring(stick_down.biggest))
end

local function assert_settled(label, got, target)
  local band = cfg.altitude_deadzone
  if got.reversed then
    error(label .. " reversed elevation")
  end
  if got.grew then
    error(label .. " vertical speed grew into a larger opposite swing, peak " .. tostring(got.peak_vy))
  end
  if math.abs(got.y - target) > band or math.abs(got.vy) > 0.5 then
    error(label .. " missed the deadzone, y " .. tostring(got.y) .. " vy " .. tostring(got.vy))
  end
end

assert_settled("altitude below", run_mode("altitude below", {
  y = 120, vy = 0, mode = "idle", altitude = 200, steps = 4000,
}), 200)
assert_settled("altitude above", run_mode("altitude above", {
  y = 280, vy = 0, mode = "idle", altitude = 200, steps = 4000,
}), 200)
assert_settled("semi below", run_mode("semi below", {
  y = 120, vy = 0, mode = "semi", altitude = 200, steps = 4000,
}), 200)
assert_settled("semi above", run_mode("semi above", {
  y = 280, vy = 0, mode = "semi", altitude = 200, steps = 4000,
}), 200)

local auto_hold = run_mode("auto", {
  y = 80, vy = 0, waypoint_x = 5000, steps = 8000,
})
assert_settled("auto", auto_hold, 400)

local idle_hold = run_mode("idle", {
  y = 120, vy = 0, mode = "idle", steps = 200,
  hover_rpm = density_hold(120),
})
if idle_hold.reversed or idle_hold.biggest > 1 then
  error("idle walked elevation, step " .. tostring(idle_hold.biggest))
end

local hover_hold = run_mode("hover", {
  y = 120, vy = 4, mode = "semi", job = "hover", steps = 800,
  hover_rpm = density_hold(120),
})
if hover_hold.reversed or math.abs(hover_hold.vy) > 0.5 then
  error("hover did not settle, vy " .. tostring(hover_hold.vy) .. " rpm " .. tostring(hover_hold.sent))
end
if hover_hold.max_rpm > hover_hold.hover0 * 1.5 then
  error("hover walked the rpm to " .. tostring(hover_hold.max_rpm))
end

local released = run_mode("released", {
  y = 366, vy = 8, mode = "manual", steps = 800,
  hover_rpm = density_hold(366),
})
if released.reversed or math.abs(released.vy) > 0.5 then
  error("released stick did not stop, vy " .. tostring(released.vy))
end
if released.max_rpm > released.hover0 * 1.5 or released.min_rpm < released.hover0 * 0.5 then
  error("released stick left the density hover, rpm " .. tostring(released.min_rpm) .. " " .. tostring(released.max_rpm))
end

-- The live hull hovers far below the density curve. The trim used to ignore
-- that and every mode kept climbing.
local far = density_hold(200) / 2.2
local far_hold = run_mode("far hull", {
  y = 200, vy = 0, mode = "semi", altitude = 200, steps = 8000,
  hover_rpm = far, true_over_model = 1 / 2.2,
})
assert_settled("far hull", far_hold, 200)
local far_release = run_mode("far release", {
  y = 200, vy = 8, mode = "manual", steps = 8000,
  hover_rpm = far, true_over_model = 1 / 2.2,
})
if far_release.reversed or math.abs(far_release.vy) > 0.5 or far_release.y > 280 then
  error("far release ran away, y " .. tostring(far_release.y) .. " vy " .. tostring(far_release.vy))
end

-- The live computer samples slower than the nominal step, and this hull
-- hovers below the scale it had already learned. The trim has to follow
-- that over the real interval, and the held integer must not hunt.
local live_pace = run_mode("live pace", {
  y = 490, vy = 2, mode = "semi", altitude = 450, steps = 400,
  hover_rpm = density_hold(490) / 1.85,
  elev_scale = 1.58,
  true_over_model = 1 / 1.85,
  tick = 0.30,
})
if live_pace.scale == nil or live_pace.scale < 1.75 then
  error("live pace did not follow the hull, scale " .. tostring(live_pace.scale))
end
assert_settled("live pace", live_pace, 450)

-- A trim learned at another height used to divide a gentle release, and the
-- held integer reversed a small climb. The anchor is the RPM this hull holds.
local stale_anchor = density_hold(72) / 1.05
local stale_climb = run_mode("stale climb", {
  y = 72, vy = 0, mode = "idle", altitude = 84, steps = 2500,
  hover_rpm = stale_anchor,
  elev_scale = 1.36,
  elev_anchor = stale_anchor,
  true_over_model = 1 / 1.05,
})
assert_settled("stale climb", stale_climb, 84)
if stale_climb.min_rpm < stale_anchor * 0.85 then
  error("stale climb slammed rpm to " .. tostring(stale_climb.min_rpm))
end

local function stale_idle_then_release()
  package.loaded.runtime = nil
  local runtime = require("runtime")
  local real_clock = os.clock
  local clock = 0
  os.clock = function()
    return clock
  end
  local anchor = density_hold(72) / 1.05
  fresh_ship(72, 0)
  local holding = engine_tick.new_state()
  holding.mode = "idle"
  holding.seeded = true
  holding.hover_rpm = anchor
  holding.elev_scale = 1.36
  local sent = anchor
  local devices = {
    rsc11 = {
      setTargetSpeed = function(rpm)
        sent = rpm
      end,
      getTargetSpeed = function()
        return sent
      end,
    },
  }
  local max_step = 0
  local prev = nil
  for _ = 1, 80 do
    clock = clock + 0.30
    local stepped
    holding, stepped = engine_tick.tick(holding, {
      ship = ship,
      command = nil,
      su = 1,
      ready = true,
      stick_fresh = false,
      config = cfg,
      current_elevation_rpm = sent,
    })
    runtime.apply(stepped, devices)
    if prev ~= nil and math.abs(stepped.rsc.rsc11 - prev) > max_step then
      max_step = math.abs(stepped.rsc.rsc11 - prev)
    end
    prev = stepped.rsc.rsc11
    integrate_sent(sent, stepped.relays.relay6 == true, 1 / 1.05, 0.30)
  end
  if max_step > 1 then
    os.clock = real_clock
    error("idle learned by walking rpm, step " .. tostring(max_step))
  end
  if holding.elev_anchor == nil or math.abs(holding.elev_anchor - anchor) / anchor > 0.08 then
    os.clock = real_clock
    error("idle did not learn the hold it was flying, anchor " .. tostring(holding.elev_anchor))
  end
  holding.mode = "manual"
  holding.stick = { x = 0, y = 0, z = 0 }
  ship.vy = 0.75
  local min_rpm = sent
  local peak_vy = math.abs(ship.vy)
  local prev_sign = 1
  for _ = 1, 40 do
    clock = clock + 0.30
    local stepped
    holding, stepped = engine_tick.tick(holding, {
      ship = ship,
      command = nil,
      su = 1,
      ready = true,
      stick_fresh = false,
      config = cfg,
      current_elevation_rpm = sent,
    })
    runtime.apply(stepped, devices)
    if stepped.relays.relay6 == true then
      os.clock = real_clock
      error("stale release reversed elevation")
    end
    if sent < min_rpm then
      min_rpm = sent
    end
    integrate_sent(sent, false, 1 / 1.05, 0.30)
    local sign = 0
    if ship.vy > 0.05 then
      sign = 1
    elseif ship.vy < -0.05 then
      sign = -1
    end
    if prev_sign ~= 0 and sign ~= 0 and sign ~= prev_sign and math.abs(ship.vy) > peak_vy + 0.5 then
      os.clock = real_clock
      error("stale release hunted, vy " .. tostring(ship.vy))
    end
    if sign ~= 0 then
      prev_sign = sign
    end
    if math.abs(ship.vy) > peak_vy then
      peak_vy = math.abs(ship.vy)
    end
  end
  os.clock = real_clock
  if min_rpm < anchor * 0.9 then
    error("stale release slammed rpm to " .. tostring(min_rpm))
  end
  if math.abs(ship.vy) > 0.5 then
    error("stale release did not settle, vy " .. tostring(ship.vy))
  end
end
stale_idle_then_release()

-- The live release learned a hover from a climb that was no longer
-- accelerating. That one sample became the stop command and the integer hold
-- kept the ship climbing. The recorded speeds are the ones that did it.
local function moving_release_keeps_rest_anchor()
  package.loaded.runtime = nil
  local runtime = require("runtime")
  local real_clock = os.clock
  local clock = 0
  os.clock = function()
    return clock
  end
  fresh_ship(78.23, 0)
  ship.dt = 0.30
  local holding = engine_tick.new_state()
  holding.mode = "idle"
  holding.job = nil
  holding.seeded = true
  holding.hover_rpm = 427
  holding.elev_scale = 1.058
  holding.elev_anchor = 427
  holding.elev_anchor_y = ship.y
  local sent = 427
  local devices = {
    rsc11 = {
      setTargetSpeed = function(rpm)
        sent = rpm
      end,
      getTargetSpeed = function()
        return sent
      end,
    },
  }
  local function once(command, fresh)
    clock = clock + 0.30
    local stepped
    holding, stepped = engine_tick.tick(holding, {
      ship = ship,
      command = command,
      su = 1,
      ready = true,
      stick_fresh = fresh == true,
      config = cfg,
      current_elevation_rpm = sent,
    })
    runtime.apply(stepped, devices)
    return stepped
  end
  for _ = 1, 8 do
    once(nil, false)
  end
  local rest = holding.elev_anchor
  if rest == nil then
    os.clock = real_clock
    error("release had no rest anchor")
  end
  ship.vy = 0.20
  once({ type = "stick", x = 0, y = 0, z = 1 }, true)
  local speeds = { 0.269, 0.337, 0.405, 0.474, 0.402, 0.331, 0.259, 0.187, 0.163, 0.139, 0.115, 0.091 }
  for _, vy in ipairs(speeds) do
    ship.y = ship.y + 0.08
    ship.vy = vy
    local stepped = once(nil, false)
    if vy > 0.15 and holding.elev_anchor ~= nil and holding.elev_anchor > rest + 4 then
      os.clock = real_clock
      error("moving release stored a climb as the hover, anchor " .. tostring(holding.elev_anchor))
    end
    if vy > 0.15 and stepped.rsc.rsc11 > rest + 4 then
      os.clock = real_clock
      error("moving release commanded the climb, rpm " .. tostring(stepped.rsc.rsc11))
    end
    if stepped.rsc.rsc11 < rest * 0.9 then
      os.clock = real_clock
      error("moving release slammed rpm to " .. tostring(stepped.rsc.rsc11))
    end
    if stepped.relays.relay6 == true then
      os.clock = real_clock
      error("moving release reversed elevation")
    end
  end
  os.clock = real_clock
end
moving_release_keeps_rest_anchor()

-- A short hop from rest. This hull hovers below the density curve, and the
-- elevation integer stays out for the shipped hold. Integrating that integer
-- (not a fresh command every nominal step) is what carries the ship past the
-- setpoint. The approach cap is left to the tick.
local function short_altitude(start_y, target, label, true_over_model)
  package.loaded.runtime = nil
  local runtime = require("runtime")
  local real_clock = os.clock
  local clock = 1000
  os.clock = function()
    return clock
  end
  local step = 0.30
  -- 1.4 is the harsh plant. 1/1.85 and 1/2.2 are the live ratios in this file.
  -- The anchor starts unset; the tick has to adopt the resting RPM itself.
  if true_over_model == nil or true_over_model <= 0 then
    true_over_model = 1 / 1.4
  end
  fresh_ship(start_y, 0)
  ship.dt = step
  local hover = density_hold(start_y) * true_over_model
  local state = engine_tick.new_state()
  state.mode = "semi"
  state.seeded = true
  state.hover_rpm = hover
  local sent = hover
  local devices = {
    rsc11 = {
      setTargetSpeed = function(rpm)
        sent = rpm
      end,
      getTargetSpeed = function()
        return sent
      end,
    },
  }
  local deadzone = cfg.altitude_deadzone
  local far = 0
  local wrong = 0
  local entered = false
  local left = false
  local reversed = false
  local biggest = 0
  local prev_sent = sent
  local grew = false
  local swing_peak = 0
  local swing_sign = 0
  local last_swing = nil
  local quiet_need = math.floor(20 / step)
  local quiet = 0
  -- Long enough that a slow hunt cannot hide behind an early sample.
  local steps = math.floor(240 / step)
  for i = 1, steps do
    clock = clock + step
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
      current_elevation_rpm = sent,
    })
    runtime.apply(stepped, devices)
    if stepped.relays.relay6 == true then
      reversed = true
    end
    local delta = math.abs(sent - prev_sent)
    if delta > biggest then
      biggest = delta
    end
    prev_sent = sent
    integrate_sent(sent, stepped.relays.relay6 == true, true_over_model, step)
    local past = ship.y - target
    local beyond = past
    if start_y > target then
      beyond = -past
    end
    if beyond > far then
      far = beyond
    end
    local away = 0
    if start_y < target then
      away = start_y - ship.y
    else
      away = ship.y - start_y
    end
    if away > wrong then
      wrong = away
    end
    local sign = 0
    if ship.vy > 0.05 then
      sign = 1
    elseif ship.vy < -0.05 then
      sign = -1
    end
    if sign ~= 0 then
      if swing_sign == 0 then
        swing_sign = sign
      elseif sign ~= swing_sign then
        -- Deadband chatter under the near-zero band is not a growing hunt.
        -- A swing that clears 0.15 and beats the previous peak is.
        if last_swing ~= nil and swing_peak > 0.15 and swing_peak > last_swing + 0.05 then
          grew = true
        end
        last_swing = swing_peak
        swing_peak = math.abs(ship.vy)
        swing_sign = sign
      end
    end
    if math.abs(ship.vy) > swing_peak then
      swing_peak = math.abs(ship.vy)
    end
    if math.abs(ship.y - target) <= deadzone then
      entered = true
    elseif entered then
      left = true
    end
    if entered and not left and math.abs(ship.y - target) <= deadzone and math.abs(ship.vy) < 0.15 then
      quiet = quiet + 1
    else
      quiet = 0
    end
  end
  os.clock = real_clock
  if reversed then
    error(label .. " reversed elevation")
  end
  if not entered or left or far > deadzone or wrong > deadzone then
    error(label .. " flew past the deadzone, far " .. tostring(far)
      .. " wrong " .. tostring(wrong)
      .. " y " .. tostring(ship.y) .. " vy " .. tostring(ship.vy)
      .. " entered " .. tostring(entered))
  end
  if grew then
    error(label .. " opposite swing grew, last " .. tostring(last_swing)
      .. " y " .. tostring(ship.y) .. " vy " .. tostring(ship.vy))
  end
  if quiet < quiet_need or math.abs(ship.y - target) > deadzone or math.abs(ship.vy) >= 0.15 then
    error(label .. " did not stay near zero, quiet " .. tostring(quiet)
      .. " y " .. tostring(ship.y) .. " vy " .. tostring(ship.vy))
  end
  if biggest >= 100 then
    error(label .. " stepped elevation by " .. tostring(biggest))
  end
  print(string.format("short altitude %s y=%.3f vy=%.3f far=%.3f step=%.0f quiet=%.0f",
    label, ship.y, ship.vy, far, biggest, quiet))
end

short_altitude(90, 102, "climb 12")
short_altitude(90, 82, "descent 8")
short_altitude(90, 102, "climb 12 ratio 1.85", 1 / 1.85)
short_altitude(90, 82, "descent 8 ratio 1.85", 1 / 1.85)
short_altitude(90, 102, "climb 12 ratio 2.2", 1 / 2.2)
short_altitude(90, 82, "descent 8 ratio 2.2", 1 / 2.2)

-- A climb toward 1000 keeps asking for an elevation integer the controller
-- has not reached. Counting only an open-loop ramp misses that chase.
local function cruise_elevation_writes()
  package.loaded.runtime = nil
  local runtime = require("runtime")
  local real_clock = os.clock
  local clock = 0
  os.clock = function()
    return clock
  end
  fresh_ship(120, 0)
  local state = engine_tick.new_state()
  state.mode = "auto"
  state.phase = "track"
  state.profile = "cruise"
  state.waypoint_x = 5000
  state.waypoint_z = 0
  state.altitude = 1000
  state.altitude_set = true
  state.hover_rpm = cfg.hover_equilibrium
  state.seeded = true
  local sent = cfg.hover_equilibrium
  local writes = 0
  local last_written = nil
  local first_write = true
  local devices = {
    rsc11 = {
      setTargetSpeed = function(rpm)
        if not first_write and rpm ~= 0 and last_written ~= nil
            and math.abs(rpm - last_written) >= 100 then
          error("cruise elevation step " .. tostring(rpm - last_written))
        end
        first_write = false
        last_written = rpm
        writes = writes + 1
        sent = rpm
      end,
      getTargetSpeed = function()
        return sent
      end,
    },
  }
  local window = 400
  local flags = {}
  local in_window = 0
  local max_window = 0
  local steps = 2000
  for i = 1, steps do
    clock = clock + 0.05
    local before = writes
    local stepped
    state, stepped = engine_tick.tick(state, {
      ship = ship,
      command = nil,
      su = 1,
      ready = true,
      stick_fresh = false,
      config = cfg,
      current_elevation_rpm = sent,
    })
    runtime.apply(stepped, devices)
    local wrote = 0
    if writes > before then
      wrote = 1
    end
    if i > window then
      in_window = in_window - (flags[i - window] or 0)
    end
    flags[i] = wrote
    in_window = in_window + wrote
    if i >= window and in_window > max_window then
      max_window = in_window
    end
    local net = elevation_accel(sent, stepped.relays.relay6 == true)
    ship.y = ship.y + ship.vy * 0.05 + 0.5 * net * 0.0025
    ship.vy = ship.vy + net * 0.05
  end
  os.clock = real_clock
  if max_window >= 128 then
    error("cruise climb called setTargetSpeed " .. tostring(max_window) .. " times in 400 applies")
  end
  if writes < 2 then
    error("cruise climb did not retarget elevation")
  end
  if ship.y <= 120 + cfg.altitude_deadzone then
    error("cruise climb did not start toward 1000, y " .. tostring(ship.y))
  end
  print(string.format(
    "cruise climb elevation writes window=%d total=%d y=%.3f",
    max_window, writes, ship.y
  ))
end

cruise_elevation_writes()
