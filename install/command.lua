local BASE = "https://raw.githubusercontent.com/patrck269/Autopilot/13855ce2ac0b81801ca5c2293e3014e2618f22f9/"

local files = {
  { "programs/command.lua", "startup.lua" },
  { "src/command_ui.lua", "src/command_ui.lua" },
  { "src/protocol.lua", "src/protocol.lua" },
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
