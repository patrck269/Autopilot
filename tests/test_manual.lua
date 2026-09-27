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
