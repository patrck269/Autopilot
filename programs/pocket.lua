local program = shell.getRunningProgram()
local dir = fs.getDir(program)
package.path = fs.combine(dir, "src") .. "/?.lua;" .. package.path

local pocket_ui = require("pocket_ui")
local gps_fix = require("gps_fix")

rednet.open("back")
local state = pocket_ui.new()
while true do
  local event, _, x, y = os.pullEvent()
  if event == "mouse_click" then
    local _, message = pocket_ui.touch(state, x, y, {
      locate = function()
        return gps_fix.horizontal(gps.locate(2))
      end,
    })
    if message ~= nil then
      rednet.broadcast(message)
    end
  end
end
