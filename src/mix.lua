local speed = require("speed")

local M = {}

function M.zero()
  return {
    rsc = {
      rsc12 = 0, rsc13 = 0, rsc14 = 0, rsc15 = 0,
      rsc16 = 0, rsc17 = 0,
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

-- All four RCS are pullers. Positive RPM pulls toward that thruster.
-- Bow port 13, bow starboard 14, stern port 15, stern starboard 12.
-- A left turn pulls bow port and stern starboard. A right turn pulls
-- bow starboard and stern port. A strafe pulls both thrusters on that side.
-- Positive vy is starboard. Positive yaw is a right turn.
-- Returns bow port, bow starboard, stern port, stern starboard.
function M.sides(vy, yaw, gain)
  local sway = vy * gain
  local spin = yaw * gain
  local port = 0
  local starboard = 0
  if sway > 0 then
    starboard = sway
  elseif sway < 0 then
    port = -sway
  end
  local bow_port = port
  local bow_starboard = starboard
  local stern_port = port
  local stern_starboard = starboard
  if spin > 0 then
    bow_starboard = bow_starboard + spin
    stern_port = stern_port + spin
  elseif spin < 0 then
    bow_port = bow_port - spin
    stern_starboard = stern_starboard - spin
  end
  return bow_port, bow_starboard, stern_port, stern_starboard
end

-- Thrust is proportional to signed RPM^1.2. Add forces, rather than RPM,
-- so bearing correction preserves the commanded translation and brake.
function M.add_rpm(a, b)
  local function force(rpm)
    return (rpm < 0 and -1 or 1) * math.abs(rpm)^1.2
  end
  local sum = force(a) + force(b)
  return (sum < 0 and -1 or 1) * math.abs(sum)^(1 / 1.2)
end

return M
