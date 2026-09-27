package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local hover = require("hover")

A.eq(hover.adjust(100, 0, 2), 100, "hold")
A.eq(hover.adjust(100, 1, 2), 98, "rising")
A.eq(hover.adjust(100, -1, 2), 102, "sinking")

A.near(hover.desired_vertical(100, 400, 8, 20), 280 / 15, 1e-9, "reach the 20-block shell in 15 seconds")
A.near(hover.desired_vertical(385, 400, 8, 20), 7 / 60, 1e-9, "slow remainder inside 20 blocks")
A.eq(hover.desired_vertical(396, 400, 8, 20), 0, "deadzone holds")

local far = hover.seek(400, 0, 100, 400, 2, 10, 8, 20, 0.2, 1)
local near = hover.seek(400, 0, 385, 400, 2, 10, 8, 20, 0.2, 1)
if not (far - 400 > near - 400) then
  error("far adjustment should exceed the near one")
end
if not (near - 400 < 2) then
  error("near adjustment should stay under 2 rpm, got " .. tostring(near - 400))
end
A.eq(hover.seek(430, 0, 396, 400, 2, 10, 8, 20, 0.2, 1), 430, "hold rpm inside the deadzone")
local coasting = hover.seek(500, 4, 396, 400, 2, 10, 8, 20, 0.2, 1)
if not (coasting < 500 and 500 - coasting < 1) then
  error("deadzone damping should be under 1 rpm, got " .. tostring(500 - coasting))
end
