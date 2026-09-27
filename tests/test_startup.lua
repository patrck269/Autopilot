package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local startup = require("startup")
local config = require("config")

local cfg = config.default()
A.eq(cfg.climb_rpm, 256, "climb")
A.eq(cfg.names.rsc10, "Create_RotationSpeedController_10", "default network name")
A.eq(cfg.names.relay2, "redstone_relay_2", "relay name")
A.eq(cfg.names.speedometer, "Create_Speedometer_0", "speedometer name")
A.eq(cfg.names.stressometer, "Create_Stressometer_0", "stressometer name")
A.eq(cfg.names.relay4, nil, "no relay 4")

local missing = startup.missing({ rsc10 = true, relay2 = true }, { "rsc10", "relay2", "rsc11" })
A.eq(#missing, 1, "one missing")
A.eq(missing[1], "rsc11", "missing name")
