local M = {}

-- Elevation is controller 16. Thrusters are controller 17.
M.elevation_name = "Create_RotationSpeedController_16"
M.thruster_name = "Create_RotationSpeedController_17"

function M.apply(axis, rpm, device)
  if axis ~= "elevation" and axis ~= "thrusters" then
    error("rpm axis required")
  end
  if type(rpm) ~= "number" then
    error(axis .. " rpm required")
  end
  if device == nil or device.setTargetSpeed == nil then
    error(axis .. " controller missing")
  end
  device.setTargetSpeed(rpm)
  return rpm
end

-- ComputerCraft key codes. Enter applies the number on the screen.
local KEY_ENTER = 257
local KEY_NUMPAD_ENTER = 335
local KEY_BACKSPACE = 259
local KEY_DELETE = 261
local KEY_UP = 265
local KEY_DOWN = 264

function M.new_ui()
  return {
    draft = "",
    selected = "elevation",
    elevation = nil,
    thrusters = nil,
  }
end

local function shown(rpm)
  if rpm == nil then
    return "-"
  end
  return tostring(rpm)
end

function M.draw(ui, output)
  output.clear()
  output.setCursorPos(1, 1)
  output.write("Elevation RPM")
  output.setCursorPos(1, 2)
  output.write("Controller 16")
  output.setCursorPos(1, 3)
  output.write("Set " .. shown(ui.elevation))
  output.setCursorPos(1, 5)
  output.write("Thrusters RPM")
  output.setCursorPos(1, 6)
  output.write("Controller 17")
  output.setCursorPos(1, 7)
  output.write("Set " .. shown(ui.thrusters))
  output.setCursorPos(1, 9)
  output.write("Editing " .. ui.selected)
  output.setCursorPos(1, 10)
  output.write("RPM> " .. ui.draft)
  output.setCursorPos(1, 12)
  output.write("Enter sets it")
  output.setCursorPos(1, 13)
  output.write("Up or down switches")
end

local function append_draft(ui, character)
  if character:match("%d") then
    ui.draft = ui.draft .. character
    return
  end
  if character == "-" and ui.draft == "" then
    ui.draft = "-"
    return
  end
  if character == "." and ui.draft ~= "" and ui.draft ~= "-" and not ui.draft:find(".", 1, true) then
    ui.draft = ui.draft .. "."
  end
end

local function switch_axis(ui)
  if ui.selected == "elevation" then
    ui.selected = "thrusters"
  else
    ui.selected = "elevation"
  end
  ui.draft = ""
end

-- Returns the RPM to send when the user commits the field. Other keys only edit the draft.
function M.on_event(ui, event, a, b)
  if event == "key" and b == true then
    return nil
  end
  if event == "char" and type(a) == "string" and #a == 1 then
    append_draft(ui, a)
    return nil
  end
  if event ~= "key" then
    return nil
  end
  if a == KEY_UP or a == KEY_DOWN then
    switch_axis(ui)
    return nil
  end
  if a == KEY_BACKSPACE or a == KEY_DELETE then
    ui.draft = ui.draft:sub(1, -2)
    return nil
  end
  if a ~= KEY_ENTER and a ~= KEY_NUMPAD_ENTER then
    return nil
  end
  local rpm = tonumber(ui.draft)
  if rpm == nil then
    return nil
  end
  ui.draft = ""
  ui[ui.selected] = rpm
  return rpm
end

return M
