package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local engine = require("engine_tick")
local config = require("config")

local function force(rpm)
  return (rpm < 0 and -1 or 1) * math.abs(rpm)^1.2
end
local function tick(bearing, yaw_rate)
  local state = engine.new_state()
  state.mode = "manual"
  state.bearing = bearing
  state.bearing_set = true
  return engine.tick(state, {
    ship = {x=0,y=62,z=0,vx=0,vy=0,vz=1,heading=0,
      pitch_rate=0,roll_rate=0,yaw_rate=yaw_rate,dt=.05},
    config = config.default(), ready = true, stick_fresh = true,
    current_elevation_rpm = 430, su = 0,
  })
end

local function torque(outputs)
  local r = outputs.rsc
  return force(r.rsc6)-force(r.rsc9)-force(r.rsc8)+force(r.rsc7)
end
local _, coasting = tick(0, .1)
if torque(coasting) >= 0 then error("heading deadband must still brake positive yaw velocity") end
local _, overshooting = tick(.01, .1)
if torque(overshooting) >= 0 then error("approaching heading must brake before overshoot") end
local _, reverse_spin = tick(0, -.1)
if torque(reverse_spin) <= 0 then error("yaw damping must oppose negative yaw velocity") end
local _, braking = tick(0)
local _, turning = tick(.5)
local function sway(outputs)
  local r = outputs.rsc
  return force(r.rsc6)+force(r.rsc8)-force(r.rsc7)-force(r.rsc9)
end
A.near(sway(turning), sway(braking), .0001, "bearing correction preserves lateral braking force")
local r = turning.rsc
if force(r.rsc6)-force(r.rsc9)-force(r.rsc8)+force(r.rsc7) <= 0 then
  error("combined command must still turn toward the bearing")
end

local _, outage_outputs, status = engine.tick(engine.new_state(), {
  ship = {x=0,y=62,z=0,vx=0,vy=0,vz=0,heading=0,
    pitch_rate=.4,roll_rate=-.4,dt=.05},
  config = config.default(), ready = true, current_elevation_rpm = 430, su = 0,
})
A.eq(status.outage, "port_bow", "corner outage detected")
A.eq(outage_outputs.relays.relay9, true, "opposite corner cut")
A.eq(outage_outputs.relays.relay6, false, "outage keeps surviving lift upward")

-- Debug-shell state can bypass protocol normalization. Huge finite angles
-- must not trap the flight loop in repeated subtraction.
local _, large_angle = tick(1e20)
for _, rpm in pairs(large_angle.rsc) do
  if rpm ~= rpm or math.abs(rpm) == math.huge then error("invalid large-angle output") end
end

local navigating = engine.new_state()
local nav_config = config.default()
nav_config.ship_mass = 1000000 -- Keep this force check below shaft saturation.
navigating.mode, navigating.phase = "auto", "track"
navigating.waypoint_x, navigating.waypoint_z = 1000, 0
local _, correcting = engine.tick(navigating, {
  ship={x=0,y=400,z=0,vx=0,vy=0,vz=1,forward_speed=0,side_speed=-1,
    forward={x=1,y=0,z=0},right={x=0,y=0,z=-1},heading=0,
    pitch_rate=0,roll_rate=0,yaw_rate=0,dt=.05},
  config=nav_config,ready=true,su=0,current_elevation_rpm=430,
})
local side_accel=sway(correcting)*100000/(256^1.2)/nav_config.ship_mass
A.near(side_accel,nav_config.side_accel,1e-8,"automatic side force realizes requested acceleration")
