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
A.eq(s6, 10, "port bow translates starboard")
A.eq(s8, 10, "port aft translates starboard")
A.eq(s7, 0, "starboard aft stays")
A.eq(s9, 0, "starboard bow stays")

s6, s7, s8, s9 = mix.sides(0, 1, 10)
A.eq(s6, 10, "yaw bow port side")
A.eq(s7, 10, "yaw stern starboard side")
A.eq(s8, 0, "yaw cancels the other port")
A.eq(s9, 0, "yaw cancels the other starboard")

local u2, u3, u4, u5 = mix.ups(1, 0, 0, 5)
A.eq(u2, 5, "bow starboard")
A.eq(u3, 5, "bow port")
A.eq(u4, 0, "stern starboard quiet")
A.eq(u5, 0, "stern port quiet")

u2, u3, u4, u5 = mix.ups(0, 1, 4, 5)
A.eq(u2, 9, "starboard bow lift plus roll")
A.eq(u4, 9, "starboard stern")
A.eq(u3, 4, "port bow lift only")
A.eq(u5, 4, "port stern lift only")
