local number = require("numeric")
local M = {}
local RSC, RELAY = {}, {}
for i = 2, 11 do RSC["rsc" .. i] = true end
for _, i in ipairs({2,3,5,6,7,8,9,10}) do RELAY["relay" .. i] = true end
local SIDES = {bottom=true,top=true,front=true,back=true,left=true,right=true}
local function bounded(v, limit) return number.finite(v) and math.abs(v) <= limit end
function M.keep(pending, raw)
  local cmd = M.validate(raw)
  if not cmd then return pending end
  if pending and pending.type == "emergency" and cmd.type ~= "clear_emergency" then return pending end
  return cmd
end
function M.validate(msg)
  if type(msg) ~= "table" then return nil end
  local kind = msg.type
  if kind == "stick" and bounded(msg.x, 1) and bounded(msg.y, 1) and bounded(msg.z, 1) then
    return {type=kind,x=msg.x,y=msg.y,z=msg.z}
  elseif kind == "set_mode" and (msg.mode == "manual" or msg.mode == "semi" or msg.mode == "auto") then
    return {type=kind,mode=msg.mode}
  elseif kind == "set_altitude" and bounded(msg.y, 30000000) then
    return {type=kind,y=msg.y}
  elseif kind == "set_bearing" and number.finite(msg.bearing) then
    return {type=kind,bearing=number.wrap(msg.bearing)}
  elseif kind == "set_speed" and bounded(msg.speed, 1000000) then
    return {type=kind,speed=msg.speed}
  elseif (kind == "set_waypoint" or kind == "return_to_user") and bounded(msg.x, 30000000) and bounded(msg.z, 30000000) then
    return {type=kind,x=msg.x,z=msg.z}
  elseif kind == "set_profile" and (msg.profile == "cruise" or msg.profile == "warp") then
    return {type=kind,profile=msg.profile}
  elseif kind == "emergency" or kind == "clear_emergency" or kind == "diagnostic_exit" or kind == "cancel_jobs" then
    return {type=kind}
  elseif kind == "diagnostic_enter" and type(msg.hover) == "boolean" then
    return {type=kind,hover=msg.hover}
  elseif kind == "diagnostic_elevation" and number.finite(msg.rpm) then
    return {type=kind,rpm=number.clamp(msg.rpm,0,32769)}
  elseif kind == "diagnostic_set" then
    if RSC[msg.device] and number.finite(msg.rpm) then return {type=kind,device=msg.device,rpm=msg.rpm} end
    if RELAY[msg.device] and SIDES[msg.side] and number.finite(msg.level) then
      return {type=kind,device=msg.device,side=msg.side,level=math.floor(number.clamp(msg.level,0,15))}
    end
  end
  return nil
end
-- A queue preserves independent setpoints, coalesces repeated inputs, and gives
-- emergency transitions priority. Bounded even if an untrusted sender floods it.
function M.enqueue(queue, raw)
  queue = queue or {}
  local cmd = M.validate(raw)
  if not cmd then return queue end
  if cmd.type == "emergency" then return {cmd} end
  if queue[1] and queue[1].type == "emergency" then
    if cmd.type == "clear_emergency" then return {queue[1],cmd} end
    return queue
  end
  for i = #queue, 1, -1 do
    if queue[i].type == cmd.type then table.remove(queue,i) end
  end
  if #queue >= 32 then table.remove(queue,1) end
  queue[#queue+1] = cmd
  return queue
end
return M
