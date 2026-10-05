local BASE = "https://raw.githubusercontent.com/patrck269/Autopilot/0845355e8d8b676c586f4fe224a240294b8fa439/"

local files = {
  { "programs/watchdog.lua", "startup.lua" },
  { "src/config.lua", "src/config.lua" },
  { "src/numeric.lua", "src/numeric.lua" },
  { "src/mix.lua", "src/mix.lua" },
  { "src/speed.lua", "src/speed.lua" },
  { "src/runtime.lua", "src/runtime.lua" },
  { "src/link.lua", "src/link.lua" },
  { "src/shell.lua", "src/shell.lua" },
  { "src/watchdog.lua", "src/watchdog.lua" },
}

-- Stage a complete, syntax-checked release before replacing any live file.
local stage=".autopilot-install-stage"
if fs.exists(stage) then error("Installation staging directory exists; inspect "..stage.." before retrying",0) end
fs.makeDir(stage)
local changed={}
local ok,err=pcall(function()
  for i,item in ipairs(files) do
    write("Get "..item[2].."... ")
    local response,why=http.get(BASE..item[1])
    if not response then error(why or ("Download failed: "..item[1]),0) end
    local body=response.readAll()
    response.close()
    local chunk,syntax=load(body,"@"..item[1],"t",{})
    if not chunk then error(syntax,0) end
    local handle=assert(fs.open(fs.combine(stage,tostring(i)),"w"),"Cannot stage "..item[2])
    handle.write(body);handle.close()
    print("ok")
  end
  -- startup is committed last, after all of its dependencies.
  for i=#files,1,-1 do
    local dest=files[i][2]
    local parent=fs.getDir(dest)
    if parent~="" then fs.makeDir(parent) end
    local backup=fs.combine(stage,"backup-"..i)
    local existed=fs.exists(dest)
    if existed then fs.move(dest,backup) end
    changed[#changed+1]={dest=dest,backup=backup,existed=existed}
    fs.move(fs.combine(stage,tostring(i)),dest)
  end
end)
if not ok then
  local recovered=true
  for i=#changed,1,-1 do
    local item=changed[i]
    local restored=pcall(function()
      if fs.exists(item.dest) then fs.delete(item.dest) end
      if item.existed then fs.move(item.backup,item.dest) end
    end)
    recovered=recovered and restored
  end
  if recovered then fs.delete(stage) end
  error(tostring(err)..(recovered and "" or ("; recovery files retained in "..stage)),0)
end
fs.delete(stage)
print("Rebooting into startup")
os.reboot()
