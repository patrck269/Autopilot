package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local mix = require("mix")

local z = mix.zero()
A.eq(z.rsc.rsc10, 0, "zero x")
A.eq(z.relays.relay2, 0, "zero relay2")
A.eq(z.relays.relay6, false, "zero reverser")

local rpm, level = mix.x(-10, 35)
A.eq(rpm, -10, "reverse keeps sign")
A.eq(level, 4, "magnitude level")

local hold_rpm, hold_rev = mix.elevation("hold", 80, 200)
A.eq(hold_rpm, 80, "hover rpm")
A.eq(hold_rev, false, "hover not reversed")

local climb_rpm, climb_rev = mix.elevation("climb", 80, 200)
A.eq(climb_rpm, 200, "climb rpm")
A.eq(climb_rev, false, "climb forward")

local sought_rpm, sought_rev = mix.elevation("climb", 430, 256)
A.eq(sought_rpm, 430, "climb follows a higher hover setting")
A.eq(sought_rev, false, "sought climb stays forward")

local down_rpm, down_rev = mix.elevation("reverse", 80, 200)
A.eq(down_rpm, 80, "reverse uses hover magnitude")
A.eq(down_rev, false, "normal reverse does not use the reverser")

local desc_rpm, desc_rev = mix.elevation("descend", 80, 200)
A.eq(desc_rpm, 80, "descend rpm")
A.eq(desc_rev, false, "descend does not use the reverser")

local s6, s7, s8, s9 = mix.sides(1, 0, 10)
A.eq(s6, 10, "port bow prop pushes starboard")
A.eq(s8, 10, "port aft prop pushes starboard")
A.eq(s7, -10, "starboard aft prop reverses toward starboard")
A.eq(s9, -10, "bow starboard prop reverses toward starboard")

s6, s7, s8, s9 = mix.sides(0, 1, 10)
A.eq(s6, 10, "positive yaw spins port bow")
A.eq(s7, 10, "positive yaw spins starboard aft")
A.eq(s8, -10, "positive yaw reverses port aft")
A.eq(s9, -10, "positive yaw reverses bow starboard")

s6, s7, s8, s9 = mix.sides(0, -1, 10)
A.eq(s6, -10, "negative yaw reverses port bow")
A.eq(s8, 10, "negative yaw spins port aft")
A.eq(s7, -10, "negative yaw reverses starboard aft")
A.eq(s9, 10, "negative yaw spins bow starboard")
