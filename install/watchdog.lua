local BASE = "https://raw.githubusercontent.com/patrck269/Autopilot/2524ee3aa90ecd948c99c282b3653cf4b8e179e9/"

local files = {
  { "programs/watchdog.lua", "startup.lua" },
  { "src/watchdog.lua", "src/watchdog.lua" },
  { "src/link.lua", "src/link.lua" },
  { "src/shell.lua", "src/shell.lua" },
  { "src/config.lua", "src/config.lua" },
  { "src/mix.lua", "src/mix.lua" },
  { "src/speed.lua", "src/speed.lua" },
  { "src/runtime.lua", "src/runtime.lua" },
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
