package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local engine = require("engine_tick")
local pid = require("pid")
local runtime = require("runtime")
local cfg = require("config").default()

local old_clock = os.clock
local now = 0
os.clock = function() return now end

local function hull(y, vy)
  return {
    x = 0, y = y, z = 0,
    vx = 0, vy = vy, vz = 0,
    forward_speed = 0, side_speed = 0,
    pitch = 0, roll = 0, heading = 0,
    pitch_rate = 0, roll_rate = 0, yaw_rate = 0,
    dt = 0.05,
  }
end

local function fly(state, vy, mass)
  now = now + 0.05
  return engine.tick(state, {
    ship = hull(120, vy),
    ready = true,
    config = cfg,
    ship_mass = mass,
    current_elevation_rpm = 800,
  })
end

local heavy = 32071065
local state = engine.new_state()
state.seeded = true
state.altitude = 400
state.altitude_set = true
state.job = "altitude"
state.hover_rpm = 430
state.pid_gains = pid.calibrate(430, 0.05)
for _ = 1, 10 do
  state = fly(state, 0, heavy)
end
A.eq(state.pid_gains.equilibrium, 430, "two seconds have not passed")
local jumped = false
for _ = 1, 50 do
  state = fly(state, 0, heavy)
  if state.lift_jump then
    jumped = true
  end
end
if state.pid_gains.equilibrium <= 430 then
  error("a grounded heavy hull kept the light-ship hover RPM")
end
A.eq(jumped, true, "the new hover RPM is one elevation write")
local raised = state.pid_gains.equilibrium
for _ = 1, 40 do
  state = fly(state, 1, heavy)
end
A.eq(state.pid_gains.equilibrium, raised, "a rising hull keeps the RPM that lifted it")
A.eq(state.lift_locked, true, "lift calibration locks after the hull rises")
print("heavy hull hover RPM rose from 430 to " .. tostring(raised))

local function yaw_at(mass)
  local fresh = engine.new_state()
  fresh.seeded = true
  fresh.bearing = 1
  fresh.bearing_set = true
  fresh.altitude = 120
  fresh.altitude_set = true
  fresh.job = "altitude"
  local _, outputs = engine.tick(fresh, {
    ship = hull(120, 0),
    ready = true,
    config = cfg,
    ship_mass = mass,
    current_elevation_rpm = 430,
  })
  return math.abs(outputs.rsc.rsc14 or 0)
end
local light = yaw_at(heavy)
local tuned = yaw_at(nil)
if light >= tuned then
  error("live mass did not reduce the RCS command, light " .. tostring(light) .. " tuned " .. tostring(tuned))
end
print("rcs at live mass " .. tostring(light) .. " versus tuned mass " .. tostring(tuned))

package.loaded.runtime = nil
runtime = require("runtime")
local sent = nil
local device = {
  getTargetSpeed = function() return sent or 0 end,
  setTargetSpeed = function(rpm) sent = rpm end,
}
runtime.apply({ rsc = { rsc16 = 100 }, relays = {} }, { rsc16 = device })
runtime.jump("rsc16")
runtime.apply({ rsc = { rsc16 = 5000 }, relays = {} }, { rsc16 = device })
A.eq(sent, 5000, "a lift jump writes the full elevation command")

os.clock = old_clock
