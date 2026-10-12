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

return M
