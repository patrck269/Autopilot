local numeric = require("numeric")
local M = {}
local function dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
function M.rotate(q,v)
  local u=q.v or q
  local w=q.a or q.w
  assert(numeric.finite(w) and numeric.finite(u.x) and numeric.finite(u.y) and numeric.finite(u.z), "invalid quaternion")
  local norm=math.sqrt(w*w+dot(u,u)); assert(norm>0,"zero quaternion")
  local x,y,z=u.x/norm,u.y/norm,u.z/norm; w=w/norm
  local tx,ty,tz=2*(y*v.z-z*v.y),2*(z*v.x-x*v.z),2*(x*v.y-y*v.x)
  return {x=v.x+w*tx+y*tz-z*ty,y=v.y+w*ty+z*tx-x*tz,z=v.z+w*tz+x*ty-y*tx}
end
function M.sample(pos,vel,q,omega,dt,axes)
  axes=axes or {forward={x=1,y=0,z=0},right={x=0,y=0,z=-1},up={x=0,y=1,z=0}}
  for _,vector in ipairs({pos,vel,omega}) do
    assert(type(vector)=="table" and numeric.finite(vector.x) and numeric.finite(vector.y) and numeric.finite(vector.z),"invalid ship telemetry")
  end
  for _,axis in ipairs({axes.forward,axes.right,axes.up}) do
    assert(math.abs(dot(axis,axis)-1)<1e-6,"ship frame axes must be unit vectors")
  end
  assert(math.abs(dot(axes.forward,axes.right))<1e-6 and math.abs(dot(axes.forward,axes.up))<1e-6 and math.abs(dot(axes.right,axes.up))<1e-6,"ship frame axes must be orthogonal")
  local f,r,u=M.rotate(q,axes.forward),M.rotate(q,axes.right),M.rotate(q,axes.up)
  return {x=pos.x,y=pos.y,z=pos.z,vx=vel.x,vy=vel.y,vz=vel.z,
    forward_speed=dot(vel,f),side_speed=dot(vel,r),up_speed=dot(vel,u),
    heading=numeric.atan2(-f.z,f.x),pitch=-math.asin(numeric.clamp(f.y,-1,1)),roll=-math.asin(numeric.clamp(r.y,-1,1)),
    pitch_rate=dot(omega,r),roll_rate=-dot(omega,f),yaw_rate=dot(omega,u),dt=dt,
    forward=f,right=r,up=u}
end
function M.project(ship,x,z)
  local f=ship.forward or {x=math.cos(ship.heading or 0),z=-math.sin(ship.heading or 0)}
  local r=ship.right or {x=-math.sin(ship.heading or 0),z=-math.cos(ship.heading or 0)}
  return x*f.x+z*f.z,x*r.x+z*r.z
end
return M
