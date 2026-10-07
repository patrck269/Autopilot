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
A.near(msg.bearing, math.pi, 1e-9, "180 degrees is a half turn")

state = command_ui.new()
state, msg = command_ui.key(state, "y", true, false)
state, msg = command_ui.key(state, "numPad1", true, false)
state, msg = command_ui.key(state, "numPad2", true, false)
state, msg = command_ui.key(state, "numPad2", true, true)
state, msg = command_ui.key(state, "numPad0", true, false)
state, msg = command_ui.key(state, "numPadEnter", true, false)
A.eq(msg.type, "set_altitude", "numpad altitude")
A.eq(msg.y, 120, "numpad altitude value")
state, msg = command_ui.key(state, "numPadEnter", true, true)
A.eq(msg, nil, "a repeated enter does not replace the altitude")
A.eq(state.entered_altitude, 120, "the entered altitude stays on the command computer")
state, msg = command_ui.key(state, "k", true, false)
A.eq(state.entered_altitude, nil, "cancel clears the entered altitude")

state = command_ui.new()
state, msg = command_ui.key(state, "y", true, false)
state, msg = command_ui.key(state, "minus", true, false)
state, msg = command_ui.key(state, "one", true, false)
state, msg = command_ui.key(state, "period", true, false)
state, msg = command_ui.key(state, "five", true, false)
state, msg = command_ui.key(state, "enter", true, false)
A.eq(msg.type, "set_altitude", "signed altitude")
A.eq(msg.y, -1.5, "minus and period")

state = command_ui.new()
state, msg = command_ui.key(state, "y", true, false)
state, msg = command_ui.key(state, "numPadSubtract", true, false)
state, msg = command_ui.key(state, "numPad8", true, false)
state, msg = command_ui.key(state, "numPadDecimal", true, false)
state, msg = command_ui.key(state, "numPad0", true, false)
state, msg = command_ui.key(state, "numPadEnter", true, false)
A.eq(msg.y, -8, "numpad minus and decimal")

local engine_tick = require("engine_tick")
local protocol = require("protocol")
local shell_mod = require("shell")
local command_status = require("command_status")
local config = require("config")

local function deliver(pending, message)
  if message == nil then
    return pending
  end
  return shell_mod.ingest({}, pending, message, protocol.keep, function() end)
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

local function press(ui, pending, name)
  local message
  ui, message = command_ui.key(ui, name, true, false)
  pending = deliver(pending, message)
  pending = deliver(pending, heartbeat())
  return ui, pending, message
end

local cfg = config.default()
local ship = {
  y = 100, x = 0, z = 0, vx = 0, vy = 0, vz = 0,
  pitch = 0, roll = 0, heading = 0,
  pitch_rate = 0, roll_rate = 0, dt = 0.05,
}

local function fly(command, fresh_stick)
  local flown, outputs, flight_status = engine_tick.tick(engine_tick.new_state(), {
    ship = ship,
    command = command,
    su = 1,
    ready = true,
    stick_fresh = fresh_stick == true,
    config = cfg,
    current_elevation_rpm = cfg.hover_equilibrium,
  })
  return flown, outputs, flight_status
end

local ui = command_ui.new()
local pending
ui, pending = press(ui, nil, "y")
A.eq(ui.field, "y", "altitude entry is open")
A.eq(ui.buffer, "", "the guide shows an empty altitude")
ui, pending = press(ui, pending, "one")
ui, pending = press(ui, pending, "two")
ui, pending = press(ui, pending, "zero")
A.eq(ui.buffer, "120", "the guide shows the typed altitude")
ui, pending = press(ui, pending, "enter")
A.eq(ui.entered_altitude, 120, "the guide keeps the entered altitude")
A.eq(pending.type, "set_altitude", "a status heartbeat does not drop the altitude")
A.eq(pending.y, 120, "the setpoint survives the heartbeat")
local flown, outputs, flight_status = fly(pending, false)
A.eq(flown.mode, "idle", "an idle altitude stays idle")
A.eq(flown.altitude, 120, "the idle setpoint is the typed altitude")
A.eq(outputs.relays.relay6, false, "the idle climb leaves the reverser off")
if flown.altitude - ship.y <= 8 then
  error("the idle change was inside the deadzone")
end
local shown = command_status.apply(flight_status)
A.eq(shown.altitude, 120, "the guide shows the flown altitude")

ui = command_ui.new()
pending = nil
ui, pending = press(ui, pending, "y")
ui, pending = press(ui, pending, "one")
ui, pending = press(ui, pending, "two")
ui, pending = press(ui, pending, "zero")
ui, pending = press(ui, pending, "numPadEnter")
local stick
ui, stick = command_ui.key(ui, "right", true, false)
pending = deliver(pending, stick)
pending = deliver(pending, heartbeat())
A.eq(pending.type, "stick", "a status heartbeat does not replace the stick")
A.eq(pending.latched_altitude, 120, "a stick before the tick keeps the altitude")
flown, outputs = fly(pending, true)
A.eq(flown.altitude, 120, "the tick keeps the altitude")
A.eq(flown.mode, "manual", "a held stick may select manual")
A.eq(flown.stick.x, 1, "a held stick may fly")
A.eq(outputs.relays.relay6, false, "the stick leaves the reverser off")

ui = command_ui.new()
pending = nil
ui, pending = press(ui, pending, "e")
A.eq(pending.type, "emergency", "a status heartbeat does not drop emergency")
flown, outputs = fly(pending, false)
A.eq(flown.emergency, true, "emergency latches")
A.eq(outputs.rsc.rsc11, 0, "emergency holds zero thrust")
A.eq(outputs.relays.relay6, false, "emergency leaves the reverser off")
