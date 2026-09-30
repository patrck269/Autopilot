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

check("engine", "programs/engine.lua", "install/engine.lua")
check("command", "programs/command.lua", "install/command.lua")
check("pocket", "programs/pocket.lua", "install/pocket.lua")
check("watchdog", "programs/watchdog.lua", "install/watchdog.lua")
