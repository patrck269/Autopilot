package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local manual = require("manual")

local vx, vy, vz = manual.velocity(0, 0, 0)
A.eq(vx, 0, "idle x")
A.eq(vy, 0, "idle y")
A.eq(vz, 0, "idle z")

vx, vy, vz = manual.velocity(1, 0, 0)
A.eq(vx, 3, "forward")
A.eq(vy, 0, "forward y")
A.eq(vz, 0, "forward z")

vx, vy, vz = manual.velocity(-1, 0, 0)
A.eq(vx, -3, "back")

vx, vy, vz = manual.velocity(1, 1, 0)
A.near(math.sqrt(vx * vx + vy * vy + vz * vz), 3, 1e-9, "diagonal length")
A.near(vx, 3 / math.sqrt(2), 1e-9, "diagonal x")
A.near(vy, 3 / math.sqrt(2), 1e-9, "diagonal y")

local oppose = manual.release_effort(4)
if oppose == 0 or oppose > 0 then
  error("released stick should oppose positive velocity, got " .. tostring(oppose))
end
A.eq(manual.release_effort(-4) > 0, true, "oppose negative velocity")
A.eq(manual.release_effort(0), 0, "settled release")

local raised = manual.x_rpm(100, 0, 3, 5)
if not (raised > 100) then
  error("x rpm should rise when speed is below target, got " .. tostring(raised))
end

local full_side = manual.rcs_rpm(1, 200000000)
if full_side < 1000 or full_side > 100000 then
  error("full sideways rcs rpm out of range: " .. tostring(full_side))
end
local full_vert = manual.rcs_rpm(1, 200000000)
if full_vert < 1000 or full_vert > 100000 then
  error("full vertical rcs rpm out of range: " .. tostring(full_vert))
end
