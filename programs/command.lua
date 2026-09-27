local program = shell.getRunningProgram()
local dir = fs.getDir(program)
package.path = fs.combine(dir, "src") .. "/?.lua;" .. package.path

local command_ui = require("command_ui")
local command_status = require("command_status")

local function fill(x, y, w, h, bg)
  term.setBackgroundColor(bg)
  for row = 0, h - 1 do
    term.setCursorPos(x, y + row)
    term.write((" "):rep(w))
  end
end

local function text(x, y, value, fg, bg, maxW)
  if maxW ~= nil and #value > maxW then
    value = string.sub(value, 1, maxW)
  end
  term.setCursorPos(x, y)
  term.setTextColor(fg)
  term.setBackgroundColor(bg)
  term.write(value)
end

local function describe(message, state)
  if message == nil then
    if state.field ~= nil then
      return "Typing " .. state.field .. ": " .. state.buffer
    end
    return "Ready"
  end
  if message.type == "stick" then
    local parts = {}
    if message.x > 0 then parts[#parts + 1] = "forward" end
    if message.x < 0 then parts[#parts + 1] = "back" end
    if message.y > 0 then parts[#parts + 1] = "right" end
    if message.y < 0 then parts[#parts + 1] = "left" end
    if message.z > 0 then parts[#parts + 1] = "up" end
    if message.z < 0 then parts[#parts + 1] = "down" end
    if #parts == 0 then
      return "Stick released"
    end
    return "Stick " .. table.concat(parts, " ")
  end
  if message.type == "set_mode" then
    return "Mode " .. message.mode
  end
  if message.type == "set_profile" then
    return "Profile " .. message.profile
  end
  if message.type == "set_altitude" then
    return "Altitude " .. tostring(message.y)
  end
  if message.type == "set_bearing" then
    return "Bearing " .. tostring(message.bearing)
  end
  if message.type == "set_speed" then
    return "Speed " .. tostring(message.speed)
  end
  if message.type == "set_waypoint" then
    return "Waypoint " .. tostring(message.x) .. ", " .. tostring(message.z)
  end
  if message.type == "emergency" then
    return "Emergency stop"
  end
  if message.type == "clear_emergency" then
    return "Emergency cleared"
  end
  return message.type
end

local function draw(state, status)
  local width, height = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()

  fill(1, 1, width, 1, colors.lightBlue)
  text(2, 1, "SHIP COMMAND", colors.white, colors.lightBlue)

  local leftW = math.floor(width * 0.55)
  local rightX = leftW + 2
  local rightW = width - rightX

  local leftText = leftW - 2
  local rightText = rightW - 2
  fill(1, 3, leftW, 6, colors.gray)
  text(2, 3, "STICK", colors.white, colors.gray, leftText)
  text(2, 4, "Left / Right  back / forward", colors.black, colors.gray, leftText)
  text(2, 5, "A / D         left / right", colors.black, colors.gray, leftText)
  text(2, 6, "Space / Up    up", colors.black, colors.gray, leftText)
  text(2, 7, "Shift / Down  down", colors.black, colors.gray, leftText)

  fill(rightX, 3, rightW, 6, colors.blue)
  text(rightX + 1, 3, "MODES", colors.white, colors.blue, rightText)
  text(rightX + 1, 4, "M  Manual", colors.yellow, colors.blue, rightText)
  text(rightX + 1, 5, "S  Semi-automatic", colors.lime, colors.blue, rightText)
  text(rightX + 1, 6, "U  Automatic", colors.orange, colors.blue, rightText)
  text(rightX + 1, 7, "W  Cruise / warp", colors.white, colors.blue, rightText)

  fill(1, 10, leftW, 6, colors.lightGray)
  text(2, 10, "ENTER A NUMBER", colors.black, colors.lightGray, leftText)
  local function entry(row, label, fieldName)
    local active = state.field == fieldName
    local bg = colors.lightGray
    local fg = colors.black
    local value = label
    if active then
      bg = colors.white
      fg = colors.black
      value = label .. " " .. state.buffer .. "_"
    end
    fill(2, row, leftText, 1, bg)
    text(2, row, value, fg, bg, leftText)
  end
  entry(11, "Y Altitude", "y")
  entry(12, "B Bearing", "bearing")
  entry(13, "V Speed", "speed")
  entry(14, "X Waypoint", "x")
  entry(15, "Z Waypoint", "z")

  fill(rightX, 10, rightW, 6, colors.red)
  text(rightX + 1, 10, "SAFETY", colors.white, colors.red, rightText)
  text(rightX + 1, 12, "E  Emergency stop", colors.white, colors.red, rightText)
  text(rightX + 1, 13, "C  Clear emergency", colors.white, colors.red, rightText)

  fill(1, height, width, 1, colors.black)
  local line = status
  if #line > width - 1 then
    line = string.sub(line, 1, width - 1)
  end
  text(2, height, line, colors.white, colors.black)
end

rednet.open("back")
local state = command_ui.new()
local status = "Ready"
local link = nil
draw(state, status)

while true do
  local event, p1, p2 = os.pullEvent()
  local message = nil
  if event == "rednet_message" then
    local applied = command_status.apply(p2)
    if applied ~= nil then
      link = applied
      status = applied.line
      draw(state, status)
    end
  elseif event == "key" then
    local name = keys.getName(p1)
    state, message = command_ui.key(state, name, true)
  elseif event == "key_up" then
    local name = keys.getName(p1)
    state, message = command_ui.key(state, name, false)
  elseif event == "term_resize" then
    draw(state, status)
  end
  if message ~= nil then
    rednet.broadcast(message)
    if link == nil then
      status = describe(message, state)
    end
  elseif state.field ~= nil and link == nil then
    status = describe(nil, state)
  end
  if event == "key" or event == "key_up" or event == "term_resize" then
    draw(state, status)
  end
end
