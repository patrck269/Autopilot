local config = require("config")
local unpack = unpack or table.unpack

local SIDES = { "bottom", "top", "front", "back", "left", "right" }

local M = {}

-- Create deletes a speed controller whose target changes too often. Each new
-- integer detaches that kinetic network and attaches it again, and the
-- controller breaks once its flicker score passes 128. Hold the last integer
-- across this many applies, and never longer than hold_seconds, so a slow
-- tick cannot freeze a stale climb RPM. Zero still goes out at once. A sign
-- change stops at zero before it reverses.
M.speed_hold = 30
M.hold_seconds = 1.5

local last_rpm = {}
local hold_for = {}
local held_since = {}
local arrived_at = {}
local chase_left = {}

local function write_all(device, value)
  for _, side in ipairs(SIDES) do
    device.setOutput(side, value)
  end
end

local function integer_rpm(rpm)
  local clamped = config.clamp_rpm(rpm)
  if clamped >= 0 then
    return math.floor(clamped)
  end
  return -math.floor(-clamped)
end

-- After the asked-for integer is held, a few partial steps may follow it at
-- once so a stop can reach the next integer. Further partial steps are one
-- per four applies, which keeps a 400-apply window under the flicker score.
-- The step that lands on the asked-for integer is not delayed.
local APPROACH_HOLD = 3
local BURST = 3

local function remember(name, rpm, arrived)
  last_rpm[name] = rpm
  arrived_at[name] = arrived
  held_since[name] = os.clock()
  if arrived then
    hold_for[name] = M.speed_hold
    chase_left[name] = BURST
    return
  end
  local left = chase_left[name] or 0
  if left > 1 then
    chase_left[name] = left - 1
    hold_for[name] = 0
  else
    chase_left[name] = 0
    hold_for[name] = APPROACH_HOLD
  end
end

local function hold_open(name, hold)
  if hold <= 0 then
    return true
  end
  local started = held_since[name]
  return started ~= nil and os.clock() - started >= M.hold_seconds
end

-- A step of about 100 RPM detaches the elevation network hard enough to
-- break the block. The first target, when the controller has none yet, and
-- an immediate zero may be any size. A known target is approached in
-- smaller steps. Only the integer that was asked for is held.
local ELEVATION = "rsc11"
local ELEVATION_STEP = 99

local function limit_step(name, previous, sending)
  if name ~= ELEVATION or previous == nil or sending == 0 then
    return sending
  end
  local delta = sending - previous
  if delta >= 100 then
    return previous + ELEVATION_STEP
  end
  if delta <= -100 then
    return previous - ELEVATION_STEP
  end
  return sending
end

local function signs_differ(previous, wanted)
  return previous ~= 0 and wanted ~= 0 and ((previous > 0) ~= (wanted > 0))
end

local function apply_targets(outputs, devices)
  for name, rpm in pairs(outputs.rsc) do
    local device = devices[name]
    if device ~= nil and device.setTargetSpeed ~= nil then
      local wanted = integer_rpm(rpm)
      local previous = last_rpm[name]
      if previous == nil and device.getTargetSpeed ~= nil then
        local current = device.getTargetSpeed()
        if type(current) == "number" then
          previous = integer_rpm(current)
          last_rpm[name] = previous
        end
      end
      local hold = hold_for[name] or 0
      local sending = wanted
      local write = false
      if previous == nil then
        sending = limit_step(name, previous, sending)
        remember(name, sending, true)
        write = true
      elseif wanted == previous then
        if hold > 0 then
          hold_for[name] = hold - 1
        end
      elseif signs_differ(previous, wanted) then
        sending = 0
        remember(name, sending, true)
        write = true
      elseif wanted == 0 or previous == 0 or hold_open(name, hold)
          or (arrived_at[name] == false and math.abs(wanted - previous) < 100) then
        sending = limit_step(name, previous, wanted)
        if sending ~= previous then
          remember(name, sending, sending == wanted)
          write = true
        end
      else
        if hold > 0 then
          hold_for[name] = hold - 1
        end
      end
      if write then
        device.setTargetSpeed(sending)
      end
    end
  end
  local relay2 = devices.relay2
  if relay2 ~= nil and relay2.setAnalogOutput ~= nil then
    relay2.setAnalogOutput("bottom", outputs.relays.relay2 or 0)
  end
  for name, on in pairs(outputs.relays) do
    if name ~= "relay2" then
      local device = devices[name]
      if device ~= nil and device.setOutput ~= nil then
        write_all(device, on == true)
      end
    end
  end
  if outputs.diag_relay ~= nil then
    local device = devices[outputs.diag_relay.device]
    if device ~= nil and device.setOutput ~= nil then
      for _, side in ipairs(SIDES) do
        local value = 0
        if side == outputs.diag_relay.side then
          value = outputs.diag_relay.level
        end
        if device.setAnalogOutput ~= nil then
          device.setAnalogOutput(side, value)
        else
          device.setOutput(side, value ~= 0)
        end
      end
    end
  end
end

function M.apply(outputs, devices)
  local failures = {}
  local guarded = {}
  for name, device in pairs(devices) do
    local device_name = name
    guarded[name] = setmetatable({}, {
      __index = function(_, method)
        local fn = device[method]
        if type(fn) ~= "function" then
          return fn
        end
        return function(...)
          local results = { pcall(fn, ...) }
          if not results[1] then
            failures[#failures + 1] = device_name .. ": " .. tostring(results[2])
            return nil
          end
          return unpack(results, 2)
        end
      end,
    })
  end
  apply_targets(outputs, guarded)
  if #failures > 0 then
    error(table.concat(failures, "; "), 0)
  end
end

return M
