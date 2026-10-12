local M = {}

-- This hull's only actuator. The jazz ship keeps elevation on controller 11.
M.controller = "rsc16"
M.peripheral_name = "Create_RotationSpeedController_16"

function M.apply(rpm, device)
  if type(rpm) ~= "number" then
    error("elevation rpm required")
  end
  if device == nil or device.setTargetSpeed == nil then
    error("elevation controller missing")
  end
  device.setTargetSpeed(rpm)
  return rpm
end

-- ComputerCraft key codes. Enter applies the number on the screen.
local KEY_ENTER = 257
local KEY_NUMPAD_ENTER = 335
local KEY_BACKSPACE = 259
local KEY_DELETE = 261

function M.new_ui()
  return { draft = "", rpm = nil }
end

function M.draw(ui, output)
  output.clear()
  output.setCursorPos(1, 1)
  output.write("Elevation RPM")
  output.setCursorPos(1, 2)
  output.write("Controller 16")
  local shown = "-"
  if ui.rpm ~= nil then
    shown = tostring(ui.rpm)
  end
  output.setCursorPos(1, 4)
  output.write("Set " .. shown)
  output.setCursorPos(1, 6)
  output.write("RPM> " .. ui.draft)
  output.setCursorPos(1, 8)
  output.write("Enter sets it")
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
  ui.rpm = rpm
  return rpm
end

return M
