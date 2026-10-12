package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local engine_tick = require("engine_tick")
local protocol = require("protocol")
local config = require("config")
local monitors = require("monitors")
local speed = require("speed")

local cfg = config.default()

local function ship_at(y, vx)
  return {
    x = 0, y = y or 120, z = 0,
    vx = vx or 0, vy = 0, vz = 0,
    forward_speed = vx or 0, side_speed = 0,
    pitch = 0, roll = 0, heading = 0.4,
    pitch_rate = 0, roll_rate = 0, yaw_rate = 0,
    dt = 0.05,
  }
end

local function fresh()
  return engine_tick.new_state()
end

local function step(state, command, ship, stick_fresh)
  return engine_tick.tick(state, {
    ship = ship or ship_at(120, 0),
    command = command,
    ready = true,
    stick_fresh = stick_fresh == true,
    config = cfg,
    su = 1,
    current_elevation_rpm = 430,
  })
end

local state = fresh()
A.eq(state.mode, "semi", "fresh flight state is semi")
print("fresh flight state mode is semi")

for _, mode in ipairs({ "manual", "auto", "idle" }) do
  local rejected = protocol.validate({ type = "set_mode", mode = mode })
  A.eq(rejected, nil, "set_mode " .. mode .. " rejected")
  local next_state = step(fresh(), { type = "set_mode", mode = mode })
  A.eq(next_state.mode, "semi", "set_mode " .. mode .. " leaves semi")
  print("set_mode " .. mode .. " rejected and mode stays semi")
end

local stuck = step(fresh(), { type = "stick", x = 1, y = 0, z = 0 }, ship_at(120, 0), true)
A.eq(stuck.mode, "semi", "stick does not enter manual")
print("stick command stays semi and does not enter manual")

local emergency = step(fresh(), { type = "emergency" })
local cleared = step(emergency, { type = "clear_emergency" })
A.eq(cleared.emergency, false, "emergency cleared")
A.eq(cleared.outputs_disabled, false, "clear enables the props again")
A.eq(cleared.mode, "semi", "emergency clear returns to semi")
print("emergency clear returns to semi")

local _, dark = engine_tick.tick(fresh(), {
  ship = ship_at(120, 0),
  ready = true,
  config = cfg,
  su = 0,
  su_capacity = 0,
  current_elevation_rpm = 0,
})
if (dark.rsc.rsc16 or 0) == 0 then
  error("a stopped stressometer zeroed every controller")
end
print("stopped stressometer still commands elevation " .. tostring(dark.rsc.rsc16))

package.loaded.runtime = nil
local runtime = require("runtime")
local mix = require("mix")
local writes = 0
local sent = nil
local device = {
  getTargetSpeed = function()
    return 400
  end,
  setTargetSpeed = function(rpm)
    writes = writes + 1
    sent = rpm
  end,
}
local devices = {
  rsc16 = device,
  rsc17 = {
    getTargetSpeed = function() return 0 end,
    setTargetSpeed = function() end,
  },
}
runtime.apply(mix.zero(), devices)
runtime.apply(mix.zero(), devices)
A.eq(writes, 1, "a held emergency zero is not rewritten")
A.eq(sent, 0, "emergency stops elevation")
local restarted = cleared
restarted.hover_rpm = 430
restarted.altitude = 120
restarted.altitude_set = true
restarted.job = "altitude"
local _, flying = step(restarted, nil, ship_at(120, 0))
package.loaded.runtime = nil
local clean = require("runtime")
local expected = nil
clean.apply(flying, {
  rsc16 = { setTargetSpeed = function(rpm) expected = rpm end },
})
local stopped = {
  getTargetSpeed = function() return 0 end,
  setTargetSpeed = function(rpm) sent = rpm end,
}
runtime.relax()
runtime.apply(flying, { rsc16 = stopped })
A.eq(sent, expected, "cleared emergency restarts at the full elevation command")
if sent == nil or math.abs(sent) < 100 then
  error("cleared emergency left elevation at " .. tostring(sent))
end
local held = sent
runtime.apply(flying, { rsc16 = stopped })
A.eq(sent, held, "a lagging zero does not crawl the restarted elevation")
print("cleared emergency restarts elevation at " .. tostring(sent))

local jobs = require("jobs")
local function flown_accel(rpm)
  if rpm == nil or rpm == 0 then
    return 0
  end
  local magnitude = jobs.thrust(rpm, cfg.ship_mass) / cfg.ship_mass
  if rpm < 0 then
    return -magnitude
  end
  return magnitude
end

local function fly_speed(requested, start_vx)
  local state = fresh()
  local ship = ship_at(62, start_vx)
  local peak = math.abs(start_vx)
  state = step(state, { type = "set_speed", speed = requested }, ship)
  local capped = requested
  if capped > 35 then
    capped = 35
  elseif capped < -35 then
    capped = -35
  end
  A.eq(state.target_speed, capped, "speed target is capped at 35")
  A.eq(state.ramp_rate, (capped - start_vx) / 15, "speed ramp rate")
  for _ = 1, 800 do
    local outputs
    state, outputs = step(state, nil, ship)
    ship.vx = ship.vx + flown_accel(outputs.rsc.rsc17) * ship.dt
    ship.forward_speed = ship.vx
    if math.abs(ship.vx) > peak then
      peak = math.abs(ship.vx)
    end
    if math.abs(ship.vx) > 35 then
      error("flown speed exceeded 35 for target " .. tostring(requested) .. ", vx " .. tostring(ship.vx))
    end
  end
  return state, peak
end

local current = 0
local target = 30
local ramped = fly_speed(target, current)
A.eq(ramped.mode, "semi", "speed setpoint stays semi")
print(string.format(
  "speed ramp rate %s = (%s - %s) / 15 and flown speed stays within 35",
  tostring(ramped.ramp_rate), tostring(target), tostring(current)
))

local _, peak_fast = fly_speed(80, 0)
local _, peak_back = fly_speed(-80, 0)
local _, peak_near = fly_speed(36, 0)
if peak_fast < 34 or peak_back < 34 or peak_near < 34 then
  error("capped speed did not approach 35, peaks " .. tostring(peak_fast) .. " " .. tostring(peak_back) .. " " .. tostring(peak_near))
end
print(string.format(
  "flown speed for targets 80, -80, and 36 peaked at %s %s %s and stayed within 35",
  tostring(peak_fast), tostring(peak_back), tostring(peak_near)
))

local climbed = step(fresh(), { type = "set_altitude", y = 250 })
A.eq(climbed.altitude, 250, "altitude setpoint")
A.eq(climbed.mode, "semi", "altitude stays semi")
local aimed = step(climbed, { type = "set_bearing", bearing = 1.2 })
A.eq(aimed.bearing, 1.2, "bearing setpoint")
A.eq(aimed.mode, "semi", "bearing stays semi")
local on_heading = ship_at(120, 0)
on_heading.heading = 1.2
on_heading.yaw_rate = 1e-8
local _, quiet = step(fresh(), { type = "set_bearing", bearing = 1.2 }, on_heading)
for _, name in ipairs({ "rsc12", "rsc13", "rsc14", "rsc15" }) do
  A.eq(quiet.rsc[name] or 0, 0, "bearing deadzone leaves " .. name .. " alone")
end
local off_heading = ship_at(120, 0)
off_heading.heading = 0
off_heading.yaw_rate = 0
local _, turning = step(fresh(), { type = "set_bearing", bearing = 0.5 }, off_heading)
if (turning.rsc.rsc14 or 0) <= 0.01 or (turning.rsc.rsc15 or 0) <= 0.01 then
  error("a real bearing error did not command the pullers")
end
print("bearing deadzone drops sub-0.01 rpm and a real error still pulls")
local reversed = step(aimed, { type = "set_speed", speed = -12 }, ship_at(120, 0))
A.eq(reversed.target_speed, -12, "reverse thrust setpoint")
A.eq(reversed.ramp_rate, speed.ramp_rate(0, -12), "reverse ramp")
A.eq(reversed.mode, "semi", "reverse stays semi")
print("altitude bearing and reverse thrust stick while mode stays semi")

local function lateral(stick_y)
  return step(fresh(), { type = "stick", x = 0, y = stick_y, z = 0 }, ship_at(120, 0), true)
end

local starboard_state, starboard = lateral(1)
A.eq(starboard_state.mode, "semi", "starboard demand stays semi")
if not (starboard.rsc.rsc14 > 0 and starboard.rsc.rsc12 > 0) then
  error("starboard pullers 14 and 12 were not positive")
end
if (starboard.rsc.rsc13 or 0) > 0 or (starboard.rsc.rsc15 or 0) > 0 then
  error("starboard command wrote a port pull")
end
print(string.format(
  "starboard lateral rsc14=%s rsc12=%s rsc13=%s rsc15=%s",
  tostring(starboard.rsc.rsc14), tostring(starboard.rsc.rsc12),
  tostring(starboard.rsc.rsc13), tostring(starboard.rsc.rsc15)
))

local port_state, port = lateral(-1)
A.eq(port_state.mode, "semi", "port demand stays semi")
if not (port.rsc.rsc13 > 0 and port.rsc.rsc15 > 0) then
  error("port pullers 13 and 15 were not positive")
end
if (port.rsc.rsc14 or 0) > 0 or (port.rsc.rsc12 or 0) > 0 then
  error("port command wrote a starboard pull")
end
print(string.format(
  "port lateral rsc13=%s rsc15=%s rsc14=%s rsc12=%s",
  tostring(port.rsc.rsc13), tostring(port.rsc.rsc15),
  tostring(port.rsc.rsc14), tostring(port.rsc.rsc12)
))

local _, thrust = step(fresh(), { type = "set_speed", speed = 10 })
A.eq(thrust.rsc.rsc17 ~= nil, true, "forward command is on controller 17")
A.eq(thrust.rsc.rsc16 ~= nil, true, "elevation command is on controller 16")
for i = 2, 11 do
  if thrust.rsc["rsc" .. i] ~= nil then
    error("controller " .. i .. " was commanded")
  end
end
print("forward is controller 17 and elevation is controller 16; controllers 2-11 are absent")

local required = config.required_names(cfg)
for _, name in ipairs(required) do
  local number = tonumber(string.match(name, "^rsc(%d+)$"))
  if number ~= nil and number >= 2 and number <= 11 then
    error("startup still requires controller " .. tostring(number))
  end
  if string.sub(name, 1, 5) == "relay" then
    error("startup still requires " .. name)
  end
end
A.eq(cfg.names.speedometer, "Create_Speedometer_1", "speedometer 1")
A.eq(cfg.names.stressometer, "Create_Stressometer_2", "stressometer 2")
print("startup does not require controllers 2-11 or the old relays")
print("speedometer 1 is elevation rpm and stressometer 2 is main engine stress")

local discovered = {}
for i = 1, 7 do
  discovered[i] = { name = "monitor_" .. i, w = 40, h = 20 }
end
local pages = monitors.assign(discovered)
A.eq(pages.monitor_4, "Flight", "monitor 4")
A.eq(pages.monitor_5, "Navigation", "monitor 5")
A.eq(pages.monitor_6, "Engines", "monitor 6")
A.eq(pages.monitor_7, "Emergency", "monitor 7")
A.eq(pages.monitor_1, nil, "monitor 1 unbound")
A.eq(pages.monitor_2, nil, "monitor 2 unbound")
A.eq(pages.monitor_3, nil, "monitor 3 unbound")
print("command pages bound only to monitor_4 monitor_5 monitor_6 monitor_7")

local pocket_program = io.open("programs/pocket.lua", "rb")
local pocket_ui = io.open("src/pocket_ui.lua", "rb")
local pocket_install = io.open("install/pocket.lua", "rb")
A.eq(pocket_program, nil, "pocket program removed")
A.eq(pocket_ui, nil, "pocket ui removed")
A.eq(pocket_install, nil, "pocket installer removed")
print("pocket program pocket ui and pocket installer are not flight entry points")

local again = engine_tick.new_state()
A.eq(again.mode, "semi", "a new flight state loaded from the command flight module is semi")
print("command flight module fresh state is semi")

local engine_source = io.open("programs/engine.lua", "rb")
local engine_text = engine_source:read("a")
engine_source:close()
if engine_text:find("engine_tick", 1, true) or engine_text:find("runtime.apply", 1, true) then
  error("engine program still flies")
end
print("engine program does not run the flight loop")

A.eq(protocol.validate({ type = "return_to_user", x = 1, z = 2 }), nil, "return_to_user rejected")
local returned = step(fresh(), { type = "return_to_user", x = 10, z = 20 })
A.eq(returned.mode, "semi", "return_to_user stays semi")
A.eq(returned.waypoint_x, nil, "return_to_user does not start navigation")
print("return_to_user does not start navigation or leave semi")
