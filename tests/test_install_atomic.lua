local A=dofile("tests/assert.lua")
local saved={fs=fs,http=http,write=write,printError=printError,reboot=os.reboot,print=print}
for _,program in ipairs({"command","pocket","watchdog"}) do
  for _,failure in ipairs({"download","commit","none"}) do
    local data={["startup.lua"]="old startup",["src/config.lua"]="old config"}
    local directories={}
    local downloads,moves,rebooted=0,0,false
    fs={
      exists=function(p) return data[p]~=nil or directories[p] end,
      getDir=function(p) return p:match("^(.*)/") or "" end,
      combine=function(a,b) return a.."/"..b end,
      makeDir=function(p) directories[p]=true end,
      open=function(p) return {write=function(s) data[p]=s end,close=function() end} end,
      delete=function(p)
        data[p]=nil;directories[p]=nil
        for key in pairs(data) do if key:sub(1,#p+1)==p.."/" then data[key]=nil end end
      end,
      move=function(a,b)
        if a:match("^%.autopilot%-install%-stage/%d+$") then
          moves=moves+1
          if failure=="commit" and moves==2 then error("disk failure") end
        end
        assert(data[a]~=nil,"missing "..a);assert(data[b]==nil,"exists "..b)
        data[b]=data[a];data[a]=nil
      end,
    }
    http={get=function()
      downloads=downloads+1
      if failure=="download" and downloads==3 then return nil,"offline" end
      return {readAll=function() return "return {}" end,close=function() end}
    end}
    write=function() end;printError=function() end;print=function() end
    os.reboot=function() rebooted=true end
    local ok=pcall(dofile,"install/"..program..".lua")
    if failure=="none" then
      A.eq(ok,true,"complete installation");A.eq(rebooted,true,"successful install reboots")
      A.eq(data["startup.lua"],"return {}","startup committed")
    else
      A.eq(ok,false,"installation failed")
      A.eq(rebooted,false,"failed install never reboots")
      A.eq(data["startup.lua"],"old startup","startup recovered")
      A.eq(data["src/config.lua"],"old config","dependency recovered")
    end
    A.eq(fs.exists(".autopilot-install-stage"),nil,"staging cleaned")
  end
end
local engine_data = { ["startup.lua"] = "old startup" }
fs = {
  exists = function(p) return engine_data[p] ~= nil end,
  delete = function(p) engine_data[p] = nil end,
}
local rebooted = false
os.reboot = function() rebooted = true end
local ok = pcall(dofile, "install/engine.lua")
A.eq(ok, true, "engine-room installer finishes")
A.eq(rebooted, true, "engine-room installer reboots")
A.eq(engine_data["startup.lua"], nil, "engine-room installer removes the old startup")
fs=saved.fs;http=saved.http;write=saved.write;printError=saved.printError;os.reboot=saved.reboot;print=saved.print
print("installer download and commit rollback passed")
