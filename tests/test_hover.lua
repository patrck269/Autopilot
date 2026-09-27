package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local hover = require("hover")

A.eq(hover.adjust(100, 0, 2), 100, "hold")
A.eq(hover.adjust(100, 1, 2), 98, "rising")
A.eq(hover.adjust(100, -1, 2), 102, "sinking")

A.eq(hover.desired_vertical(390, 400, 4, 8), 4, "full climb rate far below")
A.eq(hover.desired_vertical(396, 400, 4, 8), 0, "deadzone holds")
A.eq(hover.desired_vertical(420, 400, 4, 8), -4, "descend when above the band")

local stuck = hover.seek(400, 0, 100, 150, 2, 10, 4, 8)
if not (stuck > 400) then
  error("stuck below target should raise rpm, got " .. tostring(stuck))
end
A.eq(hover.seek(430, 0, 396, 400, 2, 10, 4, 8), 430, "hold rpm inside the deadzone")
local coasting = hover.seek(500, 4, 396, 400, 2, 10, 4, 8)
if not (coasting < 500) then
  error("speed inside the band should be damped, got " .. tostring(coasting))
end
