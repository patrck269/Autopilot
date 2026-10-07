local function read_all(path)
  local handle = io.open(path, "rb")
  if handle == nil then
    error("missing " .. path)
  end
  local text = handle:read("a")
  handle:close()
  return text:gsub("\r\n", "\n")
end

local function installer_paths(text)
  local have = {}
  for src in text:gmatch('{ "([^"]+)"') do
    have[src] = true
  end
  return have
end

local function walk(program)
  local needed = {}
  local function visit(path)
    if needed[path] then
      return
    end
    needed[path] = true
    local text = read_all(path)
    for name in text:gmatch('require%("([%w_]+)"%)') do
      visit("src/" .. name .. ".lua")
    end
  end
  visit(program)
  return needed
end

local function check(label, program, installer)
  local have = installer_paths(read_all(installer))
  for path in pairs(walk(program)) do
    if not have[path] then
      error(label .. " installer is missing " .. path)
    end
  end
  print(label .. " complete")
end

check("command", "programs/command.lua", "install/command.lua")
check("pocket", "programs/pocket.lua", "install/pocket.lua")
check("watchdog", "programs/watchdog.lua", "install/watchdog.lua")

local engine_installer = read_all("install/engine.lua")
if engine_installer:find("programs/engine.lua", 1, true) then
  error("engine-room program is still on the boot path")
end
if engine_installer:find("{ ", 1, true) then
  error("engine-room installer still downloads a boot file")
end
if engine_installer:find('fs.delete("startup.lua")', 1, true) == nil then
  error("engine-room installer leaves the old startup in place")
end
local engine_program = read_all("programs/engine.lua")
if engine_program:find("engine_tick", 1, true)
    or engine_program:find("runtime.apply", 1, true)
    or engine_program:find("rednet.broadcast", 1, true)
    or engine_program:find("link.serve", 1, true)
    or engine_program:find("link_mod.serve", 1, true) then
  error("engine-room program still flies")
end
print("engine-room computer is not on the boot path")

local command_src = read_all("programs/command.lua")
local function has(needle, label)
  if command_src:find(needle, 1, true) == nil then
    error("command-center program does not " .. label)
  end
end
has("engine_tick.tick", "call the flight tick")
has("runtime.apply", "apply outputs")
has("monitors.assign", "assign the monitors")
has("command_ui.key", "handle local keys")
has("shell_mod.ingest", "use the flight intake")
has("rednet.broadcast(status)", "broadcast the status heartbeat")
has("rednet.open(\"back\")", "open the wired modem")
has("isWireless", "find the ender modem on the network")
has("rednet.open(name)", "open the ender modem")
has("apply_latch", "apply the debug latch")
has("repeat_wired", "repeat a clear on the wired modem")
has("on_idle, session", "dial the debug shell with the flight session")
has("parallel.waitForAll", "run the shell beside the flight loop")
has("mfd.hit", "swap a monitor page on touch")
print("command-center program flies")
