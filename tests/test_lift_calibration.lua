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
state.elev_anchor = 500
state.elev_anchor_y = 120
local jumped = false
local climb_rpm = 0
for _ = 1, 50 do
  local outputs
  state, outputs = fly(state, 0, heavy)
  if state.lift_jump then
    jumped = true
    climb_rpm = outputs.rsc.rsc16 or 0
  end
end
if state.pid_gains.equilibrium <= 430 then
  error("a grounded heavy hull kept the light-ship hover RPM")
end
A.eq(jumped, true, "the new hover RPM is one elevation write")
if climb_rpm < 1000 then
  error("a grounded climb stayed at " .. tostring(climb_rpm))
end
local raised = state.pid_gains.equilibrium
print("heavy hull hover RPM rose from 430 to " .. tostring(raised))
state.altitude = 100
local trimmed = false
for _ = 1, 50 do
  state = fly(state, 1, heavy)
  if state.pid_gains.equilibrium < raised then
    trimmed = true
  end
end
A.eq(trimmed, true, "a hull above its altitude and still climbing lowers the hover RPM")
print("hover RPM trimmed from " .. tostring(raised) .. " to " .. tostring(state.pid_gains.equilibrium))
state.pid_gains = pid.calibrate(raised, 0.05)

state.bearing = 1
state.bearing_set = true
local _, scaled = engine.tick(state, {
  ship = hull(120, 1),
  ready = true,
  config = cfg,
  ship_mass = heavy,
  current_elevation_rpm = 800,
})
local fresh = engine.new_state()
fresh.seeded = true
fresh.bearing = 1
fresh.bearing_set = true
fresh.altitude = 120
fresh.altitude_set = true
fresh.job = "altitude"
local _, unscaled = engine.tick(fresh, {
  ship = hull(120, 0),
  ready = true,
  config = cfg,
  ship_mass = heavy,
  current_elevation_rpm = 430,
})
local scaled_yaw = math.abs(scaled.rsc.rsc14 or 0)
local base_yaw = math.abs(unscaled.rsc.rsc14 or 0)
A.eq(scaled_yaw, 2500, "a right turn caps bow starboard at 2500")
A.eq(math.abs(scaled.rsc.rsc15 or 0), 2500, "a right turn caps stern port at 2500")
A.eq(scaled.rsc.rsc13 or 0, 0, "a right turn leaves bow port off")
A.eq(scaled.rsc.rsc12 or 0, 0, "a right turn leaves stern starboard off")
A.eq(base_yaw, 2500, "the uncapped yaw law is held at 2500")
if math.abs(scaled.rsc.rsc16 or 0) == 1000 and math.abs(scaled.rsc.rsc17 or 0) == 1000 then
  error("the rcs cap also limited elevation and the rear thrusters")
end
print("clockwork yaw capped at " .. tostring(scaled_yaw))

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
