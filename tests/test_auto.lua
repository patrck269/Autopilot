package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local auto = require("auto")

local climb = auto.step({
  phase = "climb", y = 100, dist = 500, speed = 0, accel = nil, profile = "warp",
})
A.eq(climb.phase, "climb", "still climbing")
A.eq(climb.horiz_speed, 0, "no horizontal until 400")
A.eq(climb.vertical, "climb", "climb vertical")
A.eq(climb.reverse, false, "not reversing")

local track = auto.step({
  phase = "climb", y = 400, dist = 500, speed = 0, accel = nil, profile = "warp",
})
A.eq(track.phase, "track", "starts track at 400")
A.eq(track.horiz_speed, 50, "warp")

local cruise = auto.step({
  phase = "track", y = 400, dist = 500, speed = 7, accel = nil, profile = "cruise",
})
A.eq(cruise.horiz_speed, 7, "cruise under 8")

local brake = auto.step({
  phase = "track", y = 400, dist = 20, speed = 10, accel = 2, profile = "warp",
})
A.eq(brake.phase, "brake", "brake inside v^2/2a of 25")
A.eq(brake.reverse, true, "reverse")
A.eq(brake.horiz_speed, 0, "brake target")

local keep = auto.step({
  phase = "track", y = 400, dist = 40, speed = 10, accel = 2, profile = "warp",
})
A.eq(keep.phase, "track", "outside brake distance")

local no_sample = auto.step({
  phase = "track", y = 400, dist = 20, speed = 10, accel = nil, profile = "warp",
})
A.eq(no_sample.phase, "brake", "fallback acceleration brakes without a sample")

local arrived = auto.step({
  phase = "brake", y = 400, dist = 10, speed = 0, accel = 2, profile = "warp",
})
A.eq(arrived.phase, "descend", "within 10")
A.eq(arrived.vertical, "descend", "descend")
A.eq(arrived.horiz_speed, 0, "stop horizontal")

local done = auto.step({
  phase = "descend", y = 329, dist = 0, speed = 0, accel = 2, profile = "warp",
})
A.eq(done.phase, "hold", "at 329")
A.eq(done.vertical, "hold", "hold height")
