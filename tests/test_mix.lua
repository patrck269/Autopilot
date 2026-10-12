package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local mix = require("mix")

local z = mix.zero()
A.eq(z.rsc.rsc17, 0, "zero thrusters")
A.eq(z.rsc.rsc16, 0, "zero elevation")
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

local bow_port, bow_starboard, stern_port, stern_starboard = mix.sides(1, 0, 10)
A.eq(bow_starboard, 10, "starboard bow pulls")
A.eq(stern_starboard, 10, "starboard stern pulls")
A.eq(bow_port, 0, "port bow does not pull on a starboard command")
A.eq(stern_port, 0, "port stern does not pull on a starboard command")

bow_port, bow_starboard, stern_port, stern_starboard = mix.sides(-1, 0, 10)
A.eq(bow_port, 10, "port bow pulls")
A.eq(stern_port, 10, "port stern pulls")
A.eq(bow_starboard, 0, "starboard bow does not pull on a port command")
A.eq(stern_starboard, 0, "starboard stern does not pull on a port command")

bow_port, bow_starboard, stern_port, stern_starboard = mix.sides(0, 1, 10)
A.eq(bow_starboard, 10, "positive yaw pulls bow starboard")
A.eq(stern_port, 10, "positive yaw pulls stern port")
A.eq(bow_port, 0, "positive yaw does not pull bow port")
A.eq(stern_starboard, 0, "positive yaw does not pull stern starboard")
