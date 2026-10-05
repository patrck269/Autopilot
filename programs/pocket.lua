local program = shell.getRunningProgram()
local dir = fs.getDir(program)
package.path = fs.combine(dir, "src") .. "/?.lua;" .. package.path
local pocket_ui = require("pocket_ui")
local gps_fix = require("gps_fix")
rednet.open("back")
local state = pocket_ui.new()
local held,expires=nil,0
local timer=os.startTimer(0.1)
pocket_ui.draw(state,term)
while true do
  local event,a,x,y=os.pullEvent()
  if event=="mouse_click" or event=="mouse_drag" then
    local _,message=pocket_ui.touch(state,x,y,{locate=function() return gps_fix.horizontal(gps.locate(2)) end})
    if message then
      if message.type=="stick" then held=message;expires=os.clock()+0.3 else held=nil end
      rednet.broadcast(message)
    end
  elseif event=="mouse_up" and held then
    held=nil
    rednet.broadcast({type="stick",x=0,y=0,z=0})
  elseif event=="rednet_message" and type(x)=="table" and x.type=="status" then
    state.status=x
    if x.diag_elevation then state.elevation=x.diag_elevation end
  elseif event=="timer" and a==timer then
    if held and os.clock()<expires then rednet.broadcast(held) else held=nil end
    timer=os.startTimer(0.1)
  end
  pocket_ui.draw(state,term)
end
