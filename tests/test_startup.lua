package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local startup = require("startup")
local config = require("config")

local cfg = config.default()
A.eq(cfg.climb_rpm, 256, "climb")
A.eq(cfg.names.rsc17, "Create_RotationSpeedController_17", "thrusters")
A.eq(cfg.names.rsc16, "Create_RotationSpeedController_16", "elevation")
A.eq(cfg.names.rsc13, "Create_RotationSpeedController_13", "bow port")
A.eq(cfg.names.rsc14, "Create_RotationSpeedController_14", "bow starboard")
A.eq(cfg.names.rsc15, "Create_RotationSpeedController_15", "stern port")
A.eq(cfg.names.rsc12, "Create_RotationSpeedController_12", "stern starboard")
A.eq(cfg.names.relay2, nil, "old relay is not required")
A.eq(cfg.names.speedometer, "Create_Speedometer_1", "speedometer 1 is elevation rpm")
A.eq(cfg.names.stressometer, "Create_Stressometer_2", "stressometer 2 is main engine stress")
A.eq(cfg.names.rsc2, nil, "no old controller 2")
A.eq(cfg.names.rsc6, nil, "no old side controller")
A.eq(cfg.side_sign.rsc13, 1, "bow port sign")
A.eq(cfg.side_sign.rsc14, 1, "bow starboard sign")
for _, key in ipairs(config.required_names(cfg)) do
  if key == "rsc2" or key == "rsc3" or key == "rsc4" or key == "rsc5" then
    error("bottom rcs is still required: " .. key)
  end
end

local missing = startup.missing({ rsc17 = true, relay2 = true }, { "rsc17", "relay2", "rsc16" })
A.eq(#missing, 1, "one missing")
A.eq(missing[1], "rsc16", "missing name")
