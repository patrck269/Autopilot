package.path="src/?.lua;"..package.path
local engine, config, pid, stress = require("engine_tick"), require("config"), require("pid"), require("stress")
local cfg = config.default()
local old_clock = os.clock
local function force(rpm)
  return (rpm<0 and -1 or 1)*100000*(math.abs(rpm)/256)^1.2
end
local ok, failure = pcall(function()
  for _, initial_heading in ipairs({0,math.pi/2,math.pi,-math.pi/2}) do
    package.loaded.runtime=nil
    local runtime=require("runtime")
    local x,z,vx,vz,heading,rate,now=0,0,0,0,initial_heading,0,0
    os.clock=function() return now end
    local actual,devices={},{}
    for _,name in ipairs({"rsc6","rsc7","rsc8","rsc9","rsc10","rsc11"}) do
      actual[name]=name=="rsc11" and 430*pid.thrust_scale(400) or 0
      devices[name]={getTargetSpeed=function() return actual[name] end,
        setTargetSpeed=function(rpm) actual[name]=rpm end}
    end
    local state=engine.new_state()
    state.mode="auto";state.phase="track";state.waypoint_x=120;state.waypoint_z=80
    local arrived=false
    for i=1,24000 do
      now=i*.05
      local f={x=math.cos(heading),y=0,z=-math.sin(heading)}
      local r={x=-math.sin(heading),y=0,z=-math.cos(heading)}
      local sample={x=x,y=400,z=z,vx=vx,vy=0,vz=vz,forward=f,right=r,
        forward_speed=vx*f.x+vz*f.z,side_speed=vx*r.x+vz*r.z,
        heading=heading,yaw_rate=rate,pitch_rate=0,roll_rate=0,dt=.05}
      local outputs
      state,outputs=engine.tick(state,{ship=sample,ready=true,config=cfg,su=stress.consumed({rsc=actual}),
        su_capacity=stress.CAPACITY,current_elevation_rpm=actual.rsc11})
      local applied=runtime.apply(outputs,devices,{measured=stress.consumed({rsc=actual}),capacity=stress.CAPACITY})
      state.modeled_su=stress.consumed(applied)
      local front=force(actual.rsc6)-force(actual.rsc9)
      local rear=force(actual.rsc8)-force(actual.rsc7)
      local side=(front+rear)/cfg.ship_mass
      local forward=(actual.rsc10<0 and -1 or 1)*10*(math.abs(actual.rsc10)/(430*pid.thrust_scale(400)))^1.2
      vx=vx+(f.x*forward+r.x*side+(i<300 and .01 or 0))*.05
      vz=vz+(f.z*forward+r.z*side)*.05
      x=x+vx*.05;z=z+vz*.05
      rate=rate+(front-rear)*8/(cfg.ship_mass*400)*.05
      heading=heading+rate*.05
      if math.sqrt(vx*vx+vz*vz)>50.1 then error("held navigation exceeds speed cap") end
      if state.phase=="descend" and math.sqrt(vx*vx+vz*vz)<.11 then arrived=true;break end
    end
    local distance=math.sqrt((x-120)^2+(z-80)^2)
    if not arrived or distance>10.1 then
      error(string.format("held navigation failed: initial heading %.3f, distance %.3f, phase %s",initial_heading,distance,state.phase))
    end
  end
end)
os.clock=old_clock
if not ok then error(failure) end
