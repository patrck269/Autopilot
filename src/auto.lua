local speed = require("speed")

local M = {}

local function result(phase, horiz, vertical, reverse)
  return {
    phase = phase,
    horiz_speed = horiz,
    vertical = vertical,
    reverse = reverse,
  }
end

function M.step(s)
  local phase = s.phase
  if phase == "climb" and s.y >= 400 then
    if s.dist <= 10 then
      phase = "descend"
    else
      phase = "track"
    end
  end
  if phase == "track" then
    local limit = 50
    if s.profile == "cruise" then
      limit = 7
    end
    if s.dist <= 10 then
      phase = "descend"
    elseif s.accel ~= nil and s.accel > 0 and s.dist <= speed.brake_distance(s.speed, s.accel) then
      phase = "brake"
    else
      return result(phase, limit, "hold", false)
    end
  end
  if phase == "brake" then
    if s.dist <= 10 then
      phase = "descend"
    else
      return result(phase, 0, "hold", true)
    end
  end
  if phase == "descend" then
    if s.y <= 329 then
      phase = "hold"
    else
      return result(phase, 0, "descend", false)
    end
  end
  if phase == "hold" then
    return result(phase, 0, "hold", false)
  end
  return result("climb", 0, "climb", false)
end

return M
