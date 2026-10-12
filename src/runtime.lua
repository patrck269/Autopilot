local config = require("config")
local stress = require("stress")
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
local chase_left = {}
local flicker = {}
local flicker_clock = {}
-- Last getTargetSpeed integer already accounted for. A lagging controller
-- keeps returning the old value after setTargetSpeed(0); writing zero again
-- on every tick rebuilds the kinetic network and fills the flicker budget.
local seen_speed = {}
-- relax() arms one apply that does not adopt the stopped controller, so the
-- next elevation command is a first write rather than a 99 RPM step from 0.
local fresh = false

local function forget(name)
  last_rpm[name] = nil
  hold_for[name] = nil
  held_since[name] = nil
  chase_left[name] = nil
end

function M.relax()
  last_rpm = {}
  hold_for = {}
  held_since = {}
  chase_left = {}
  flicker = {}
  flicker_clock = {}
  seen_speed = {}
  fresh = true
end

local relay_state = {}

local function relay_write(name, side, value, send)
  local key = name .. "\0" .. side
  if relay_state[key] == value then
    return
  end
  relay_state[key] = value
  send()
end

local function write_all(name, device, value)
  for _, side in ipairs(SIDES) do
    relay_write(name, side, value, function()
      device.setOutput(side, value)
    end)
  end
end

local function integer_rpm(rpm)
  local clamped = config.clamp_rpm(rpm)
  if clamped >= 0 then
    return math.floor(clamped)
  end
  return -math.floor(-clamped)
end

-- A powered target change stops and restarts the network: +10 flicker,
-- decaying by one per game tick. The rebuild runs on the server thread, so a
-- burst of them freezes every screen until it returns. Later changes wait
-- for the full hold instead of following on the next tick.
local FLICKER_LIMIT = 80 -- Reserve room for an immediate stop and propagation.

local function flicker_score(name)
  local now = os.clock() -- ComputerCraft game time, including server tick lag.
  local clock = flicker_clock[name] or now
  local ticks = math.max(0, math.floor((now - clock) / 0.05 + 1e-6))
  flicker[name] = math.max(0, (flicker[name] or 0) - ticks)
  flicker_clock[name] = clock + ticks * 0.05
  return flicker[name]
end

local function remember(name, rpm, _arrived)
  last_rpm[name] = rpm
  held_since[name] = os.clock()
  hold_for[name] = M.speed_hold
  chase_left[name] = 0
end

local function hold_open(name, hold)
  if hold <= 0 then
    return true
  end
  local started = held_since[name]
  return started ~= nil and os.clock() - started >= M.hold_seconds
end

-- Retain the elevation slew limit for flight behavior. Create has no
-- 100-RPM destruction threshold; every changed integer costs flicker.
local ELEVATION = "rsc16"
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

local function apply_targets(outputs, devices, options)
  local applied = {rsc={}, relays=outputs.relays, diag_relay=outputs.diag_relay}
  local previous_targets = {}
  local skip_read = fresh
  fresh = false
  for name, rpm in pairs(outputs.rsc) do
    local device = devices[name]
    if device ~= nil and device.setTargetSpeed ~= nil then
      local wanted = integer_rpm(rpm)
      local previous = last_rpm[name]
      if device.getTargetSpeed ~= nil and not skip_read then
        local current = device.getTargetSpeed()
        if type(current) == "number" then
          current = integer_rpm(current)
          -- An unchanged reading is the value we already handled. Adopting it
          -- again turns a held zero into a new target and rewrites it.
          if current ~= seen_speed[name] then
            seen_speed[name] = current
            if current ~= previous then
              forget(name)
              previous = current
              last_rpm[name] = current
            end
          end
        end
      end
      local hold = hold_for[name] or 0
      local sending = wanted
      if previous == nil then
        sending = limit_step(name, previous, sending)
      elseif wanted == previous then
        if hold > 0 then
          hold_for[name] = hold - 1
        end
      elseif signs_differ(previous, wanted) then
        sending = 0
      elseif wanted == 0 or previous == 0 or hold_open(name, hold) then
        sending = limit_step(name, previous, wanted)
      else
        sending = previous
        if hold > 0 then
          hold_for[name] = hold - 1
        end
      end
      applied.rsc[name] = sending
      previous_targets[name] = previous
    else
      forget(name)
    end
  end

  local budget_room
  if options then
    -- Budget the integers that will actually be held together, rather than
    -- the requested outputs that the hold or elevation step may postpone.
    local room = options.budget or stress.budget(options.measured, options.capacity,
      stress.consumed({rsc=previous_targets}))
    budget_room = room
    stress.limit_budget(applied, room)
    for name, rpm in pairs(applied.rsc) do
      rpm = integer_rpm(rpm)
      local previous = previous_targets[name]
      if name == ELEVATION and previous ~= nil and rpm ~= 0
          and math.abs(rpm - previous) >= 100 then
        -- An abrupt loss of capacity cannot be solved by holding an unsafe
        -- elevation speed. Zero is the actuator's permitted immediate stop.
        rpm = 0
      end
      applied.rsc[name] = rpm
    end
  end
  -- Budget shedding, zero restarts, and reversals also pass this gate. A
  -- reduction that cannot wait stops immediately; an increase waits. This
  -- preserves the stress budget and leaves emergency zero unconditional.
  for name, rpm in pairs(applied.rsc) do
    local previous = previous_targets[name]
    if rpm ~= previous and rpm ~= 0 and flicker_score(name) + 10 > FLICKER_LIMIT then
      applied.rsc[name] = previous or 0
      if budget_room ~= nil and stress.consumed(applied) > budget_room then
        applied.rsc[name] = 0
      end
    end
  end
  local writes = {}
  for name, rpm in pairs(applied.rsc) do
    if rpm ~= previous_targets[name] then writes[#writes+1] = name end
  end
  table.sort(writes, function(a,b)
    local a_reduces = math.abs(applied.rsc[a]) <= math.abs(previous_targets[a] or 0)
    local b_reduces = math.abs(applied.rsc[b]) <= math.abs(previous_targets[b] or 0)
    if a_reduces ~= b_reduces then return a_reduces end
    return a < b
  end)
  local reduction_failed = false
  local failed = nil
  for _, name in ipairs(writes) do
    local rpm, previous = applied.rsc[name], previous_targets[name]
    local increases = math.abs(rpm) > math.abs(previous or 0)
    if not (increases and reduction_failed) then
      -- Charge attempts too: a peripheral can fail after changing the block.
      -- Cache invalidation must not erase the protection before a retry.
      flicker[name] = flicker_score(name) + (rpm == 0 and 5 or 10)
      local device = devices[name]
      if device == nil or device.setTargetSpeed == nil then
        remember(name, rpm, rpm == integer_rpm(outputs.rsc[name]))
      else
        local returned
        local wrote, failure = pcall(function()
          returned = device.setTargetSpeed(rpm)
        end)
        if not wrote then
          failed = failure or "actuator write failed"
        elseif returned ~= false then
          remember(name, rpm, rpm == integer_rpm(outputs.rsc[name]))
          if device.getTargetSpeed ~= nil then
            local after = device.getTargetSpeed()
            if type(after) == "number" then
              seen_speed[name] = integer_rpm(after)
            end
          end
        elseif not increases then
          reduction_failed = true
        end
      end
    end
  end
  if failed ~= nil then
    error(failed)
  end
  local relay2 = devices.relay2
  if relay2 ~= nil and relay2.setAnalogOutput ~= nil then
    local level = outputs.relays.relay2 or 0
    relay_write("relay2", "bottom", level, function()
      relay2.setAnalogOutput("bottom", level)
    end)
  end
  for name, on in pairs(outputs.relays) do
    if name ~= "relay2" then
      local device = devices[name]
      if device ~= nil and device.setOutput ~= nil then
        write_all(name, device, on == true)
      end
    end
  end
  if outputs.diag_relay ~= nil then
    local device = devices[outputs.diag_relay.device]
    local diag_name = outputs.diag_relay.device
    if device ~= nil and device.setOutput ~= nil then
      for _, side in ipairs(SIDES) do
        local value = 0
        if side == outputs.diag_relay.side then
          value = outputs.diag_relay.level
        end
        if device.setAnalogOutput ~= nil then
          relay_write(diag_name, side, value, function()
            device.setAnalogOutput(side, value)
          end)
        else
          relay_write(diag_name, side, value ~= 0, function()
            device.setOutput(side, value ~= 0)
          end)
        end
      end
    end
  end
  return applied
end

function M.apply(outputs, devices, options)
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
            if method == "setTargetSpeed" then
              forget(device_name)
            end
            failures[#failures + 1] = device_name .. ": " .. tostring(results[2])
            if method == "setTargetSpeed" then return false end
            return nil
          end
          if method == "setTargetSpeed" then return true end
          return unpack(results, 2)
        end
      end,
    })
  end
  local applied = apply_targets(outputs, guarded, options)
  if #failures > 0 then
    error(table.concat(failures, "; "), 0)
  end
  return applied
end

return M
