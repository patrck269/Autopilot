package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local runtime = require("runtime")

local function recorder()
  local calls = {}
  return {
    calls = calls,
    setTargetSpeed = function(rpm)
      calls[#calls + 1] = "rpm " .. tostring(rpm)
    end,
    setOutput = function(side, value)
      calls[#calls + 1] = "out " .. side .. " " .. tostring(value)
    end,
    setAnalogOutput = function(side, value)
      calls[#calls + 1] = "analog " .. side .. " " .. tostring(value)
    end,
  }
end

local rsc = recorder()
local relay = recorder()
runtime.apply({
  rsc = { rsc10 = -12 },
  relays = { relay2 = 4, relay7 = true },
  diag_relay = nil,
}, { rsc10 = rsc, relay2 = relay, relay7 = relay })
A.eq(rsc.calls[1], "rpm -12", "rsc")
A.eq(relay.calls[1], "analog bottom 4", "stepped throttle")
A.eq(relay.calls[2], "out bottom true", "cutoff all sides starts at bottom")
A.eq(#relay.calls, 7, "analog plus six sides")

local config = require("config")
local limit = config.default().max_rpm
local high_x = recorder()
local high_z = recorder()
runtime.apply({
  rsc = { rsc10 = 50000, rsc11 = -50000 },
  relays = {},
}, { rsc10 = high_x, rsc11 = high_z })
A.eq(high_x.calls[1], "rpm " .. tostring(limit), "high target is clamped")
A.eq(high_z.calls[1], "rpm " .. tostring(-limit), "negative target is clamped")
