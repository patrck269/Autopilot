package.path="src/?.lua;"..package.path
local A=dofile("tests/assert.lua")
local cfg=require("config").default()
local saved={}
for _,name in ipairs({"fs","shell","rednet","peripheral","ship","parallel","term","colors"}) do saved[name]=_G[name] end
local old_clock,old_timer,old_pull=os.clock,os.startTimer,os.pullEvent
local now,events,hardware,broadcasts=0,{}, {},{}
fs={getDir=function() return "" end,combine=function(a,b) return b end,open=function() return nil end}
shell={getRunningProgram=function() return "startup.lua" end}
colors={green=1,gray=2,red=3,black=4,white=5,blue=6,lime=7,lightBlue=8,yellow=9,orange=10,lightGray=11}
term={setBackgroundColor=function() end,setTextColor=function() end,clear=function() end,setCursorPos=function() end,write=function() end,getSize=function() return 40,20 end}
peripheral={
  isPresent=function() return true end,getType=function() return "modem" end,find=function() return nil end,getNames=function() return {} end,
  wrap=function(network)
    local key
    for name,value in pairs(cfg.names) do if value==network then key=name end end
    return {
      setTargetSpeed=function(rpm) hardware[key]=rpm end,
      getTargetSpeed=function() return hardware[key] or 430 end,
      setOutput=function() end,setAnalogOutput=function() end,
      getStress=function() return 0 end,getStressCapacity=function() return 479231 end,getSpeed=function() return 256 end,
    }
  end,
}
ship={getWorldspacePosition=function() return {x=0,y=100,z=0} end,
 getVelocity=function() return {x=0,y=0,z=0} end,
 getQuaternion=function() return {x=0,y=0,z=0,w=1} end,
 getAngularVelocity=function() return {x=0,y=0,z=0} end}
rednet={open=function() end,broadcast=function(status)
  local copy={};for k,v in pairs(hardware) do copy[k]=v end
  broadcasts[#broadcasts+1]={status=status,outputs=copy}
end}
parallel={waitForAll=function(flight,debug) debug();flight() end}
os.clock=function() return now end
local timer=0
os.startTimer=function() timer=timer+1;return timer end
os.pullEvent=function()
  now=now+.05
  local next=table.remove(events,1)
  if not next then error("test end",0) end
  return table.unpack(next)
end
local function run(commands)
  hardware={};broadcasts={};events={};timer=0;now=0
  for _,command in ipairs(commands) do events[#events+1]={"rednet_message",12,command} end
  events[#events+1]={"timer",1}
  local ok,err=pcall(dofile,"programs/command.lua")
  A.eq(ok,false,"test stops event loop")
  if not tostring(err):find("test end",1,true) then error(err) end
  A.eq(#broadcasts,1,"one flight sample")
  for name,rpm in pairs(hardware) do A.eq(rpm,0,"fatal exit zeros "..name) end
  return broadcasts[1]
end
local result=run({{type="set_mode",mode="semi"},{type="set_altitude",y=250},{type="set_speed",speed=20}})
if result.outputs.rsc10<=0 then error("actual program dropped queued speed") end
if result.outputs.rsc11<=430 then error("actual program dropped queued altitude") end
A.eq(result.status.type,"status","program broadcasts telemetry")
result=run({{type="emergency"},{type="stick",x=1,y=0,z=0}})
A.eq(result.status.emergency,true,"program latches emergency before queued stick")
for _,rpm in pairs(result.outputs) do A.eq(rpm,0,"emergency output") end
for name,value in pairs(saved) do _G[name]=value end
-- Explicit nil restoration as pairs omits absent globals.
for _,name in ipairs({"fs","shell","rednet","peripheral","ship","parallel","term","colors"}) do _G[name]=saved[name] end
os.clock,os.startTimer,os.pullEvent=old_clock,old_timer,old_pull
print("command program queue and fatal-exit cleanup passed")
