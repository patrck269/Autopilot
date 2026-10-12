package.path="src/?.lua;"..package.path
local A=dofile("tests/assert.lua")
local protocol=require("protocol")
local engine=require("engine_tick")
local config=require("config")
local frame=require("frame")
local control=require("control")
local shell=require("shell")
local pid=require("pid")
local cfg=config.default()
for _,bad in ipairs({math.huge,-math.huge,0/0}) do
  A.eq(protocol.validate({type="set_bearing",bearing=bad}),nil,"nonfinite bearing")
  A.eq(protocol.validate({type="stick",x=bad,y=0,z=0}),nil,"nonfinite stick")
  A.eq(config.clamp_rpm(bad),0,"nonfinite actuator")
end
A.eq(protocol.validate({type="diagnostic_set",device="rsc666",rpm=1}),nil,"unknown controller")
A.eq(protocol.validate({type="diagnostic_set",device="relay7",side="bogus",level=1}),nil,"unknown side")
local q={}
q=protocol.enqueue(q,{type="set_altitude",y=250})
q=protocol.enqueue(q,{type="set_bearing",bearing=1})
A.eq(#q,2,"independent setpoints survive")
q=protocol.enqueue(q,{type="emergency"})
q=protocol.enqueue(q,{type="stick",x=1,y=0,z=0})
A.eq(#q,1,"stick cannot overwrite emergency")
A.eq(q[1].type,"emergency","emergency priority")
local ship={x=0,y=100,z=0,vx=0,vy=0,vz=0,pitch=0,roll=0,heading=0,pitch_rate=0,roll_rate=0,dt=.05}
local function tick(state,command,commands)
  return engine.tick(state,{ship=ship,command=command,commands=commands,ready=true,stick_fresh=true,config=cfg,su=0,current_elevation_rpm=430})
end
local state=engine.new_state()
local outputs
state,outputs=tick(state,nil,{{type="set_mode",mode="semi"},{type="set_altitude",y=250},{type="set_speed",speed=20}})
A.eq(state.altitude,250,"queued altitude")
A.eq(state.target_speed,20,"queued speed")
state,outputs=tick(state,{type="diagnostic_enter",hover=true})
A.eq(outputs.rsc.rsc16,430,"diagnostic captures live lift")
state,outputs=tick(state,{type="diagnostic_exit"})
for _,rpm in pairs(outputs.rsc) do A.eq(rpm,0,"exit zeros all outputs") end
state,outputs=tick(state,nil)
for _,rpm in pairs(outputs.rsc) do A.eq(rpm,0,"exit remains zero") end
local session=shell.new_session(state,cfg,{})
local forwarded=false
shell.ingest(session,{}, {type="clear_emergency"},protocol.enqueue,function() forwarded=true end)
A.eq(forwarded,true,"queued clear reaches wired watchdog")
local v=frame.sample({x=0,y=0,z=0},{x=0,y=0,z=-4},{x=0,y=math.sin(math.pi/4),z=0,w=math.cos(math.pi/4)},{x=0,y=0,z=0},.05)
A.near(v.forward_speed,4,1e-9,"rotated forward speed")
A.near(v.side_speed,0,1e-9,"rotated side speed")
A.near(v.heading,math.pi/2,1e-9,"rotated heading")
-- No-drag force simulation exercises caps over sustained input, not one tick.
local function prop_accel(rpm,y)
  return (rpm<0 and -1 or 1)*10*(math.abs(rpm)/(430*pid.thrust_scale(y)))^1.2
end
-- Positive RPM thrusts along the controller's mount. The starboard pair is
-- mounted opposite the port pair, and a reverse command is a negative RPM.
local function force(rpm)
  local mag=100000*(math.abs(rpm or 0)/256)^1.2
  if (rpm or 0)<0 then return -mag end
  return mag
end
for _,mode in ipairs({"semi"}) do
  ship.vx=0;ship.vz=0;ship.y=62
  state=engine.new_state()
  if mode=="semi" then state,outputs=tick(state,nil,{{type="set_mode",mode="semi"},{type="set_speed",speed=80}}) end
  local cap=35
  for i=1,1200 do
    state,outputs=tick(state,mode=="manual" and {type="stick",x=1,y=0,z=0} or nil)
    ship.vx=ship.vx+prop_accel(outputs.rsc.rsc17,ship.y)*.05
    if ship.vx>cap+.01 then error(mode.." exceeded measured cap: "..ship.vx) end
  end
  A.near(ship.vx,cap,.02,mode.." reaches cap")
end
print("regression controls, frames, and command priority passed")

local writes={}
local devices={}
for name in pairs(require("mix").zero().rsc) do
  local name=name
  devices[name]={setTargetSpeed=function(rpm)
    writes[name]=rpm
    if name=="rsc17" then error("detached") end
  end}
end
local ok=pcall(require("runtime").apply,require("mix").zero(),devices)
A.eq(ok,false,"peripheral failure is reported")
for name in pairs(devices) do A.eq(writes[name],0,"zero attempted despite another failure") end
for _,dimensions in ipairs({{27,20},{10,8}}) do
  for _,button in ipairs(require("mfd").controls(dimensions[1],dimensions[2])) do
    if button.x+button.w-1>dimensions[1] or button.y+button.h-1>dimensions[2] then error("monitor control outside screen") end
  end
end
