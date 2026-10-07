local speed = require("speed")
local M = {}
local function result(phase,horiz,vertical,reverse)
  return {phase=phase,horiz_speed=horiz,vertical=vertical,reverse=reverse}
end
function M.step(s)
  local phase=s.phase
  local limit=s.profile=="cruise" and 7 or 50
  local settled=math.abs(s.speed or 0)<=0.1
  if phase=="climb" and s.y>=400 then phase="track" end
  if phase=="track" or phase=="brake" or phase=="approach" then
    if s.dist<=10 and settled then phase="descend"
    elseif s.dist<=10 then return result("brake",0,"hold",true)
    elseif phase=="brake" and not settled then return result("brake",0,"hold",true)
    else
      local accel=math.max(s.accel or 1,0.1)
      local approach=math.min(limit, math.sqrt(2*accel*math.max(s.dist-5,0)))
      if phase=="brake" or phase=="approach" then
        return result("approach",approach,"hold",false)
      elseif s.dist<=speed.brake_distance(s.speed,accel)+5 then
        return result("brake",0,"hold",true)
      end
      return result("track",limit,"hold",false)
    end
  end
  if phase=="descend" then
    if s.dist>10 then return result("approach",math.min(limit,2),"hold",false) end
    if s.y<=329 then phase="hold" else return result("descend",0,"descend",false) end
  end
  if phase=="hold" then
    if s.dist>10 then return result("approach",math.min(limit,2),"hold",false) end
    return result("hold",0,"hold",false)
  end
  return result("climb",0,"climb",false)
end
return M
