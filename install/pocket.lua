local BASE = "https://raw.githubusercontent.com/patrck269/Autopilot/4d8e8817032f30a5cd0aa8bea7d8da47492b14bc/"

local files = {
  { "programs/pocket.lua", "startup.lua" },
  { "src/pocket_ui.lua", "src/pocket_ui.lua" },
  { "src/protocol.lua", "src/protocol.lua" },
  { "src/gps_fix.lua", "src/gps_fix.lua" },
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
