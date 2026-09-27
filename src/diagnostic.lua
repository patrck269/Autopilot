local mix = require("mix")

local M = {}

local LOCKED = {
  rsc11 = true,
  relay6 = true,
  relay7 = true,
  relay8 = true,
  relay9 = true,
  relay10 = true,
}

local function clamp_rpm(rpm)
  if rpm > 32 then
    return 32
  end
  if rpm < -32 then
    return -32
  end
  return rpm
end

local function clamp_level(level)
  if level > 15 then
    return 15
  end
  if level < 0 then
    return 0
  end
  return level
end

function M.apply(selection, hover)
  local outputs = mix.zero()
  outputs.diag_relay = nil
  local hover_on = hover ~= nil and hover.enabled == true
  if hover_on then
    outputs.rsc.rsc11 = hover.rpm
  end
  if selection == nil then
    return outputs
  end
  if hover_on and LOCKED[selection.device] then
    return outputs
  end
  if selection.rpm ~= nil then
    outputs.rsc[selection.device] = clamp_rpm(selection.rpm)
    return outputs
  end
  if selection.side ~= nil then
    outputs.diag_relay = {
      device = selection.device,
      side = selection.side,
      level = clamp_level(selection.level),
    }
  end
  return outputs
end

return M
