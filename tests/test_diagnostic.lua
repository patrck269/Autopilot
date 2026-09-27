package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local diagnostic = require("diagnostic")

local clamped = diagnostic.apply({ device = "rsc10", rpm = 100 }, nil)
A.eq(clamped.rsc.rsc10, 32, "upper clamp")
A.eq(clamped.rsc.rsc11, 0, "others zero")

local neg = diagnostic.apply({ device = "rsc10", rpm = -100 }, nil)
A.eq(neg.rsc.rsc10, -32, "lower clamp")

local relay = diagnostic.apply({ device = "relay7", side = "bottom", level = 20 }, nil)
A.eq(relay.diag_relay.level, 15, "level clamp")
A.eq(relay.diag_relay.side, "bottom", "side")
A.eq(relay.relays.relay7, false, "flight cutoff stays false")

local hover = diagnostic.apply(
  { device = "relay7", side = "top", level = 15 },
  { enabled = true, rpm = 180 }
)
A.eq(hover.diag_relay, nil, "corner cutoff locked")
A.eq(hover.rsc.rsc11, 180, "elevation set past 32")

local blocked = diagnostic.apply({ device = "rsc11", rpm = 10 }, { enabled = true, rpm = 90 })
A.eq(blocked.rsc.rsc11, 90, "rsc11 not the test device")
