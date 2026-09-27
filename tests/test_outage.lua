package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local outage = require("outage")

local kind, which = outage.classify(0, 0, 0.2)
A.eq(kind, nil, "calm")

kind, which = outage.classify(0.4, -0.4, 0.2)
A.eq(kind, "corner", "corner kind")
A.eq(which, "port_bow", "nose down and port down")

kind, which = outage.classify(0.4, 0.4, 0.2)
A.eq(which, "starboard_bow", "nose down and starboard down")

kind, which = outage.classify(-0.4, -0.4, 0.2)
A.eq(which, "port_stern", "nose up and port down")

kind, which = outage.classify(-0.4, 0.4, 0.2)
A.eq(which, "starboard_stern", "nose up and starboard down")

kind, which = outage.classify(0.05, -0.5, 0.2)
A.eq(kind, "side", "side kind")
A.eq(which, "port", "port side")

kind, which = outage.classify(0.05, 0.5, 0.2)
A.eq(which, "starboard", "starboard side")

A.eq(outage.opposite("port_bow"), "starboard_stern", "opposite pb")
A.eq(outage.opposite("starboard_bow"), "port_stern", "opposite sb")
A.eq(outage.opposite("starboard_stern"), "port_bow", "opposite ss")
A.eq(outage.opposite("port_stern"), "starboard_bow", "opposite ps")

local cut = outage.cutoffs("corner", "port_bow")
A.eq(cut.relay9, true, "cut starboard stern")
A.eq(cut.relay7, false, "failed corner relay stays off")
A.eq(cut.relay5, false, "master Z cutoff stays off")

A.near(outage.live_prop_scale(0, "port"), 1, 1e-9, "level scale")
A.near(outage.live_prop_scale(-0.5, "port"), 0.5, 1e-9, "port low")
A.eq(outage.live_prop_scale(-2, "port"), 0, "port scale floor")
A.near(outage.live_prop_scale(0.25, "starboard"), 0.75, 1e-9, "starboard low")

local fall = outage.fall_cutoffs()
A.eq(fall.relay5, true, "master cut")
A.eq(fall.relay7, true, "pb cut")
A.eq(fall.relay8, true, "sb cut")
A.eq(fall.relay9, true, "ss cut")
A.eq(fall.relay10, true, "ps cut")
