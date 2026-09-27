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

local memory = {}
hover.remember(memory, 100.2, 430)
A.eq(hover.recall(memory, 100), 430, "recall the altitude just flown")
A.eq(hover.recall(memory, 101.4), 430, "recall a nearby altitude")

local descent = hover.simulate_descent(450, 400, 8, 430, 0.05)
A.eq(descent.reverser, false, "reverser stays off")
if not (descent.lowest_rpm < 430) then
  error("elevation rpm should fall, got " .. tostring(descent.lowest_rpm))
end
if not descent.inside then
  error("craft should be inside the deadzone, altitude " .. tostring(descent.altitude))
end
if descent.min_altitude < 400 - 8 then
  error("descent crossed the far side at " .. tostring(descent.min_altitude))
end
A.eq(hover.use_reverser(false), false, "normal flight keeps the reverser off")
A.eq(hover.use_reverser(true), true, "failed prop may use the reverser")
