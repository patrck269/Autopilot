package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local engine, config = require("engine_tick"), require("config")
local cfg = config.default()
local old_clock = os.clock
local function force(rpm)
  return (rpm < 0 and -1 or 1)*100000*(math.abs(rpm)/256)^1.2
end
local ok, failure = pcall(function()
  for _, initial in ipairs({-.5, .5, 2}) do
    package.loaded.runtime = nil
    local runtime = require("runtime")
    local heading, rate, now = initial, .03, 0
    os.clock = function() return now end
    local actual, devices = {}, {}
    for _, name in ipairs({"rsc6","rsc7","rsc8","rsc9","rsc10","rsc11"}) do
      actual[name] = name == "rsc11" and 430 or 0
      devices[name] = {getTargetSpeed=function() return actual[name] end,
        setTargetSpeed=function(rpm) actual[name]=rpm end}
    end
    local state = engine.new_state()
    state.mode, state.bearing, state.bearing_set = "manual", 0, true
    for i=1,12000 do
      now = i*.05
      local outputs
      state, outputs = engine.tick(state, {
        ship={x=0,y=62,z=0,vx=0,vy=0,vz=0,forward_speed=0,side_speed=0,
          heading=heading,yaw_rate=rate,pitch_rate=0,roll_rate=0,dt=.05},
        config=cfg,ready=true,su=0,stick_fresh=true,current_elevation_rpm=430,
      })
      runtime.apply(outputs,devices,{budget=require("stress").USABLE})
      local torque = force(actual.rsc6)-force(actual.rsc9)-force(actual.rsc8)+force(actual.rsc7)
      rate = rate + torque*8/(cfg.ship_mass*400)*.05
      heading = heading + rate*.05
    end
    A.near(heading,0,.021,"bearing settles with held actuator targets")
    A.near(rate,0,.001,"yaw momentum settles with held actuator targets")
  end
end)
os.clock=old_clock
if not ok then error(failure) end
