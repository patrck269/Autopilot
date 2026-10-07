package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local engine_tick = require("engine_tick")
local command_ui = require("command_ui")
local command_status = require("command_status")
local protocol = require("protocol")
local shell_mod = require("shell")
local runtime = require("runtime")
local config = require("config")
local pid = require("pid")
local jobs = require("jobs")

local cfg = config.default()
local ship = {
  y = 100, x = 0, z = 0, vx = 0, vy = 0, vz = 0,
  pitch = 0, roll = 0, heading = 0, pitch_rate = 0, roll_rate = 0, dt = 0.05,
}

local density_gains = pid.calibrate(cfg.hover_equilibrium, 0.05)
local function density_hold(world_y)
  return pid.command(density_gains, 0, world_y, world_y, 0, 0.05)
end

local function elevation_accel(rpm, reverser, at_y)
  local specific = jobs.thrust(rpm, cfg.ship_mass) / cfg.ship_mass
  local reference = pid.air_density(pid.reference_y())
  local here = pid.air_density(at_y)
  if reference > 0 then
    specific = specific * (here / reference)
  end
  if reverser then
    return -(specific + 10)
  end
  return specific - 10
end

local function deliver(session, pending, message)
  if message == nil then
    return pending
  end
  return shell_mod.ingest(session, pending, message, protocol.keep, function() end)
end

local function heartbeat()
  return {
    type = "status",
    mode = "idle",
    altitude = 1,
    su = 1,
    speed = 0,
    horizontal_speed = 0,
  }
end

local function tick(state, command, hold_rpm, is_ready)
  return engine_tick.tick(state, {
    ship = ship,
    command = command,
    su = 1,
    ready = is_ready ~= false,
    stick_fresh = command ~= nil and command.type == "stick",
    config = cfg,
    current_elevation_rpm = hold_rpm,
  })
end

local function stand_in(outputs)
  local devices = {}
  local log = {}
  local function recorder(name)
    return {
      setTargetSpeed = function(rpm)
        log[#log + 1] = { kind = "rpm", name = name, rpm = rpm }
      end,
      setOutput = function(side, value)
        log[#log + 1] = { kind = "out", name = name, side = side, value = value }
      end,
      setAnalogOutput = function(side, value)
        log[#log + 1] = { kind = "analog", name = name, side = side, value = value }
      end,
    }
  end
  for name in pairs(outputs.rsc) do
    devices[name] = recorder(name)
  end
  for name in pairs(outputs.relays) do
    devices[name] = recorder(name)
  end
  return devices, log
end

local function apply_outputs(outputs)
  package.loaded.runtime = nil
  runtime = require("runtime")
  local devices, log = stand_in(outputs)
  runtime.apply(outputs, devices)
  return log
end

local function assert_zero(log, label)
  local saw_rpm = false
  local saw_relay6 = false
  for i = 1, #log do
    local item = log[i]
    if item.kind == "rpm" then
      saw_rpm = true
      if item.rpm ~= 0 then
        error(label .. " applied " .. item.name .. " rpm " .. tostring(item.rpm))
      end
    elseif item.kind == "analog" then
      if item.value ~= 0 then
        error(label .. " applied " .. item.name .. " analog " .. tostring(item.value))
      end
    elseif item.value == true then
      error(label .. " applied " .. item.name .. " on")
    end
    if item.name == "relay6" and item.kind == "out" then
      saw_relay6 = true
      A.eq(item.value, false, label .. " reverser")
    end
  end
  if not saw_rpm then
    error(label .. " applied no rotation speed")
  end
  if not saw_relay6 then
    error(label .. " did not write the elevation reverser")
  end
end

local function rpm_of(log, name)
  local found = nil
  for i = 1, #log do
    if log[i].kind == "rpm" and log[i].name == name then
      found = log[i].rpm
    end
  end
  return found
end

local hold_rpm = density_hold(ship.y)
local blocked_state, blocked_outputs = tick(engine_tick.new_state(), nil, hold_rpm, false)
A.eq(blocked_state.mode, "idle", "a missing peripheral leaves the boot mode")
assert_zero(apply_outputs(blocked_outputs), "not ready")
print("command center not-ready thrust=0")

local function fresh()
  ship.y = 100
  ship.vy = 0
  ship.vx = 0
  ship.vz = 0
  return engine_tick.new_state()
end

local function type_altitude(ui, session, pending, steps)
  local msg
  ui, msg = command_ui.key(ui, "y", true, false)
  pending = deliver(session, pending, msg)
  for i = 1, #steps do
    ui, msg = command_ui.key(ui, steps[i][1], true, steps[i][2] == true)
    pending = deliver(session, pending, msg)
    pending = deliver(session, pending, heartbeat())
  end
  return ui, pending, msg
end

local session = {}
local ui = command_ui.new()
local state = fresh()
state = tick(state, nil, hold_rpm, true)
local pending
ui, pending = type_altitude(ui, session, nil, {
  { "one", false },
  { "two", false },
  { "two", true },
  { "zero", false },
  { "enter", false },
})
A.eq(pending.type, "set_altitude", "idle entry")
A.eq(pending.y, 120, "idle typed altitude")
A.eq(ui.entered_altitude, 120, "the guide shows the typed altitude")
local outputs, status
state, outputs, status = tick(state, pending, hold_rpm, true)
A.eq(state.mode, "idle", "idle altitude stays idle")
A.eq(state.altitude, 120, "idle setpoint")
A.eq(ship.y, 100, "idle hull has not moved")
local shown = command_status.apply(status)
A.eq(shown.altitude, 120, "command computer shows the typed altitude")
A.eq(outputs.relays.relay6, false, "idle reverser off")
local idle_log = apply_outputs(outputs)
local idle_rpm = rpm_of(idle_log, "rsc11")
local idle_vy = elevation_accel(idle_rpm, false, ship.y) * 0.05
if idle_vy <= 0 then
  error("idle vertical output " .. tostring(idle_rpm) .. " did not climb")
end
print(string.format(
  "command center idle mode=%s setpoint=%.3f shown=%.3f y=%.3f vy=%.3f dir=1",
  state.mode, state.altitude, shown.altitude, ship.y, idle_vy
))

session = {}
ui = command_ui.new()
state = fresh()
state = tick(state, nil, hold_rpm, true)
ui, pending = type_altitude(ui, session, nil, {
  { "one", false },
  { "two", false },
  { "zero", false },
  { "numPadEnter", false },
})
local stick
ui, stick = command_ui.key(ui, "right", true, false)
pending = deliver(session, pending, stick)
pending = deliver(session, pending, heartbeat())
A.eq(pending.latched_altitude, 120, "a status does not drop the altitude on the stick")
state, outputs, status = tick(state, pending, hold_rpm, true)
A.eq(state.altitude, 120, "a stick keeps the altitude")
A.eq(state.stick.x, 1, "the held stick is applied")
A.eq(outputs.relays.relay6, false, "stick reverser off")
A.eq(ship.y, 100, "stick hull has not moved")
local stick_log = apply_outputs(outputs)
local stick_x = rpm_of(stick_log, "rsc10")
if stick_x == 0 or stick_x == nil then
  error("held stick did not fly")
end
local stick_vy = elevation_accel(rpm_of(stick_log, "rsc11"), false, ship.y) * 0.05
if stick_vy <= 0 then
  error("stick vertical output did not climb")
end
print(string.format(
  "command center stick setpoint=%.3f y=%.3f vy=%.3f dir=1 rpm10=%.0f",
  state.altitude, ship.y, stick_vy, stick_x
))

session = {}
ui = command_ui.new()
state = fresh()
state = tick(state, nil, hold_rpm, true)
local emergency
ui, emergency = command_ui.key(ui, "e", true, false)
pending = deliver(session, nil, emergency)
pending = deliver(session, pending, heartbeat())
A.eq(pending.type, "emergency", "a status does not drop emergency")
state, outputs = tick(state, pending, hold_rpm, true)
A.eq(state.emergency, true, "local emergency latches")
assert_zero(apply_outputs(outputs), "emergency")
state, outputs = tick(state, nil, hold_rpm, true)
A.eq(state.emergency, true, "emergency stays latched")
assert_zero(apply_outputs(outputs), "emergency hold")
local clear
ui, clear = command_ui.key(ui, "c", true, false)
pending = deliver(session, nil, clear)
state, outputs = tick(state, pending, hold_rpm, true)
A.eq(state.emergency, false, "clear releases the latch")
ui, pending = type_altitude(ui, session, nil, {
  { "eight", false },
  { "zero", false },
  { "enter", false },
})
state, outputs = tick(state, pending, hold_rpm, true)
A.eq(state.altitude, 80, "altitude after clear")
local cleared_vy = elevation_accel(rpm_of(apply_outputs(outputs), "rsc11"), false, ship.y) * 0.05
if cleared_vy >= 0 then
  error("cleared emergency did not descend, vy " .. tostring(cleared_vy))
end
print(string.format("command center emergency cleared setpoint=%.3f vy=%.3f dir=-1", state.altitude, cleared_vy))

session = {}
state = fresh()
state = tick(state, nil, hold_rpm, true)
pending = deliver(session, nil, { type = "set_altitude", y = 80 })
pending = deliver(session, pending, { type = "stick", x = 1, y = 0, z = 0 })
state, outputs = tick(state, pending, hold_rpm, true)
A.eq(state.altitude, 80, "a rednet stick keeps the altitude")
A.eq(state.stick.x, 1, "a rednet stick flies")
local remote_vy = elevation_accel(rpm_of(apply_outputs(outputs), "rsc11"), false, ship.y) * 0.05
if remote_vy >= 0 then
  error("rednet altitude did not descend")
end
pending = deliver(session, nil, { type = "emergency" })
state, outputs = tick(state, pending, hold_rpm, true)
A.eq(state.emergency, true, "rednet emergency latches")
assert_zero(apply_outputs(outputs), "rednet emergency")
state, outputs = tick(state, nil, hold_rpm, true)
assert_zero(apply_outputs(outputs), "rednet emergency hold")
pending = deliver(session, nil, { type = "clear_emergency" })
state = tick(state, pending, hold_rpm, true)
A.eq(state.emergency, false, "rednet clear releases the latch")
print(string.format("command center rednet setpoint=%.3f vy=%.3f dir=-1", 80, remote_vy))
