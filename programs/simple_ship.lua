local program = shell.getRunningProgram()
local dir = fs.getDir(program)
package.path = fs.combine(dir, "src") .. "/?.lua;" .. package.path

local simple = require("simple_ship")

local elevation = peripheral.wrap(simple.peripheral_name)
if elevation == nil then
  error("missing " .. simple.peripheral_name)
end

rednet.open("back")

while true do
  local event, _, message = os.pullEvent()
  if event == "rednet_message" and type(message) == "table" and message.type == "set_elevation" then
    simple.apply(message.rpm, elevation)
  end
end
