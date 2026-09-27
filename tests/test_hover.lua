package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local hover = require("hover")

A.eq(hover.adjust(100, 0, 2), 100, "hold")
A.eq(hover.adjust(100, 1, 2), 98, "rising")
A.eq(hover.adjust(100, -1, 2), 102, "sinking")

A.eq(hover.desired_vertical(390, 400, 4), 4, "full climb rate far below")
A.eq(hover.desired_vertical(399, 400, 4), 1, "taper near the target")
A.eq(hover.desired_vertical(405, 400, 4), -4, "descend when above")

local stuck = hover.seek(400, 0, 100, 150, 2, 10, 4)
if not (stuck > 400) then
  error("stuck below target should raise rpm, got " .. tostring(stuck))
end
A.eq(hover.seek(430, 0, 400, 400, 2, 10, 4), 430, "hold rpm at the target")
local near = hover.seek(500, 4, 399, 400, 2, 10, 4)
if not (near < 500) then
  error("fast climb near the target should ease off, got " .. tostring(near))
end
