package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")

local commanded = 1840
local saved_path = package.path
local saved = {}
for _, name in ipairs({ "fs", "shell", "peripheral", "rednet" }) do
  saved[name] = _G[name]
end
local old_pull = os.pullEvent

local writes = {}
local opened = {}
rednet = {
  open = function(side)
    opened[#opened + 1] = side
  end,
}
fs = {
  getDir = function()
    return ""
  end,
  combine = function(_, name)
    return name
  end,
}
shell = {
  getRunningProgram = function()
    return "programs/simple_ship.lua"
  end,
}
peripheral = {
  wrap = function(network_name)
    return setmetatable({}, {
      __index = function(_, method)
        return function(...)
          writes[#writes + 1] = {
            name = network_name,
            method = method,
            args = { ... },
          }
        end
      end,
    })
  end,
}

local events = {
  { "rednet_message", 1, { type = "set_elevation", rpm = commanded } },
}
os.pullEvent = function()
  local next_event = table.remove(events, 1)
  if next_event == nil then
    error("test end", 0)
  end
  return table.unpack(next_event)
end

package.loaded.simple_ship = nil
local ok, err = pcall(dofile, "programs/simple_ship.lua")
package.path = saved_path
os.pullEvent = old_pull
for name, value in pairs(saved) do
  _G[name] = value
end

A.eq(#opened, 1, "the wired modem is opened once")
A.eq(opened[1], "back", "the wired modem is on the back")
A.eq(ok, false, "simpler ship stops when the test ends the event loop")
if not tostring(err):find("test end", 1, true) then
  error(err)
end

local elevation_writes = 0
local other_writes = 0
local applied = nil
for i = 1, #writes do
  local write = writes[i]
  local on_elevation = write.name == "Create_RotationSpeedController_16" and write.method == "setTargetSpeed"
  if on_elevation then
    elevation_writes = elevation_writes + 1
    applied = write.args[1]
  else
    other_writes = other_writes + 1
  end
end
A.eq(elevation_writes, 1, "speed controller 16 is set once")
A.eq(applied, commanded, "speed controller 16")
A.eq(other_writes, 0, "no other actuator is written")
print(string.format(
  "speed controller 16 = %s commanded %s other actuator writes %d",
  tostring(applied),
  tostring(commanded),
  other_writes
))
