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

-- Side units are reversible clockwork propellers. Positive vy is starboard:
-- the port pair spins forward and the starboard pair spins in reverse.
-- Positive yaw spins rsc6 and rsc7 forward and reverses rsc8 and rsc9.
function M.sides(vy, yaw, gain)
  local sway = vy * gain
  local spin = yaw * gain
  local rsc6 = sway + spin
  local rsc8 = sway - spin
  local rsc7 = -sway + spin
  local rsc9 = -sway - spin
  return rsc6, rsc7, rsc8, rsc9
end

return M
