local numeric = require("numeric")
local config = require("config")
local M = {}
function M.accel(target,actual,dt,limit,response,feed)
  dt=math.max(dt or 0.05,0.001)
  local error=target-actual
  local a=error/math.max(response or 1,dt)+(feed or 0)
  -- Do not command acceleration past the target during this update.
  if error>=0 then a=math.min(a,error/dt) else a=math.max(a,error/dt) end
  if math.abs(error)<0.01 and not feed then return 0 end
  return numeric.clamp(a,-limit,limit)
end
function M.prop_rpm(a,equilibrium)
  if a==0 then return 0 end
  local rpm=(equilibrium or 430)*(math.abs(a)/10)^(1/1.2)
  return config.clamp_rpm(a<0 and -rpm or rpm)
end
function M.rcs_rpm(a,mass,count)
  if a==0 then return 0 end
  local force=mass*math.abs(a)/(count or 2)
  local rpm=256*(force/100000)^(1/1.2)
  return config.clamp_rpm(a<0 and -rpm or rpm)
end
function M.sides(translation,yaw,mass)
  -- Mix forces before converting to RPM. Translation and yaw must not overwrite
  -- each other's brake pair, nor fire opposing thrusters on the same corner.
  local bow=translation+yaw
  local stern=translation-yaw
  return M.rcs_rpm(math.max(bow,0),mass,2),M.rcs_rpm(math.max(-stern,0),mass,2),
    M.rcs_rpm(math.max(stern,0),mass,2),M.rcs_rpm(math.max(-bow,0),mass,2)
end
return M
