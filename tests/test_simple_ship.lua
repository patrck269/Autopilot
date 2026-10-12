package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")

local saved_path = package.path
local saved = {}
for _, name in ipairs({ "fs", "shell", "peripheral", "rednet", "term" }) do
  saved[name] = _G[name]
end
local old_pull = os.pullEvent

local function run(events)
  local writes = {}
  local opened = {}
  local screen = {}
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
  term = {
    clear = function()
      screen = {}
    end,
    setCursorPos = function() end,
    write = function(text)
      screen[#screen + 1] = text
    end,
  }
  local queue = events
  os.pullEvent = function()
    local next_event = table.remove(queue, 1)
    if next_event == nil then
      error("test end", 0)
    end
    return table.unpack(next_event)
  end
  package.loaded.simple_ship = nil
  local ok, err = pcall(dofile, "programs/simple_ship.lua")
  return ok, err, writes, opened, screen
end

local function finish(ok, err)
  A.eq(ok, false, "simpler ship stops when the test ends the event loop")
  if not tostring(err):find("test end", 1, true) then
    error(err)
  end
end

local function applied_rpm(writes)
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
  return elevation_writes, other_writes, applied
end

local function restore()
  package.path = saved_path
  os.pullEvent = old_pull
  for name, value in pairs(saved) do
    _G[name] = value
  end
end

local suite_ok, suite_err = pcall(function()
local commanded = 1840
local ok, err, writes, opened, screen = run({
  { "rednet_message", 1, { type = "set_elevation", rpm = commanded } },
})
finish(ok, err)
A.eq(#opened, 1, "the wired modem is opened once")
A.eq(opened[1], "back", "the wired modem is on the back")
local elevation_writes, other_writes, applied = applied_rpm(writes)
A.eq(elevation_writes, 1, "speed controller 16 is set once")
A.eq(applied, commanded, "speed controller 16")
A.eq(other_writes, 0, "no other actuator is written")
local showed_prompt = false
for i = 1, #screen do
  if screen[i] == "RPM> " then
    showed_prompt = true
  end
end
A.eq(showed_prompt, true, "the screen asks for an rpm")
print(string.format(
  "speed controller 16 = %s commanded %s other actuator writes %d",
  tostring(applied),
  tostring(commanded),
  other_writes
))

local typed = 900
ok, err, writes, opened, screen = run({
  { "char", "x" },
  { "char", "9" },
  { "char", "1" },
  { "key", 259, false },
  { "char", "0" },
  { "char", "0" },
  { "key", 257, false },
})
finish(ok, err)
A.eq(#opened, 1, "typing still opens the wired modem once")
elevation_writes, other_writes, applied = applied_rpm(writes)
A.eq(elevation_writes, 1, "typed rpm sets speed controller 16 once")
A.eq(applied, typed, "speed controller 16")
A.eq(other_writes, 0, "typing writes no other actuator")
local showed_set = false
for i = 1, #screen do
  if screen[i] == "Set " .. tostring(typed) then
    showed_set = true
  end
end
A.eq(showed_set, true, "the screen shows the rpm that was set")
print(string.format(
  "typed rpm %s set speed controller 16 = %s other actuator writes %d",
  tostring(typed),
  tostring(applied),
  other_writes
))
end)
restore()
if not suite_ok then
  error(suite_err)
end
