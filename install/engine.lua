local BASE = "https://raw.githubusercontent.com/patrck269/Autopilot/071eba99e9986bb55c7aa80561a50707d4307cdd/"

local files = {
  { "programs/engine.lua", "startup.lua" },
  { "src/auto.lua", "src/auto.lua" },
  { "src/config.lua", "src/config.lua" },
  { "src/diagnostic.lua", "src/diagnostic.lua" },
  { "src/engine_tick.lua", "src/engine_tick.lua" },
  { "src/hover.lua", "src/hover.lua" },
  { "src/jobs.lua", "src/jobs.lua" },
  { "src/manual.lua", "src/manual.lua" },
  { "src/mfd.lua", "src/mfd.lua" },
  { "src/mix.lua", "src/mix.lua" },
  { "src/monitors.lua", "src/monitors.lua" },
  { "src/outage.lua", "src/outage.lua" },
  { "src/pid.lua", "src/pid.lua" },
  { "src/protocol.lua", "src/protocol.lua" },
  { "src/runtime.lua", "src/runtime.lua" },
  { "src/speed.lua", "src/speed.lua" },
  { "src/stress.lua", "src/stress.lua" },
  { "src/startup.lua", "src/startup.lua" },
  { "src/views.lua", "src/views.lua" },
}

local function download(urlPath, dest)
  local dir = fs.getDir(dest)
  if dir ~= "" then
    fs.makeDir(dir)
  end
  write("Get " .. dest .. "... ")
  local response, err = http.get(BASE .. urlPath)
  if not response then
    printError(err or "failed")
    error("Download failed: " .. urlPath, 0)
  end
  local body = response.readAll()
  response.close()
  local handle = fs.open(dest, "w")
  handle.write(body)
  handle.close()
  print("ok")
end

for _, item in ipairs(files) do
  download(item[1], item[2])
end

print("Rebooting into startup")
os.reboot()
