local BASE = "https://raw.githubusercontent.com/patrck269/Autopilot/0c2c52203bcfb3b830e6d59f3990098fe2609a59/"

local files = {
  { "programs/command.lua", "startup.lua" },
  { "src/auto.lua", "src/auto.lua" },
  { "src/command_status.lua", "src/command_status.lua" },
  { "src/command_ui.lua", "src/command_ui.lua" },
  { "src/config.lua", "src/config.lua" },
  { "src/control.lua", "src/control.lua" },
  { "src/diagnostic.lua", "src/diagnostic.lua" },
  { "src/engine_tick.lua", "src/engine_tick.lua" },
  { "src/frame.lua", "src/frame.lua" },
  { "src/hover.lua", "src/hover.lua" },
  { "src/jobs.lua", "src/jobs.lua" },
  { "src/link.lua", "src/link.lua" },
  { "src/manual.lua", "src/manual.lua" },
  { "src/mfd.lua", "src/mfd.lua" },
  { "src/mix.lua", "src/mix.lua" },
  { "src/monitors.lua", "src/monitors.lua" },
  { "src/numeric.lua", "src/numeric.lua" },
  { "src/outage.lua", "src/outage.lua" },
  { "src/pid.lua", "src/pid.lua" },
  { "src/protocol.lua", "src/protocol.lua" },
  { "src/runtime.lua", "src/runtime.lua" },
  { "src/shell.lua", "src/shell.lua" },
  { "src/speed.lua", "src/speed.lua" },
  { "src/startup.lua", "src/startup.lua" },
  { "src/stress.lua", "src/stress.lua" },
  { "src/views.lua", "src/views.lua" },
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
