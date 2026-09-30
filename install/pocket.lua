local BASE = "https://raw.githubusercontent.com/patrck269/Autopilot/245b38bde31f1f8e028bf3246365a4f254f8e555/"

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
