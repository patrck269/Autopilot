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

local function reload()
  package.loaded.runtime = nil
  return require("runtime")
end

runtime = reload()
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

runtime = reload()
local held = recorder()
local function push(rpm)
  local before = #held.calls
  runtime.apply({ rsc = { rsc11 = rpm }, relays = {} }, { rsc11 = held })
  if #held.calls == before then
    return nil
  end
  return held.calls[#held.calls]
end

A.eq(push(100.9), "rpm 100", "z target is an integer the controller can store")
A.eq(push(100.2), nil, "a fraction of the same integer does not call setTargetSpeed")
A.eq(push(25000), nil, "a new z target waits instead of rewriting the controller")
local changes = 0
local previous = 100
for n = 1, 200 do
  local sent = push(n)
  if sent ~= nil then
    local number = tonumber(string.match(sent, "%-?%d+"))
    if number ~= previous then
      changes = changes + 1
      if math.abs(number - previous) >= 100 and number ~= 0 then
        error("elevation step " .. tostring(number - previous))
      end
      previous = number
    end
  end
end
if changes > 8 then
  error("z target changed too often: " .. tostring(changes))
end
A.eq(push(0), "rpm 0", "zero cuts z immediately")
A.eq(push(400), "rpm 99", "leaving zero steps by less than 100")
local function until_change(from, rpm)
  local sent = from
  local waits = 0
  while sent == from and waits <= runtime.speed_hold + 2 do
    local next_sent = push(rpm)
    waits = waits + 1
    if next_sent ~= nil then
      sent = next_sent
    end
  end
  return sent
end
A.eq(until_change("rpm 99", -400), "rpm 0", "a sign change stops before the reverse")
A.eq(push(-400), "rpm -99", "the reversed target steps by less than 100")
A.eq(until_change("rpm -99", 90000), "rpm 0", "an opposite over-max command stops first")
A.eq(push(90000), "rpm 99", "leaving zero after the stop steps by less than 100")

runtime = reload()
local fresh_high = recorder()
runtime.apply({ rsc = { rsc11 = 90000 }, relays = {} }, { rsc11 = fresh_high })
A.eq(fresh_high.calls[1], "rpm " .. tostring(limit), "a first elevation write may be the clamped maximum")

runtime = reload()
local moving = recorder()
for i = 1, 400 do
  runtime.apply({ rsc = { rsc11 = i * 20 }, relays = {} }, { rsc11 = moving })
end
if #moving.calls >= 128 then
  error("elevation setTargetSpeed called " .. tostring(#moving.calls) .. " times in 400 applies")
end
if #moving.calls < 2 then
  error("a moving elevation target never changed the controller")
end
local last_written = nil
for i = 1, #moving.calls do
  local number = tonumber(string.match(moving.calls[i], "%-?%d+"))
  if last_written ~= nil and number ~= 0 and math.abs(number - last_written) >= 100 then
    error("consecutive elevation integers differ by " .. tostring(number - last_written))
  end
  last_written = number
end
print("elevation writes " .. tostring(#moving.calls))

runtime = reload()
local attempts = 0
local unreliable = {setTargetSpeed = function()
  attempts = attempts + 1
  if attempts == 1 then error("temporary detach") end
end}
local zero = {rsc = {rsc10 = 0}, relays = {}}
A.eq(pcall(runtime.apply, zero, {rsc10 = unreliable}), false, "failed stop reported")
runtime.apply(zero, {rsc10 = unreliable})
A.eq(attempts, 2, "failed zero write is retried")

runtime = reload()
local actual, writes = 100, 0
local changed = {
  getTargetSpeed = function() return actual end,
  setTargetSpeed = function(rpm) actual = rpm; writes = writes + 1 end,
}
runtime.apply(zero, {rsc10 = changed})
actual = 100 -- An independent controller or replacement device changed it.
runtime.apply(zero, {rsc10 = changed})
A.eq(actual, 0, "external target change cannot bypass zero")
A.eq(writes, 2, "external target change is corrected")
