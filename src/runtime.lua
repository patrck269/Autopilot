local config = require("config")

local SIDES = { "bottom", "top", "front", "back", "left", "right" }

local M = {}

local function write_all(device, value)
  for _, side in ipairs(SIDES) do
    device.setOutput(side, value)
  end
end

function M.apply(outputs, devices)
  for name, rpm in pairs(outputs.rsc) do
    local device = devices[name]
    if device ~= nil and device.setTargetSpeed ~= nil then
      device.setTargetSpeed(config.clamp_rpm(rpm))
    end
  end
  local relay2 = devices.relay2
  if relay2 ~= nil and relay2.setAnalogOutput ~= nil then
    relay2.setAnalogOutput("bottom", outputs.relays.relay2 or 0)
  end
  for name, on in pairs(outputs.relays) do
    if name ~= "relay2" then
      local device = devices[name]
      if device ~= nil and device.setOutput ~= nil then
        write_all(device, on == true)
      end
    end
  end
  if outputs.diag_relay ~= nil then
    local device = devices[outputs.diag_relay.device]
    if device ~= nil and device.setOutput ~= nil then
      for _, side in ipairs(SIDES) do
        local value = 0
        if side == outputs.diag_relay.side then
          value = outputs.diag_relay.level
        end
        if device.setAnalogOutput ~= nil then
          device.setAnalogOutput(side, value)
        else
          device.setOutput(side, value ~= 0)
        end
      end
    end
  end
end

return M
