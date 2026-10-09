package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local names = {"fs", "shell", "rednet", "peripheral", "parallel"}
local saved = {}
for _, name in ipairs(names) do saved[name] = _G[name] end
local old_clock, old_timer, old_pull = os.clock, os.startTimer, os.pullEvent
local link = require("link")
local old_serve = link.serve
local attempts, broadcasts, now, timer = 0, 0, 0, 0
fs = {getDir=function() return "" end, combine=function(_, b) return b end,
  open=function() return {readAll=function() return "test" end, close=function() end} end}
shell = {getRunningProgram=function() return "startup.lua" end}
peripheral = {wrap=function(name)
  if name == "Create_RotationSpeedController_10" then
    return {setTargetSpeed=function()
      attempts = attempts + 1
      if attempts <= 2 then error("temporary actuator failure") end
    end}
  end
end}
rednet = {open=function() end, broadcast=function() broadcasts = broadcasts + 1 end}
link.serve = function(_, _, _, callback) callback({type="zero"}) end
parallel = {waitForAll=function(rednet_loop, socket_loop)
  -- Deliver one authenticated socket command, then run watchdog retry ticks.
  local co = coroutine.create(socket_loop)
  A.eq(coroutine.resume(co), true, "socket loop survives actuator error")
  rednet_loop()
end}
os.clock = function() return now end
os.startTimer = function() timer = timer + 1; return timer end
os.pullEvent = function()
  if now >= .4 then error("test end", 0) end
  now = now + .2
  return "timer", timer
end
local old_sleep = _G.sleep
sleep = function() coroutine.yield() end
package.loaded.runtime = nil
local ok, err = pcall(dofile, "programs/watchdog.lua")
for _, name in ipairs(names) do _G[name] = saved[name] end
os.clock, os.startTimer, os.pullEvent = old_clock, old_timer, old_pull
sleep, link.serve = old_sleep, old_serve
A.eq(ok, false, "test stops watchdog loop")
if not tostring(err):find("test end", 1, true) then error(err) end
A.eq(attempts, 3, "watchdog retries failed actuator stop")
A.eq(broadcasts, 3, "write failure cannot suppress watchdog latch broadcasts")
