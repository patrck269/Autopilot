local BASE = "https://raw.githubusercontent.com/patrck269/Autopilot/00ff102dc44dce949b3593894ae09442d1b59636/"

local files = {
  { "programs/command.lua", "startup.lua" },
  { "src/command_ui.lua", "src/command_ui.lua" },
  { "src/protocol.lua", "src/protocol.lua" },
  { "src/command_status.lua", "src/command_status.lua" },
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
