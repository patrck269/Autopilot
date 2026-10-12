local program = shell.getRunningProgram()
local dir = fs.getDir(program)
package.path = fs.combine(dir, "src") .. "/?.lua;" .. package.path

local simple = require("simple_ship")

local elevation = peripheral.wrap(simple.peripheral_name)
if elevation == nil then
  error("missing " .. simple.peripheral_name)
end

rednet.open("back")

local ui = simple.new_ui()

local function show()
  simple.draw(ui, term)
end

show()

while true do
  local event, a, b = os.pullEvent()
  local rpm = nil
  if event == "rednet_message" and type(b) == "table" and b.type == "set_elevation" and type(b.rpm) == "number" then
    rpm = b.rpm
    ui.rpm = rpm
    ui.draft = ""
  else
    rpm = simple.on_event(ui, event, a, b)
  end
  if rpm ~= nil then
    simple.apply(rpm, elevation)
  end
  show()
end
