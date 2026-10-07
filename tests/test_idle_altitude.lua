package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local engine_tick = require("engine_tick")
local command_ui = require("command_ui")
local command_status = require("command_status")
local protocol = require("protocol")
local shell_mod = require("shell")
local config = require("config")
local pid = require("pid")
local jobs = require("jobs")

local cfg = config.default()
local ship = {
  y = 100, x = 0, z = 0, vx = 0, vy = 0, vz = 0,
  pitch = 0, roll = 0, heading = 0, pitch_rate = 0, roll_rate = 0, dt = 0.05,
}

local function fresh_ship(y)
  ship.x = 0
  ship.y = y
  ship.z = 0
  ship.vx = 0
  ship.vy = 0
  ship.vz = 0
  ship.pitch = 0
  ship.roll = 0
  ship.heading = 0
  ship.pitch_rate = 0
  ship.roll_rate = 0
  ship.dt = 0.05
end

local density_gains = pid.calibrate(cfg.hover_equilibrium, 0.05)
local function density_hold(world_y)
  return pid.command(density_gains, 0, world_y, world_y, 0, 0.05)
end

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

local function deliver(session, pending, message)
  if message == nil then
    return pending
  end
  return shell_mod.ingest(session, pending, message, protocol.keep, function() end)
end

local function tick(state, command, hold_rpm)
  return engine_tick.tick(state, {
    ship = ship,
    command = command,
    su = 1,
    ready = true,
    stick_fresh = command ~= nil and command.type == "stick",
    config = cfg,
    current_elevation_rpm = hold_rpm,
  })
end

local function send_key(ui, session, pending, name, down, held)
  local msg
  ui, msg = command_ui.key(ui, name, down ~= false, held == true)
  pending = deliver(session, pending, msg)
  return ui, pending, msg
end

-- Keys, the flight loop's rednet intake, then one tick. Idle is the boot mode
-- and the mode a cancel returns to. A stick may leave idle; the altitude stays.
local function idle_altitude(label, steps, typed, start_y, stick_steps, stick_x, via_cancel, expect_idle)
  if math.abs(typed - start_y) <= cfg.altitude_deadzone then
    error(label .. " is inside the deadzone")
  end
  fresh_ship(start_y)
  local hold_rpm = density_hold(start_y)
  local ui = command_ui.new()
  local session = {}
  local state = engine_tick.new_state()
  local outputs, status, msg, pending
  state, outputs, status = tick(state, nil, hold_rpm)
  A.eq(state.mode, "idle", label .. " boots in idle")
  A.eq(ship.vy, 0, label .. " boots at rest")

  if via_cancel then
    ui, pending, msg = send_key(ui, session, nil, "u", true, false)
    state, outputs, status = tick(state, pending, hold_rpm)
    A.eq(state.mode, "auto", label .. " leaves idle")
    ui, pending, msg = send_key(ui, session, nil, "k", true, false)
    A.eq(msg.type, "cancel_jobs", label .. " cancel")
    state, outputs, status = tick(state, pending, hold_rpm)
    A.eq(state.mode, "idle", label .. " cancel returns to idle")
    A.eq(state.altitude_set, false, label .. " cancel clears the armed altitude")
    A.eq(ship.y, start_y, label .. " cancel has not moved the hull")
  end

  pending = nil
  ui, pending, msg = send_key(ui, session, pending, "y", true, false)
  for i = 1, #steps do
    ui, pending, msg = send_key(ui, session, pending, steps[i][1], true, steps[i][2] == true)
  end
  A.eq(msg.type, "set_altitude", label .. " entry")
  A.eq(msg.y, typed, label .. " typed altitude")

  for i = 1, #stick_steps do
    local step = stick_steps[i]
    ui, pending, msg = send_key(ui, session, pending, step[1], step[2] ~= false, step[3] == true)
  end

  state, outputs, status = tick(state, pending, hold_rpm)
  A.eq(state.altitude, typed, label .. " setpoint is the typed altitude")
  A.eq(state.altitude_set, true, label .. " altitude stays armed")
  A.eq(state.job, "altitude", label .. " tracks the altitude")
  if expect_idle then
    A.eq(state.mode, "idle", label .. " stays idle")
  end
  A.eq(ui.entered_altitude, typed, label .. " command computer keeps the typed altitude")
  A.eq(ship.y, start_y, label .. " hull is still at the old height")
  local shown = command_status.apply(status)
  if shown == nil then
    error(label .. " produced no command-computer altitude")
  end
  A.eq(shown.altitude, typed, label .. " command computer shows the typed altitude")
  A.eq(string.find(shown.line, tostring(typed), 1, true) ~= nil, true, label .. " alt line")
  A.eq(outputs.relays.relay6, false, label .. " reverser stays off")
  A.eq(state.stick.x, stick_x, label .. " stick")
  if stick_x == 0 then
    A.eq(state.stick.y, 0, label .. " stick y")
    A.eq(state.stick.z, 0, label .. " stick z")
  else
    if outputs.rsc.rsc10 == 0 then
      error(label .. " held stick did not fly")
    end
  end

  local vy = elevation_accel(outputs.rsc.rsc11, outputs.relays.relay6 == true) * 0.05
  if vy * (typed - start_y) <= 0 then
    error(label .. " vertical speed " .. tostring(vy) .. " did not start toward " .. tostring(typed))
  end
  local direction = 1
  if vy < 0 then
    direction = -1
  end
  print(string.format(
    "idle altitude %s mode=%s setpoint=%.3f shown=%.3f y=%.3f vy=%.3f dir=%.0f",
    label, state.mode, state.altitude, shown.altitude, ship.y, vy, direction
  ))
end

idle_altitude("boot word", {
  { "one", false },
  { "two", false },
  { "two", true },
  { "zero", false },
  { "enter", false },
}, 120, 100, {}, 0, false, true)

idle_altitude("boot numpad", {
  { "numPad8", false },
  { "numPad0", false },
  { "numPad0", true },
  { "numPadEnter", false },
}, 80, 100, {}, 0, false, true)

idle_altitude("boot decimal", {
  { "one", false },
  { "two", false },
  { "zero", false },
  { "period", false },
  { "five", false },
  { "enter", false },
}, 120.5, 100, {}, 0, false, true)

idle_altitude("boot minus", {
  { "numPadSubtract", false },
  { "five", false },
  { "zero", false },
  { "numPadEnter", false },
}, -50, 100, {}, 0, false, true)

idle_altitude("boot press", {
  { "one", false },
  { "two", false },
  { "zero", false },
  { "enter", false },
}, 120, 100, { { "right", true, false } }, 1, false, false)

idle_altitude("boot repeat", {
  { "numPad1", false },
  { "numPad2", false },
  { "numPad0", false },
  { "numPadEnter", false },
}, 120, 100, { { "right", true, false }, { "right", true, true } }, 1, false, false)

idle_altitude("boot release", {
  { "eight", false },
  { "zero", false },
  { "enter", false },
}, 80, 100, { { "right", true, false }, { "right", false, false } }, 0, false, false)

idle_altitude("cancel word", {
  { "one", false },
  { "two", false },
  { "two", true },
  { "zero", false },
  { "enter", false },
}, 120, 100, {}, 0, true, true)

idle_altitude("cancel press", {
  { "numPad8", false },
  { "numPad0", false },
  { "numPadEnter", false },
}, 80, 100, { { "right", true, false } }, 1, true, false)
