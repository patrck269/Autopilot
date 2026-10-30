local program = shell.getRunningProgram()
local dir = fs.getDir(program)
package.path = fs.combine(dir, "src") .. "/?.lua;" .. package.path

local simple = require("simple_ship")

local elevation = peripheral.wrap(simple.elevation_name)
if elevation == nil then
  error("missing " .. simple.elevation_name)
end
local thrusters = peripheral.wrap(simple.thruster_name)
if thrusters == nil then
  error("missing " .. simple.thruster_name)
end

local devices = {
  elevation = elevation,
  thrusters = thrusters,
}

rednet.open("back")

local ui = simple.new_ui()

local function show()
  simple.draw(ui, term)
end

local function accept(axis, rpm)
  ui[axis] = rpm
  ui.draft = ""
  simple.apply(axis, rpm, devices[axis])
end

show()

while true do
  local event, a, b = os.pullEvent()
  if event == "rednet_message" and type(b) == "table" and type(b.rpm) == "number" then
    if b.type == "set_elevation" then
      accept("elevation", b.rpm)
    elseif b.type == "set_thrusters" then
      accept("thrusters", b.rpm)
    end
  else
    local rpm = simple.on_event(ui, event, a, b)
    if rpm ~= nil then
      simple.apply(ui.selected, rpm, devices[ui.selected])
    end
  end
  show()
end
