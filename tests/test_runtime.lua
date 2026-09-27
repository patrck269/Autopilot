package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local runtime = require("runtime")

local function recorder()
  local calls = {}
  return {
    calls = calls,
    setTargetSpeed = function(_, rpm)
      calls[#calls + 1] = "rpm " .. tostring(rpm)
    end,
    setOutput = function(_, side, value)
      calls[#calls + 1] = "out " .. side .. " " .. tostring(value)
    end,
    setAnalogOutput = function(_, side, value)
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
A.eq(relay.calls[2], "out bottom 15", "cutoff all sides starts at bottom")
A.eq(#relay.calls, 7, "analog plus six sides")
