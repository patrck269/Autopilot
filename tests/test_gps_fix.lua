package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local gps_fix = require("gps_fix")

local x, z = gps_fix.horizontal(100, 70, 200)
A.eq(x, 100, "world x")
A.eq(z, 200, "world z ignores altitude")

local missing_x, missing_z = gps_fix.horizontal(nil)
A.eq(missing_x, nil, "no fix x")
A.eq(missing_z, nil, "no fix z")
