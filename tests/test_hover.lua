package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local hover = require("hover")

A.eq(hover.adjust(100, 0, 2), 100, "hold")
A.eq(hover.adjust(100, 1, 2), 98, "rising")
A.eq(hover.adjust(100, -1, 2), 102, "sinking")

local shell = hover.desired_vertical(100, 400, 8, 20)
A.near(shell, 280 / 15, 1e-9, "a far climb reaches the 20-block shell in 15 seconds")
A.near(hover.desired_vertical(0, 100000, 8, 20), hover.climb_limit(), 1e-9, "an extreme climb stays stoppable with the reverser")
A.near(hover.desired_vertical(400, 100, 8, 20), -(280 / 15), 1e-9, "a far descent still reaches the shell in 15 seconds")
A.near(hover.desired_vertical(10000, 0, 8, 20), -hover.descent_limit(), 1e-9, "an extreme descent stays stoppable")
if hover.climb_limit() <= 280 / 15 then
  error("climb stop is still limited to one g")
end
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
A.eq(hover.remember(memory, 100, 430, 102, 0), false, "do not remember before arrival")
A.eq(hover.recall(memory, 100), nil, "unreached altitude has no rpm")
A.eq(hover.remember(memory, 100, 430, 100, 1), false, "do not remember while still moving")
A.eq(hover.remember(memory, 100, 430, 100, 0), true, "remember the rpm that arrived")
A.eq(hover.recall(memory, 100), 430, "recall the exact set altitude")
A.eq(hover.recall(memory, 101), nil, "one block away is a different altitude")
A.eq(hover.recall(memory, 102), nil, "two blocks away is a different altitude")
A.eq(hover.remember(memory, 250, 440, 250.4, 0), true, "settled on the set altitude")
A.eq(hover.recall(memory, 250), 440, "exact 250")
A.eq(hover.recall(memory, 250.4), nil, "the ship position is not a second key")

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
