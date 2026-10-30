package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")

local saved_path = package.path
local saved = {}
for _, name in ipairs({ "fs", "shell", "peripheral", "rednet", "term" }) do
  saved[name] = _G[name]
end
local old_pull = os.pullEvent

local ELEVATION = "Create_RotationSpeedController_16"
local THRUSTERS = "Create_RotationSpeedController_17"
local KEY_ENTER = 257
local KEY_BACKSPACE = 259
local KEY_DOWN = 264

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

local function writes_of(writes, name)
  local count = 0
  local others = 0
  local applied = nil
  for i = 1, #writes do
    local write = writes[i]
    if write.name == name and write.method == "setTargetSpeed" then
      count = count + 1
      applied = write.args[1]
    else
      others = others + 1
    end
  end
  return count, others, applied
end

local function screen_has(screen, text)
  for i = 1, #screen do
    if screen[i] == text then
      return true
    end
  end
  return false
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
local elevation_writes, other_writes, applied = writes_of(writes, ELEVATION)
A.eq(elevation_writes, 1, "speed controller 16 is set once")
A.eq(applied, commanded, "speed controller 16")
A.eq(other_writes, 0, "elevation leaves the thrusters alone")
A.eq(screen_has(screen, "RPM> "), true, "the screen asks for an rpm")
A.eq(screen_has(screen, "Set " .. tostring(commanded)), true, "the screen shows the elevation rpm")
A.eq(screen_has(screen, "Editing elevation"), true, "rednet elevation leaves the editor on elevation")
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
  { "key", KEY_BACKSPACE, false },
  { "char", "0" },
  { "char", "0" },
  { "key", KEY_ENTER, false },
})
finish(ok, err)
A.eq(#opened, 1, "typing still opens the wired modem once")
elevation_writes, other_writes, applied = writes_of(writes, ELEVATION)
A.eq(elevation_writes, 1, "typed rpm sets speed controller 16 once")
A.eq(applied, typed, "speed controller 16")
A.eq(other_writes, 0, "typing elevation writes no thruster")
A.eq(screen_has(screen, "Set " .. tostring(typed)), true, "the screen shows the rpm that was set")
print(string.format(
  "typed rpm %s set speed controller 16 = %s other actuator writes %d",
  tostring(typed),
  tostring(applied),
  other_writes
))

local thrust = 400
ok, err, writes, opened, screen = run({
  { "key", KEY_DOWN, false },
  { "char", "4" },
  { "char", "0" },
  { "char", "0" },
  { "key", KEY_ENTER, false },
})
finish(ok, err)
local thruster_writes
thruster_writes, other_writes, applied = writes_of(writes, THRUSTERS)
A.eq(thruster_writes, 1, "down then enter sets speed controller 17 once")
A.eq(applied, thrust, "speed controller 17")
A.eq(other_writes, 0, "typing thrusters leaves elevation alone")
A.eq(screen_has(screen, "Editing thrusters"), true, "down selects thrusters")
A.eq(screen_has(screen, "Set " .. tostring(thrust)), true, "the screen shows the thruster rpm")
print(string.format(
  "typed rpm %s set speed controller 17 = %s other actuator writes %d",
  tostring(thrust),
  tostring(applied),
  other_writes
))

local commanded_thrust = 1200
ok, err, writes, opened, screen = run({
  { "rednet_message", 1, { type = "set_thrusters", rpm = commanded_thrust } },
})
finish(ok, err)
thruster_writes, other_writes, applied = writes_of(writes, THRUSTERS)
A.eq(thruster_writes, 1, "rednet sets speed controller 17 once")
A.eq(applied, commanded_thrust, "rednet thrusters")
A.eq(other_writes, 0, "rednet thrusters leave elevation alone")
A.eq(screen_has(screen, "Set " .. tostring(commanded_thrust)), true, "the screen shows the rednet thruster rpm")
A.eq(screen_has(screen, "Editing elevation"), true, "rednet thrusters leave the editor on elevation")
print(string.format(
  "speed controller 17 = %s commanded %s other actuator writes %d",
  tostring(applied),
  tostring(commanded_thrust),
  other_writes
))

ok, err, writes = run({
  { "key", KEY_DOWN, false },
  { "key", KEY_DOWN, true },
  { "char", "5" },
  { "key", 265, false },
})
finish(ok, err)
A.eq(#writes, 0, "switching axis writes no controller")
end)
restore()
if not suite_ok then
  error(suite_err)
end
