local speed = require("speed")

local M = {}

function M.zero()
  return {
    rsc = {
      rsc2 = 0, rsc3 = 0, rsc4 = 0, rsc5 = 0,
      rsc6 = 0, rsc7 = 0, rsc8 = 0, rsc9 = 0,
      rsc10 = 0, rsc11 = 0,
    },
    relays = {
      relay2 = 0,
      relay3 = false,
      relay5 = false,
      relay6 = false,
      relay7 = false,
      relay8 = false,
      relay9 = false,
      relay10 = false,
    },
  }
end

function M.x(command_speed, ref_speed)
  return command_speed, speed.relay2_level(command_speed, ref_speed)
end

function M.elevation(vertical, hover_rpm, climb_rpm)
  if vertical == "climb" then
    local rpm = climb_rpm
    if hover_rpm > rpm then
      rpm = hover_rpm
    end
    return rpm, false
  end
  if vertical == "reverse" or vertical == "descend" then
    return hover_rpm, false
  end
  return hover_rpm, false
end

function M.sides(vy, yaw, gain)
  local rsc6 = 0
  local rsc7 = 0
  local rsc8 = 0
  local rsc9 = 0
  if vy > 0 then
    rsc6 = vy * gain
    rsc8 = vy * gain
  elseif vy < 0 then
    rsc9 = -vy * gain
    rsc7 = -vy * gain
  end
  if yaw > 0 then
    rsc6 = rsc6 + yaw * gain
    rsc7 = rsc7 + yaw * gain
  elseif yaw < 0 then
    rsc8 = rsc8 - yaw * gain
    rsc9 = rsc9 - yaw * gain
  end
  return rsc6, rsc7, rsc8, rsc9
end

local function pos(value)
  if value > 0 then
    return value
  end
  return 0
end

function M.ups(pitch_err, roll_err, lift, gain)
  local pitch = pitch_err * gain
  local roll = roll_err * gain
  local rsc2 = pos(pitch) + pos(roll) + lift
  local rsc3 = pos(pitch) + pos(-roll) + lift
  local rsc4 = pos(-pitch) + pos(roll) + lift
  local rsc5 = pos(-pitch) + pos(-roll) + lift
  return rsc2, rsc3, rsc4, rsc5
end

return M
