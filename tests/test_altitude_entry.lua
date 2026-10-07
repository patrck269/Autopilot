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

-- Keys, then the flight loop's rednet intake, then one flight tick from rest.
-- A stick press, repeat, or release after the altitude must not erase it.
local function altitude_entry(label, mode_key, mode_name, altitude_steps, typed, start_y, stick_steps, stick_x, rest_ratio)
  if math.abs(typed - start_y) <= cfg.altitude_deadzone then
    error(label .. " is inside the deadzone")
  end
  fresh_ship(start_y)
  local hold_rpm = density_hold(start_y)
  if type(rest_ratio) == "number" then
    hold_rpm = hold_rpm * rest_ratio
  end
  local ui = command_ui.new()
  local session = {}
  local msg
  ui, msg = command_ui.key(ui, mode_key, true, false)
  local pending = deliver(session, nil, msg)
  local state, outputs, status = tick(engine_tick.new_state(), pending, hold_rpm)
  A.eq(state.mode, mode_name, label .. " rests in " .. mode_name)
  A.eq(ship.y, start_y, label .. " has not moved")
  A.eq(ship.vy, 0, label .. " is at rest")

  pending = nil
  ui, msg = command_ui.key(ui, "y", true, false)
  for i = 1, #altitude_steps do
    local step = altitude_steps[i]
    ui, msg = command_ui.key(ui, step[1], true, step[2] == true)
    pending = deliver(session, pending, msg)
  end
  A.eq(msg.type, "set_altitude", label .. " entry")
  A.eq(msg.y, typed, label .. " typed altitude")

  for i = 1, #stick_steps do
    local step = stick_steps[i]
    ui, msg = command_ui.key(ui, step[1], step[2] ~= false, step[3] == true)
    pending = deliver(session, pending, msg)
  end

  state, outputs, status = tick(state, pending, hold_rpm)
  A.eq(state.altitude, typed, label .. " setpoint is the typed altitude")
  A.eq(state.altitude_set, true, label .. " altitude stays armed")
  A.eq(ui.entered_altitude, typed, label .. " command computer keeps the typed altitude")
  A.eq(ship.y, start_y, label .. " hull is still at the old height")
  local shown = command_status.apply(status)
  if shown == nil then
    error(label .. " produced no command-computer altitude")
  end
  A.eq(shown.altitude, typed, label .. " command computer shows the typed altitude")
  local typed_text = string.format("%.0f", typed)
  A.eq(string.find(shown.line, typed_text, 1, true) ~= nil, true, label .. " alt line shows " .. typed_text)
  A.eq(outputs.relays.relay6, false, label .. " reverser stays off")
  A.eq(state.stick.x, stick_x, label .. " stick")
  if stick_x == 0 then
    A.eq(state.stick.y, 0, label .. " released stick y")
    A.eq(state.stick.z, 0, label .. " released stick z")
  else
    if outputs.rsc.rsc10 == 0 then
      error(label .. " held stick did not fly")
    end
  end

  local vy
  local direction = 1
  if type(rest_ratio) == "number" then
    if state.elev_anchor == nil or state.elev_anchor <= 0 then
      error(label .. " did not adopt the rpm that was holding the ship")
    end
    A.near(state.elev_anchor, hold_rpm, 1e-3, label .. " anchor")
    local ratio = outputs.rsc.rsc11 / state.elev_anchor
    vy = (10 * (ratio ^ 1.2) - 10) * 0.05
    if vy * (typed - start_y) <= 0 then
      error(label .. " elevation rpm " .. tostring(outputs.rsc.rsc11)
        .. " did not start toward " .. tostring(typed) .. " from " .. tostring(state.elev_anchor))
    end
  else
    vy = elevation_accel(outputs.rsc.rsc11, outputs.relays.relay6 == true) * 0.05
    if vy * (typed - start_y) <= 0 then
      error(label .. " vertical speed " .. tostring(vy) .. " did not start toward " .. tostring(typed))
    end
  end
  if vy < 0 then
    direction = -1
  end
  print(string.format(
    "altitude entry %s setpoint=%.0f shown=%.0f y=%.3f vy=%.3f dir=%.0f",
    label, state.altitude, shown.altitude, ship.y, vy, direction
  ))
  if type(rest_ratio) == "number" then
    local repeat_msg
    ui, repeat_msg = command_ui.key(ui, "right", true, true)
    local repeated = deliver(session, nil, repeat_msg)
    local again
    state, again = tick(state, repeated, hold_rpm + 40)
    A.eq(state.altitude, typed, label .. " later stick left the altitude")
    A.near(state.elev_anchor, hold_rpm, 1e-3, label .. " later stick left the anchor")
    A.eq(again.relays.relay6, false, label .. " later stick left the reverser off")
  end
end

altitude_entry("manual press", "m", "manual", {
  { "one", false },
  { "two", false },
  { "two", true },
  { "zero", false },
  { "enter", false },
}, 120, 100, { { "right", true, false } }, 1)

altitude_entry("semi repeat", "s", "semi", {
  { "numPad1", false },
  { "numPad2", false },
  { "numPad2", true },
  { "numPad0", false },
  { "numPadEnter", false },
}, 120, 100, { { "right", true, false }, { "right", true, true } }, 1)

altitude_entry("auto release", "u", "auto", {
  { "eight", false },
  { "zero", false },
  { "zero", true },
  { "enter", false },
}, 80, 100, { { "right", true, false }, { "right", false, false } }, 0)

altitude_entry("manual quiet", "m", "manual", {
  { "one", false },
  { "two", false },
  { "zero", false },
  { "enter", false },
}, 120, 100, {}, 0)

altitude_entry("manual short", "m", "manual", {
  { "one", false },
  { "one", false },
  { "one", true },
  { "two", false },
  { "enter", false },
}, 112, 100, { { "right", true, false } }, 1, 1 / 1.85)
