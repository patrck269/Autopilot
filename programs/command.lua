local program = shell.getRunningProgram()
local dir = fs.getDir(program)
package.path = fs.combine(dir, "src") .. "/?.lua;" .. package.path

local command_ui = require("command_ui")

rednet.open("back")
local state = command_ui.new()
while true do
  local event, key = os.pullEvent()
  if event == "key" then
    local name = keys.getName(key)
    local _, message = command_ui.key(state, name, true)
    if message ~= nil then
      rednet.broadcast(message)
    end
  elseif event == "key_up" then
    local name = keys.getName(key)
    local _, message = command_ui.key(state, name, false)
    if message ~= nil then
      rednet.broadcast(message)
    end
  end
end
