local SIDES = { "bottom", "top", "front", "back", "left", "right" }

local M = {}

local function write_all(device, value)
  for _, side in ipairs(SIDES) do
    device:setOutput(side, value)
  end
end

function M.apply(outputs, devices)
  for name, rpm in pairs(outputs.rsc) do
    local device = devices[name]
    if device ~= nil and device.setTargetSpeed ~= nil then
      device:setTargetSpeed(rpm)
    end
  end
  local relay2 = devices.relay2
  if relay2 ~= nil and relay2.setAnalogOutput ~= nil then
    relay2:setAnalogOutput("bottom", outputs.relays.relay2 or 0)
  end
  for name, on in pairs(outputs.relays) do
    if name ~= "relay2" then
      local device = devices[name]
      if device ~= nil and device.setOutput ~= nil then
        local value = 0
        if on == true then
          value = 15
        end
        write_all(device, value)
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
        device:setOutput(side, value)
      end
    end
  end
end

return M
