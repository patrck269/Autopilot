# Ship Autopilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the three ComputerCraft programs that fly the ship from the engine room, draw the four monitors, and accept commands from the command-center keyboard and the pocket.

**Architecture:** Pure Lua functions decide speed, altitude, failure response, page assignment, and diagnostic outputs. The engine tick calls those functions. Thin ComputerCraft programs only wrap peripherals and send the same command tables.

**Tech Stack:** Lua 5.1 as used by CC:Tweaked. Tests run on desktop Lua 5.1 or any newer Lua that can `require` these files. `lua -v` must succeed before Task 1. No Minecraft API inside `src/`.

**Spec:** `docs/superpowers/specs/2026-09-26-autopilot-design.md`

## Global Constraints

- World X and Z are horizontal. World Y is altitude.
- Manual stick speed is at most 3 m/s.
- Semi-automatic reaches the set speed in 15 seconds and caps horizontal speed at 35 m/s.
- Automatic climbs to Y=400 before horizontal acceleration, warp is 50 m/s, cruise is 7 m/s (under 8), stops within 10 blocks, then descends to Y=329.
- Above 20 m/s horizontal, bow-up thrust holds the nose and the side thrusters hold heading.
- Diagnostic speed commands clamp to -32..32 RPM. RSC 11 in hover diagnostic is the exception and is not clamped.
- Diagnostic relay strength is 0..15 on one side.
- Monitor text scale is 0.5. The two largest monitors start on Flight and Navigation.
- Emergency stop zeros every flight output and stays latched until cleared.
- A missing configured peripheral refuses flight and diagnostic actuation.
- `gps.locate()` returning nothing sends no return command.
- Ship frame for config vectors: +x bow, +y starboard, +z up. Positive pitch rate means the nose is dropping. Positive roll rate means the starboard side is dropping.
- Do not add downward thrusters, stick relays, or GPS hosts. Do not change Create's rotation limit or the vstuff mod.

## File map

- `tests/assert.lua` — `eq` and `near`.
- `tests/run.lua` — runs every `tests/test_*.lua` file.
- `src/manual.lua` — stick to a velocity vector.
- `src/speed.lua` — ramp, cap, brake distance, Relay 2 level.
- `src/hover.lua` — hover-throttle adjustment.
- `src/auto.lua` — automatic phase step.
- `src/outage.lua` — classify a failure and the cutoff response.
- `src/monitors.lua` — sort monitors and swap pages.
- `src/mfd.lua` — which button a touch hit.
- `src/protocol.lua` — accept or reject a command table.
- `src/mix.lua` — zero outputs and per-axis output pieces.
- `src/diagnostic.lua` — clamp and apply one diagnostic device.
- `src/startup.lua` — list missing names.
- `src/config.lua` — default names, directions, and gains.
- `src/engine_tick.lua` — one control pass.
- `src/runtime.lua` — write one output table to fake or real peripherals.
- `src/command_ui.lua` — key names to commands.
- `src/pocket_ui.lua` — touches to commands.
- `programs/engine.lua`, `programs/command.lua`, `programs/pocket.lua` — ComputerCraft entry points.

Copy `src/` and `programs/engine.lua` onto the engine computer. Copy `programs/command.lua` onto the command computer. Copy `programs/pocket.lua` onto the pocket. Edit `src/config.lua` so each `names` value is the wired-network name shown in chat when that modem is attached.

---

### Task 1: Test runner and manual velocity

**Files:**
- Create: `tests/assert.lua`
- Create: `tests/run.lua`
- Create: `tests/test_manual.lua`
- Create: `src/manual.lua`
- Test: `tests/test_manual.lua`

**Interfaces:**
- Consumes: nothing
- Produces: `manual.velocity(sx, sy, sz) -> vx, vy, vz` with each input -1, 0, or 1. The resulting vector length is 0 or 3.

- [ ] **Step 1: Write the failing test**

```lua
package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local manual = require("manual")

local vx, vy, vz = manual.velocity(0, 0, 0)
A.eq(vx, 0, "idle x")
A.eq(vy, 0, "idle y")
A.eq(vz, 0, "idle z")

vx, vy, vz = manual.velocity(1, 0, 0)
A.eq(vx, 3, "forward")
A.eq(vy, 0, "forward y")
A.eq(vz, 0, "forward z")

vx, vy, vz = manual.velocity(-1, 0, 0)
A.eq(vx, -3, "back")

vx, vy, vz = manual.velocity(1, 1, 0)
A.near(math.sqrt(vx * vx + vy * vy + vz * vz), 3, 1e-9, "diagonal length")
A.near(vx, 3 / math.sqrt(2), 1e-9, "diagonal x")
A.near(vy, 3 / math.sqrt(2), 1e-9, "diagonal y")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/test_manual.lua`
Expected: FAIL, module `manual` not found.

- [ ] **Step 3: Write minimal implementation**

`tests/assert.lua`:

```lua
local M = {}

function M.eq(actual, expected, msg)
  if actual ~= expected then
    error(msg .. ": expected " .. tostring(expected) .. " got " .. tostring(actual), 2)
  end
end

function M.near(actual, expected, tol, msg)
  if math.abs(actual - expected) > tol then
    error(msg .. ": expected " .. tostring(expected) .. " got " .. tostring(actual), 2)
  end
end

return M
```

`tests/run.lua`:

```lua
local lfs_cmd = 'dir /b "tests\\test_*.lua"'
local pipe = io.popen(lfs_cmd)
if pipe == nil then
  error("cannot list tests")
end
local failed = 0
for name in pipe:lines() do
  local path = "tests/" .. name
  local ok, err = pcall(dofile, path)
  if not ok then
    io.stderr:write(path .. "\n" .. tostring(err) .. "\n")
    failed = failed + 1
  end
end
pipe:close()
if failed > 0 then
  os.exit(1)
end
print("ok")
```

`src/manual.lua`:

```lua
local M = {}

function M.velocity(sx, sy, sz)
  local length = math.sqrt(sx * sx + sy * sy + sz * sz)
  if length == 0 then
    return 0, 0, 0
  end
  local scale = 3 / length
  return sx * scale, sy * scale, sz * scale
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: `ok`

- [ ] **Step 5: Commit**

```
git add tests/assert.lua tests/run.lua tests/test_manual.lua src/manual.lua
git commit -m "Add manual stick velocity"
```

---

### Task 2: Speed ramp, cap, brake distance, Relay 2

**Files:**
- Create: `src/speed.lua`
- Create: `tests/test_speed.lua`
- Test: `tests/test_speed.lua`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `speed.ramp_rate(current, target) -> number` rate in m/s per second so the gap closes in 15 seconds
  - `speed.apply_ramp(current, target, rate, dt) -> number` does not step past `target`
  - `speed.cap(value, limit) -> number` clamps to `-limit..limit`
  - `speed.brake_distance(speed, accel) -> number` meters, `v^2 / (2a)`, 0 when `accel <= 0`
  - `speed.relay2_level(command_speed, ref_speed) -> integer` 0..15

- [ ] **Step 1: Write the failing test**

```lua
package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local speed = require("speed")

A.near(speed.ramp_rate(0, 30), 2, 1e-9, "rate")
A.near(speed.apply_ramp(0, 30, 2, 0.5), 1, 1e-9, "half second")
A.eq(speed.apply_ramp(29, 30, 2, 5), 30, "does not pass target")
A.eq(speed.apply_ramp(10, 0, -2, 1), 8, "slowing")
A.eq(speed.cap(40, 35), 35, "upper cap")
A.eq(speed.cap(-40, 35), -35, "lower cap")
A.eq(speed.brake_distance(10, 2), 25, "brake")
A.eq(speed.brake_distance(10, 0), 0, "no accel")
A.eq(speed.relay2_level(0, 35), 0, "relay idle")
A.eq(speed.relay2_level(35, 35), 15, "relay full")
A.eq(speed.relay2_level(-17.5, 35), 8, "relay half and reverse magnitude")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/test_speed.lua`
Expected: FAIL, module `speed` not found.

- [ ] **Step 3: Write minimal implementation**

```lua
local M = {}

function M.ramp_rate(current, target)
  return (target - current) / 15
end

function M.apply_ramp(current, target, rate, dt)
  local next_speed = current + rate * dt
  if rate > 0 and next_speed > target then
    return target
  end
  if rate < 0 and next_speed < target then
    return target
  end
  if rate == 0 then
    return target
  end
  return next_speed
end

function M.cap(value, limit)
  if value > limit then
    return limit
  end
  if value < -limit then
    return -limit
  end
  return value
end

function M.brake_distance(spd, accel)
  if accel <= 0 then
    return 0
  end
  return (spd * spd) / (2 * accel)
end

function M.relay2_level(command_speed, ref_speed)
  if ref_speed == 0 then
    return 0
  end
  local level = math.floor(math.abs(command_speed) / ref_speed * 15 + 0.5)
  if level < 0 then
    return 0
  end
  if level > 15 then
    return 15
  end
  return level
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: `ok`

- [ ] **Step 5: Commit**

```
git add src/speed.lua tests/test_speed.lua
git commit -m "Add speed ramp and brake distance"
```

---

### Task 3: Hover adjustment

**Files:**
- Create: `src/hover.lua`
- Create: `tests/test_hover.lua`
- Test: `tests/test_hover.lua`

**Interfaces:**
- Consumes: nothing
- Produces: `hover.adjust(rpm, vertical_speed, gain) -> number`. Positive vertical speed lowers the rpm.

- [ ] **Step 1: Write the failing test**

```lua
package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local hover = require("hover")

A.eq(hover.adjust(100, 0, 2), 100, "hold")
A.eq(hover.adjust(100, 1, 2), 98, "rising")
A.eq(hover.adjust(100, -1, 2), 102, "sinking")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/test_hover.lua`
Expected: FAIL, module `hover` not found.

- [ ] **Step 3: Write minimal implementation**

```lua
local M = {}

function M.adjust(rpm, vertical_speed, gain)
  return rpm - gain * vertical_speed
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: `ok`

- [ ] **Step 5: Commit**

```
git add src/hover.lua tests/test_hover.lua
git commit -m "Add hover throttle adjustment"
```

---

### Task 4: Automatic phases

**Files:**
- Create: `src/auto.lua`
- Create: `tests/test_auto.lua`
- Test: `tests/test_auto.lua`

**Interfaces:**
- Consumes: `speed.brake_distance(speed, accel)`
- Produces: `auto.step(s) -> table`. Input `s` has `phase`, `y`, `dist`, `speed`, `accel` (nil until measured), `profile` (`"warp"` or `"cruise"`). Output has `phase`, `horiz_speed`, `vertical` (`"climb"`, `"hold"`, or `"descend"`), `reverse` (boolean).

- [ ] **Step 1: Write the failing test**

```lua
package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local auto = require("auto")

local climb = auto.step({
  phase = "climb", y = 100, dist = 500, speed = 0, accel = nil, profile = "warp",
})
A.eq(climb.phase, "climb", "still climbing")
A.eq(climb.horiz_speed, 0, "no horizontal until 400")
A.eq(climb.vertical, "climb", "climb vertical")
A.eq(climb.reverse, false, "not reversing")

local track = auto.step({
  phase = "climb", y = 400, dist = 500, speed = 0, accel = nil, profile = "warp",
})
A.eq(track.phase, "track", "starts track at 400")
A.eq(track.horiz_speed, 50, "warp")

local cruise = auto.step({
  phase = "track", y = 400, dist = 500, speed = 7, accel = nil, profile = "cruise",
})
A.eq(cruise.horiz_speed, 7, "cruise under 8")

local brake = auto.step({
  phase = "track", y = 400, dist = 20, speed = 10, accel = 2, profile = "warp",
})
A.eq(brake.phase, "brake", "brake inside v^2/2a of 25")
A.eq(brake.reverse, true, "reverse")
A.eq(brake.horiz_speed, 0, "brake target")

local keep = auto.step({
  phase = "track", y = 400, dist = 40, speed = 10, accel = 2, profile = "warp",
})
A.eq(keep.phase, "track", "outside brake distance")

local no_sample = auto.step({
  phase = "track", y = 400, dist = 20, speed = 10, accel = nil, profile = "warp",
})
A.eq(no_sample.phase, "track", "wait for an accel sample")

local arrived = auto.step({
  phase = "brake", y = 400, dist = 10, speed = 1, accel = 2, profile = "warp",
})
A.eq(arrived.phase, "descend", "within 10")
A.eq(arrived.vertical, "descend", "descend")
A.eq(arrived.horiz_speed, 0, "stop horizontal")

local done = auto.step({
  phase = "descend", y = 329, dist = 0, speed = 0, accel = 2, profile = "warp",
})
A.eq(done.phase, "hold", "at 329")
A.eq(done.vertical, "hold", "hold height")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/test_auto.lua`
Expected: FAIL, module `auto` not found.

- [ ] **Step 3: Write minimal implementation**

```lua
local speed = require("speed")

local M = {}

local function result(phase, horiz, vertical, reverse)
  return {
    phase = phase,
    horiz_speed = horiz,
    vertical = vertical,
    reverse = reverse,
  }
end

function M.step(s)
  local phase = s.phase
  if phase == "climb" and s.y >= 400 then
    if s.dist <= 10 then
      phase = "descend"
    else
      phase = "track"
    end
  end
  if phase == "track" then
    local limit = 50
    if s.profile == "cruise" then
      limit = 7
    end
    if s.dist <= 10 then
      phase = "descend"
    elseif s.accel ~= nil and s.accel > 0 and s.dist <= speed.brake_distance(s.speed, s.accel) then
      phase = "brake"
    else
      return result(phase, limit, "hold", false)
    end
  end
  if phase == "brake" then
    if s.dist <= 10 then
      phase = "descend"
    else
      return result(phase, 0, "hold", true)
    end
  end
  if phase == "descend" then
    if s.y <= 329 then
      phase = "hold"
    else
      return result(phase, 0, "descend", false)
    end
  end
  if phase == "hold" then
    return result(phase, 0, "hold", false)
  end
  return result("climb", 0, "climb", false)
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: `ok`

- [ ] **Step 5: Commit**

```
git add src/auto.lua tests/test_auto.lua
git commit -m "Add automatic flight phases"
```

---

### Task 5: Outage classification and cutoffs

**Files:**
- Create: `src/outage.lua`
- Create: `tests/test_outage.lua`
- Test: `tests/test_outage.lua`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `outage.classify(pitch_rate, roll_rate, threshold) -> kind, which`. `kind` is `nil`, `"corner"`, or `"side"`. Corner names are `port_bow`, `starboard_bow`, `port_stern`, `starboard_stern`. Side names are `port` and `starboard`. A side is roll past the threshold with pitch under half the threshold. A corner is both past the threshold.
  - `outage.opposite(corner) -> corner`
  - `outage.live_prop_scale(roll_rate, dead_side) -> number` from 0 to 1
  - `outage.cutoffs(kind, which) -> table` of relay booleans. One corner cuts only the opposite relay among `relay7`..`relay10` and leaves `relay5` false. A side fall is not this function. `outage.fall_cutoffs() -> table` sets `relay5` and `relay7` through `relay10` true.

- [ ] **Step 1: Write the failing test**

```lua
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/test_outage.lua`
Expected: FAIL, module `outage` not found.

- [ ] **Step 3: Write minimal implementation**

```lua
local M = {}

function M.classify(pitch_rate, roll_rate, threshold)
  local ap = math.abs(pitch_rate)
  local ar = math.abs(roll_rate)
  if ar >= threshold and ap < threshold * 0.5 then
    if roll_rate > 0 then
      return "side", "starboard"
    end
    return "side", "port"
  end
  if ap >= threshold and ar >= threshold then
    if pitch_rate > 0 and roll_rate < 0 then
      return "corner", "port_bow"
    end
    if pitch_rate > 0 and roll_rate > 0 then
      return "corner", "starboard_bow"
    end
    if pitch_rate < 0 and roll_rate < 0 then
      return "corner", "port_stern"
    end
    return "corner", "starboard_stern"
  end
  return nil, nil
end

function M.opposite(corner)
  local pairs = {
    port_bow = "starboard_stern",
    starboard_stern = "port_bow",
    starboard_bow = "port_stern",
    port_stern = "starboard_bow",
  }
  return pairs[corner]
end

function M.live_prop_scale(roll_rate, dead_side)
  local excess = 0
  if dead_side == "port" and roll_rate < 0 then
    excess = -roll_rate
  end
  if dead_side == "starboard" and roll_rate > 0 then
    excess = roll_rate
  end
  local scale = 1 - excess
  if scale < 0 then
    return 0
  end
  if scale > 1 then
    return 1
  end
  return scale
end

local function blank()
  return {
    relay5 = false,
    relay7 = false,
    relay8 = false,
    relay9 = false,
    relay10 = false,
  }
end

function M.cutoffs(kind, which)
  local relays = blank()
  if kind ~= "corner" then
    return relays
  end
  local relay = {
    port_bow = "relay7",
    starboard_bow = "relay8",
    starboard_stern = "relay9",
    port_stern = "relay10",
  }
  local cut = M.opposite(which)
  relays[relay[cut]] = true
  return relays
end

function M.fall_cutoffs()
  return {
    relay5 = true,
    relay7 = true,
    relay8 = true,
    relay9 = true,
    relay10 = true,
  }
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: `ok`

- [ ] **Step 5: Commit**

```
git add src/outage.lua tests/test_outage.lua
git commit -m "Add propeller outage classification"
```

---

### Task 6: Monitor order and page swap

**Files:**
- Create: `src/monitors.lua`
- Create: `tests/test_monitors.lua`
- Test: `tests/test_monitors.lua`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `monitors.assign(list) -> map`. Each item is `{name, w, h}`. Sort by `w * h` descending, then `name` ascending. Index 1 is `Flight`, 2 is `Navigation`, 3 is `Engines`, 4 is `Emergency`. Extra monitors get no page. Fewer than four get the prefix of that list.
  - `monitors.swap(map, from_name, to_name) -> new map`. The two pages exchange. Unknown names return the same pages.

- [ ] **Step 1: Write the failing test**

```lua
package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local monitors = require("monitors")

local pages = monitors.assign({
  { name = "m_small_b", w = 28, h = 30 },
  { name = "m_large_b", w = 42, h = 30 },
  { name = "m_large_a", w = 42, h = 30 },
  { name = "m_small_a", w = 28, h = 30 },
})
A.eq(pages.m_large_a, "Flight", "tie breaks by name")
A.eq(pages.m_large_b, "Navigation", "second large")
A.eq(pages.m_small_a, "Engines", "third")
A.eq(pages.m_small_b, "Emergency", "fourth")

local swapped = monitors.swap(pages, "m_large_a", "m_small_a")
A.eq(swapped.m_large_a, "Engines", "moved away")
A.eq(swapped.m_small_a, "Flight", "moved here")
A.eq(swapped.m_large_b, "Navigation", "untouched")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/test_monitors.lua`
Expected: FAIL, module `monitors` not found.

- [ ] **Step 3: Write minimal implementation**

```lua
local M = {}

local ORDER = { "Flight", "Navigation", "Engines", "Emergency" }

function M.assign(list)
  local items = {}
  for i, item in ipairs(list) do
    items[i] = item
  end
  table.sort(items, function(a, b)
    local as = a.w * a.h
    local bs = b.w * b.h
    if as ~= bs then
      return as > bs
    end
    return a.name < b.name
  end)
  local pages = {}
  for i, item in ipairs(items) do
    pages[item.name] = ORDER[i]
  end
  return pages
end

function M.swap(map, from_name, to_name)
  local next_map = {}
  for name, page in pairs(map) do
    next_map[name] = page
  end
  if next_map[from_name] == nil or next_map[to_name] == nil then
    return next_map
  end
  next_map[from_name], next_map[to_name] = next_map[to_name], next_map[from_name]
  return next_map
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: `ok`

- [ ] **Step 5: Commit**

```
git add src/monitors.lua tests/test_monitors.lua
git commit -m "Add monitor page assignment"
```

---

### Task 7: MFD button hit

**Files:**
- Create: `src/mfd.lua`
- Create: `tests/test_mfd.lua`
- Test: `tests/test_mfd.lua`

**Interfaces:**
- Consumes: nothing
- Produces: `mfd.hit(w, h, x, y, names) -> name or nil`. `names` has four monitor names. The bottom row is split into four equal slots. A touch on that row returns the name in that slot. Any other row returns nil.

- [ ] **Step 1: Write the failing test**

```lua
package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local mfd = require("mfd")

local names = { "a", "b", "c", "d" }
A.eq(mfd.hit(40, 30, 1, 29, names), nil, "above the row")
A.eq(mfd.hit(40, 30, 1, 30, names), "a", "first")
A.eq(mfd.hit(40, 30, 11, 30, names), "b", "second")
A.eq(mfd.hit(40, 30, 21, 30, names), "c", "third")
A.eq(mfd.hit(40, 30, 31, 30, names), "d", "fourth")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/test_mfd.lua`
Expected: FAIL, module `mfd` not found.

- [ ] **Step 3: Write minimal implementation**

```lua
local M = {}

function M.hit(w, h, x, y, names)
  if y ~= h then
    return nil
  end
  local slot = math.floor(w / 4)
  if slot < 1 then
    return nil
  end
  local index = math.floor((x - 1) / slot) + 1
  if index < 1 or index > 4 then
    return nil
  end
  return names[index]
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: `ok`

- [ ] **Step 5: Commit**

```
git add src/mfd.lua tests/test_mfd.lua
git commit -m "Add MFD button hits"
```

---

### Task 8: Command protocol

**Files:**
- Create: `src/protocol.lua`
- Create: `tests/test_protocol.lua`
- Test: `tests/test_protocol.lua`

**Interfaces:**
- Consumes: nothing
- Produces: `protocol.validate(msg) -> msg or nil`. Accepted `type` values and required fields:
  - `stick`: numbers `x`, `y`, `z`
  - `set_mode`: `mode` is `manual`, `semi`, or `auto`
  - `set_altitude`: number `y`
  - `set_bearing`: number `bearing`
  - `set_speed`: number `speed`
  - `set_waypoint`: numbers `x`, `z`
  - `set_profile`: `profile` is `cruise` or `warp`
  - `return_to_user`: numbers `x`, `z`
  - `emergency`: no fields
  - `clear_emergency`: no fields
  - `diagnostic_enter`: boolean `hover`
  - `diagnostic_exit`: no fields
  - `diagnostic_elevation`: number `rpm`
  - `diagnostic_set`: string `device`, and either number `rpm` or string `side` plus number `level`

- [ ] **Step 1: Write the failing test**

```lua
package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local protocol = require("protocol")

A.eq(protocol.validate(nil), nil, "nil")
A.eq(protocol.validate({ type = "nope" }), nil, "unknown")
A.eq(protocol.validate({ type = "stick", x = 1 }).type, nil, "short stick")

local stick = protocol.validate({ type = "stick", x = 1, y = 0, z = -1 })
A.eq(stick.x, 1, "stick x")
A.eq(protocol.validate({ type = "set_mode", mode = "auto" }).mode, "auto", "mode")
A.eq(protocol.validate({ type = "set_mode", mode = "hover" }), nil, "bad mode")
A.eq(protocol.validate({ type = "set_waypoint", x = 3, z = 4 }).z, 4, "waypoint")
A.eq(protocol.validate({ type = "set_profile", profile = "cruise" }).profile, "cruise", "profile")
A.eq(protocol.validate({ type = "return_to_user", x = 8, z = 9 }).x, 8, "return")
A.eq(protocol.validate({ type = "emergency" }).type, "emergency", "estop")
A.eq(protocol.validate({ type = "clear_emergency" }).type, "clear_emergency", "clear")
A.eq(protocol.validate({ type = "diagnostic_enter", hover = true }).hover, true, "diag enter")
A.eq(protocol.validate({ type = "diagnostic_set", device = "rsc10", rpm = 40 }).rpm, 40, "diag rpm")
A.eq(protocol.validate({ type = "diagnostic_set", device = "relay7", side = "bottom", level = 15 }).side, "bottom", "diag relay")
A.eq(protocol.validate({ type = "diagnostic_set", device = "relay7" }), nil, "diag relay missing side")
A.eq(protocol.validate({ type = "diagnostic_elevation", rpm = 80 }).rpm, 80, "elevation")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/test_protocol.lua`
Expected: FAIL, module `protocol` not found.

- [ ] **Step 3: Write minimal implementation**

```lua
local M = {}

local function is_number(value)
  return type(value) == "number"
end

function M.validate(msg)
  if type(msg) ~= "table" then
    return nil
  end
  local kind = msg.type
  if kind == "stick" and is_number(msg.x) and is_number(msg.y) and is_number(msg.z) then
    return msg
  end
  if kind == "set_mode" and (msg.mode == "manual" or msg.mode == "semi" or msg.mode == "auto") then
    return msg
  end
  if kind == "set_altitude" and is_number(msg.y) then
    return msg
  end
  if kind == "set_bearing" and is_number(msg.bearing) then
    return msg
  end
  if kind == "set_speed" and is_number(msg.speed) then
    return msg
  end
  if kind == "set_waypoint" and is_number(msg.x) and is_number(msg.z) then
    return msg
  end
  if kind == "set_profile" and (msg.profile == "cruise" or msg.profile == "warp") then
    return msg
  end
  if kind == "return_to_user" and is_number(msg.x) and is_number(msg.z) then
    return msg
  end
  if kind == "emergency" or kind == "clear_emergency" or kind == "diagnostic_exit" then
    return msg
  end
  if kind == "diagnostic_enter" and type(msg.hover) == "boolean" then
    return msg
  end
  if kind == "diagnostic_elevation" and is_number(msg.rpm) then
    return msg
  end
  if kind == "diagnostic_set" and type(msg.device) == "string" then
    if is_number(msg.rpm) then
      return msg
    end
    if type(msg.side) == "string" and is_number(msg.level) then
      return msg
    end
  end
  return nil
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: `ok`

- [ ] **Step 5: Commit**

```
git add src/protocol.lua tests/test_protocol.lua
git commit -m "Add command validation"
```

---

### Task 9: Output mix pieces

**Files:**
- Create: `src/mix.lua`
- Create: `tests/test_mix.lua`
- Test: `tests/test_mix.lua`

**Interfaces:**
- Consumes: `speed.relay2_level`, `speed.cap`
- Produces:
  - `mix.zero() -> outputs` with `rsc.rsc2`..`rsc.rsc11` all 0, `relays.relay2` 0, and the other relays false
  - `mix.x(command_speed, ref_speed) -> rsc10, relay2`. `rsc10` keeps its sign. `relay2` is 0..15.
  - `mix.elevation(vertical, hover_rpm, climb_rpm) -> rsc11, relay6`. `vertical` is `"climb"`, `"hold"`, `"descend"`, or `"reverse"`. Descend uses negative world demand as Relay 6 true and positive `rsc11`. Hold uses `hover_rpm` and Relay 6 false. Climb uses `climb_rpm`.
  - `mix.sides(vy, yaw, gain) -> rsc6, rsc7, rsc8, rsc9`
  - `mix.ups(pitch_err, roll_err, lift, gain) -> rsc2, rsc3, rsc4, rsc5`. `pitch_err > 0` means the nose is down. `roll_err > 0` means starboard is down. Only positive contributions fire.

Side directions used by `mix.sides`: rsc6 and rsc8 thrust +y at x = +1 and x = -1. rsc9 and rsc7 thrust -y at x = +1 and x = -1. Yaw moment of a thruster is `x * direction_y`.

- [ ] **Step 1: Write the failing test**

```lua
package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local mix = require("mix")

local z = mix.zero()
A.eq(z.rsc.rsc10, 0, "zero x")
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

local down_rpm, down_rev = mix.elevation("reverse", 80, 200)
A.eq(down_rpm, 80, "reverse uses hover magnitude")
A.eq(down_rev, true, "reverser on")

local s6, s7, s8, s9 = mix.sides(1, 0, 10)
A.eq(s6, 10, "port bow translates starboard")
A.eq(s8, 10, "port aft translates starboard")
A.eq(s7, 0, "starboard aft stays")
A.eq(s9, 0, "starboard bow stays")

s6, s7, s8, s9 = mix.sides(0, 1, 10)
A.eq(s6, 10, "yaw bow port side")
A.eq(s7, 10, "yaw stern starboard side")
A.eq(s8, 0, "yaw cancels the other port")
A.eq(s9, 0, "yaw cancels the other starboard")

local u2, u3, u4, u5 = mix.ups(1, 0, 0, 5)
A.eq(u2, 5, "bow starboard")
A.eq(u3, 5, "bow port")
A.eq(u4, 0, "stern starboard quiet")
A.eq(u5, 0, "stern port quiet")

u2, u3, u4, u5 = mix.ups(0, 1, 4, 5)
A.eq(u2, 9, "starboard bow lift plus roll")
A.eq(u4, 9, "starboard stern")
A.eq(u3, 4, "port bow lift only")
A.eq(u5, 4, "port stern lift only")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/test_mix.lua`
Expected: FAIL, module `mix` not found.

- [ ] **Step 3: Write minimal implementation**

```lua
local speed = require("speed")

local M = {}

function M.zero()
  return {
    rsc = {
      rsc2 = 0, rsc3 = 0, rsc4 = 0, rsc5 = 0,
      rsc6 = 0, rsc7 = 0, rsc8 = 0, rsc9 = 0,
      rsc10 = 0, rsc11 = 0,
    },
    relays = {
      relay2 = 0,
      relay3 = false,
      relay5 = false,
      relay6 = false,
      relay7 = false,
      relay8 = false,
      relay9 = false,
      relay10 = false,
    },
  }
end

function M.x(command_speed, ref_speed)
  return command_speed, speed.relay2_level(command_speed, ref_speed)
end

function M.elevation(vertical, hover_rpm, climb_rpm)
  if vertical == "climb" then
    return climb_rpm, false
  end
  if vertical == "reverse" then
    return hover_rpm, true
  end
  return hover_rpm, false
end

function M.sides(vy, yaw, gain)
  local rsc6 = 0
  local rsc7 = 0
  local rsc8 = 0
  local rsc9 = 0
  if vy > 0 then
    rsc6 = vy * gain
    rsc8 = vy * gain
  elseif vy < 0 then
    rsc9 = -vy * gain
    rsc7 = -vy * gain
  end
  if yaw > 0 then
    rsc6 = rsc6 + yaw * gain
    rsc7 = rsc7 + yaw * gain
  elseif yaw < 0 then
    rsc8 = rsc8 - yaw * gain
    rsc9 = rsc9 - yaw * gain
  end
  return rsc6, rsc7, rsc8, rsc9
end

local function pos(value)
  if value > 0 then
    return value
  end
  return 0
end

function M.ups(pitch_err, roll_err, lift, gain)
  local pitch = pitch_err * gain
  local roll = roll_err * gain
  local rsc2 = pos(pitch) + pos(roll) + lift
  local rsc3 = pos(pitch) + pos(-roll) + lift
  local rsc4 = pos(-pitch) + pos(roll) + lift
  local rsc5 = pos(-pitch) + pos(-roll) + lift
  return rsc2, rsc3, rsc4, rsc5
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: `ok`

- [ ] **Step 5: Commit**

```
git add src/mix.lua tests/test_mix.lua
git commit -m "Add thrust output mix"
```

---

### Task 10: Diagnostic clamp and hover exclusion

**Files:**
- Create: `src/diagnostic.lua`
- Create: `tests/test_diagnostic.lua`
- Test: `tests/test_diagnostic.lua`

**Interfaces:**
- Consumes: `mix.zero`
- Produces: `diagnostic.apply(selection, hover) -> outputs`.
  - `selection` is `nil` or `{device, rpm}` or `{device, side, level}`.
  - `hover` is `nil` or `{enabled = true, rpm = number}`.
  - Speed-controller rpm clamps to -32..32.
  - When `hover.enabled`, a `diagnostic_set` for `rsc11`, `relay6`, `relay7`, `relay8`, `relay9`, or `relay10` does not change those devices. `outputs.rsc.rsc11` becomes `hover.rpm` with no clamp.
  - Relay `level` clamps to 0..15. `outputs.diag_relay` is `{device, side, level}` or nil.
  - Flight cutoff booleans stay false. `relay3` can be the selected relay.

- [ ] **Step 1: Write the failing test**

```lua
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/test_diagnostic.lua`
Expected: FAIL, module `diagnostic` not found.

- [ ] **Step 3: Write minimal implementation**

```lua
local mix = require("mix")

local M = {}

local LOCKED = {
  rsc11 = true,
  relay6 = true,
  relay7 = true,
  relay8 = true,
  relay9 = true,
  relay10 = true,
}

local function clamp_rpm(rpm)
  if rpm > 32 then
    return 32
  end
  if rpm < -32 then
    return -32
  end
  return rpm
end

local function clamp_level(level)
  if level > 15 then
    return 15
  end
  if level < 0 then
    return 0
  end
  return level
end

function M.apply(selection, hover)
  local outputs = mix.zero()
  outputs.diag_relay = nil
  local hover_on = hover ~= nil and hover.enabled == true
  if hover_on then
    outputs.rsc.rsc11 = hover.rpm
  end
  if selection == nil then
    return outputs
  end
  if hover_on and LOCKED[selection.device] then
    return outputs
  end
  if selection.rpm ~= nil then
    outputs.rsc[selection.device] = clamp_rpm(selection.rpm)
    return outputs
  end
  if selection.side ~= nil then
    outputs.diag_relay = {
      device = selection.device,
      side = selection.side,
      level = clamp_level(selection.level),
    }
  end
  return outputs
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: `ok`

- [ ] **Step 5: Commit**

```
git add src/diagnostic.lua tests/test_diagnostic.lua
git commit -m "Add diagnostic output rules"
```

---

### Task 11: Startup check and default config

**Files:**
- Create: `src/startup.lua`
- Create: `src/config.lua`
- Create: `tests/test_startup.lua`
- Test: `tests/test_startup.lua`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `startup.missing(present, required) -> array` of required names that are not keys of `present`
  - `config.default() -> table` with `climb_rpm = 256`, `outage_threshold = 0.2`, `outage_fail_seconds = 5`, `hover_gain = 2`, `side_gain = 10`, `up_gain = 5`, `balance_rpm = 64`, and `names` for `relay2` through `relay10` (no relay4), `rsc2` through `rsc11`, `speedometer`, `stressometer`, `wired_modem`, `ender_modem`

- [ ] **Step 1: Write the failing test**

```lua
package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local startup = require("startup")
local config = require("config")

local cfg = config.default()
A.eq(cfg.climb_rpm, 256, "climb")
A.eq(cfg.names.rsc10, "rsc10", "default network name")
A.eq(cfg.names.relay4, nil, "no relay 4")

local missing = startup.missing({ rsc10 = true, relay2 = true }, { "rsc10", "relay2", "rsc11" })
A.eq(#missing, 1, "one missing")
A.eq(missing[1], "rsc11", "missing name")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/test_startup.lua`
Expected: FAIL, module `startup` not found.

- [ ] **Step 3: Write minimal implementation**

`src/startup.lua`:

```lua
local M = {}

function M.missing(present, required)
  local found = {}
  for _, name in ipairs(required) do
    if present[name] ~= true then
      found[#found + 1] = name
    end
  end
  return found
end

return M
```

`src/config.lua`:

```lua
local M = {}

function M.default()
  return {
    climb_rpm = 256,
    outage_threshold = 0.2,
    outage_fail_seconds = 5,
    hover_gain = 2,
    side_gain = 10,
    up_gain = 5,
    balance_rpm = 64,
    names = {
      relay2 = "relay2",
      relay3 = "relay3",
      relay5 = "relay5",
      relay6 = "relay6",
      relay7 = "relay7",
      relay8 = "relay8",
      relay9 = "relay9",
      relay10 = "relay10",
      rsc2 = "rsc2",
      rsc3 = "rsc3",
      rsc4 = "rsc4",
      rsc5 = "rsc5",
      rsc6 = "rsc6",
      rsc7 = "rsc7",
      rsc8 = "rsc8",
      rsc9 = "rsc9",
      rsc10 = "rsc10",
      rsc11 = "rsc11",
      speedometer = "speedometer",
      stressometer = "stressometer",
      wired_modem = "wired_modem",
      ender_modem = "ender_modem",
    },
  }
end

function M.required_names(cfg)
  local names = {}
  for key, _ in pairs(cfg.names) do
    names[#names + 1] = key
  end
  table.sort(names)
  return names
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: `ok`

- [ ] **Step 5: Commit**

```
git add src/startup.lua src/config.lua tests/test_startup.lua
git commit -m "Add startup check and default config"
```

---

### Task 12: Engine tick

**Files:**
- Create: `src/engine_tick.lua`
- Create: `tests/test_engine_tick.lua`
- Test: `tests/test_engine_tick.lua`

**Interfaces:**
- Consumes: `manual.velocity`, `speed.ramp_rate`, `speed.apply_ramp`, `speed.cap`, `hover.adjust`, `auto.step`, `outage.classify`, `outage.cutoffs`, `outage.fall_cutoffs`, `outage.live_prop_scale`, `mix.zero`, `mix.x`, `mix.elevation`, `mix.sides`, `mix.ups`, `diagnostic.apply`, `protocol.validate`, `config.default`
- Produces: `engine_tick.new_state() -> state` and `engine_tick.tick(state, input) -> state, outputs, status`.
  - `input.ship` has `y`, `x`, `z`, `vx`, `vy`, `vz`, `pitch`, `roll`, `heading`, `pitch_rate`, `roll_rate`, `dt`.
  - `input.command` is one validated message or nil.
  - `input.su` is a number.
  - `input.ready` is false when startup failed. Tick then returns zero outputs and does not leave `blocked`.
  - `status` has `mode`, `altitude`, `vertical_speed`, `horizontal_speed`, `heading`, `target`, `su`, `outage`.
  - Stick axes persist on `state.stick` and zero when `input.stick_fresh` is false.
  - Semi speed retarget stores a new ramp rate. Semi horizontal cap is 35. Semi ref speed for Relay 2 is 35.
  - Return-to-user sets mode `auto`, waypoint X and Z, and phase `climb`.
  - Horizontal speed above 20 adds `pitch` and `roll` into `mix.ups`, and heading error into `mix.sides` yaw. Heading error is `state.bearing - ship.heading` after both are wrapped to -pi..pi. Wrap helper is local to this file.
  - Corner outage applies `outage.cutoffs` onto the relays and does not command the cut corner's elevation. Side outage sets the dead-side upward controllers to `balance_rpm` and multiplies `rsc11` by `live_prop_scale`. If that roll is still toward the dead side after `outage_fail_seconds`, apply `fall_cutoffs` and zero `rsc2`..`rsc5` and `rsc11`.
  - `state.balance_time` accumulates `dt` during a side outage and resets otherwise.

- [ ] **Step 1: Write the failing test**

```lua
package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local engine_tick = require("engine_tick")
local config = require("config")

local cfg = config.default()
local ship = {
  y = 100, x = 0, z = 0, vx = 0, vy = 0, vz = 0,
  pitch = 0, roll = 0, heading = 0, pitch_rate = 0, roll_rate = 0, dt = 0.05,
}

local state = engine_tick.new_state()
local blocked, outputs, status = engine_tick.tick(state, {
  ship = ship, command = { type = "set_mode", mode = "manual" },
  su = 10, ready = false, stick_fresh = false, config = cfg,
})
A.eq(blocked.mode, "blocked", "not ready")
A.eq(outputs.rsc.rsc10, 0, "no thrust when blocked")

state = engine_tick.new_state()
state, outputs, status = engine_tick.tick(state, {
  ship = ship,
  command = { type = "stick", x = 1, y = 0, z = 0 },
  su = 12, ready = true, stick_fresh = true, config = cfg,
})
A.eq(state.mode, "manual", "stick selects manual")
A.eq(outputs.rsc.rsc10, 3, "forward 3 m/s as rpm at gain 1")
A.eq(status.su, 12, "su status")
A.eq(status.mode, "manual", "status mode")

state, outputs = engine_tick.tick(state, {
  ship = ship, command = nil, su = 12, ready = true, stick_fresh = false, config = cfg,
})
A.eq(outputs.rsc.rsc10, 0, "stick timeout")

state = engine_tick.new_state()
state.mode = "manual"
state, outputs = engine_tick.tick(state, {
  ship = ship, command = { type = "emergency" },
  su = 0, ready = true, stick_fresh = true, config = cfg,
})
A.eq(state.emergency, true, "latched")
A.eq(outputs.rsc.rsc11, 0, "estop elevation")

state, outputs = engine_tick.tick(state, {
  ship = ship, command = { type = "stick", x = 1, y = 0, z = 0 },
  su = 0, ready = true, stick_fresh = true, config = cfg,
})
A.eq(outputs.rsc.rsc10, 0, "estop holds")

state, outputs = engine_tick.tick(state, {
  ship = ship, command = { type = "clear_emergency" },
  su = 0, ready = true, stick_fresh = false, config = cfg,
})
A.eq(state.emergency, false, "cleared")

ship.pitch_rate = 0.4
ship.roll_rate = -0.4
state = engine_tick.new_state()
state.mode = "auto"
state.phase = "hold"
state, outputs, status = engine_tick.tick(state, {
  ship = ship, command = nil, su = 1, ready = true, stick_fresh = false, config = cfg,
})
A.eq(outputs.relays.relay9, true, "cut opposite corner")
A.eq(outputs.rsc.rsc2, 64, "live starboard bow")
A.eq(outputs.rsc.rsc5, 64, "live port stern")
A.eq(outputs.rsc.rsc3, 0, "failed corner thruster stays off")
A.eq(status.outage, "port_bow", "outage status")

ship.pitch_rate = 0
ship.roll_rate = 0
ship.pitch = 1
ship.vx = 25
ship.y = 400
state = engine_tick.new_state()
state.mode = "auto"
state.phase = "hold"
state.waypoint_x = 0
state.waypoint_z = 0
state, outputs = engine_tick.tick(state, {
  ship = ship, command = nil, su = 1, ready = true, stick_fresh = false, config = cfg,
})
A.eq(outputs.rsc.rsc2, 5, "nose down fires bow starboard")
A.eq(outputs.rsc.rsc3, 5, "nose down fires bow port")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/test_engine_tick.lua`
Expected: FAIL, module `engine_tick` not found.

- [ ] **Step 3: Write minimal implementation**

```lua
local manual = require("manual")
local speed = require("speed")
local hover = require("hover")
local auto = require("auto")
local outage = require("outage")
local mix = require("mix")
local diagnostic = require("diagnostic")

local M = {}

local function wrap(angle)
  while angle > math.pi do
    angle = angle - math.pi * 2
  end
  while angle < -math.pi do
    angle = angle + math.pi * 2
  end
  return angle
end

function M.new_state()
  return {
    mode = "idle",
    emergency = false,
    stick = { x = 0, y = 0, z = 0 },
    altitude = 100,
    bearing = 0,
    target_speed = 0,
    ramp_rate = 0,
    ramp_speed = 0,
    waypoint_x = 0,
    waypoint_z = 0,
    profile = "warp",
    phase = "climb",
    hover_rpm = 0,
    measured_accel = nil,
    last_horiz = 0,
    balance_time = 0,
    balance_side = nil,
    diagnostic = false,
    hover_diag = false,
    diag_selection = nil,
    diag_elevation = 0,
  }
end

local function status_of(state, ship, su, outage_name)
  return {
    mode = state.mode,
    altitude = ship.y,
    vertical_speed = ship.vy,
    horizontal_speed = math.sqrt(ship.vx * ship.vx + ship.vz * ship.vz),
    heading = ship.heading,
    target = state.mode,
    su = su,
    outage = outage_name,
  }
end

local function apply_command(state, command)
  if command == nil then
    return
  end
  if command.type == "emergency" then
    state.emergency = true
    state.diagnostic = false
    return
  end
  if command.type == "clear_emergency" then
    state.emergency = false
    return
  end
  if state.emergency then
    return
  end
  if command.type == "diagnostic_enter" then
    state.diagnostic = true
    state.hover_diag = command.hover
    state.mode = "diagnostic"
    state.diag_selection = nil
    return
  end
  if command.type == "diagnostic_exit" then
    state.diagnostic = false
    state.hover_diag = false
    state.diag_selection = nil
    state.mode = "idle"
    return
  end
  if command.type == "diagnostic_set" then
    state.diag_selection = command
    return
  end
  if command.type == "diagnostic_elevation" then
    state.diag_elevation = command.rpm
    return
  end
  if state.diagnostic then
    return
  end
  if command.type == "stick" then
    state.mode = "manual"
    state.stick = { x = command.x, y = command.y, z = command.z }
    return
  end
  if command.type == "set_mode" then
    state.mode = command.mode
    if command.mode == "semi" then
      state.ramp_speed = 0
      state.ramp_rate = speed.ramp_rate(0, state.target_speed)
    end
    if command.mode == "auto" then
      state.phase = "climb"
    end
    return
  end
  if command.type == "set_altitude" then
    state.altitude = command.y
    return
  end
  if command.type == "set_bearing" then
    state.bearing = command.bearing
    return
  end
  if command.type == "set_speed" then
    state.target_speed = command.speed
    state.ramp_rate = speed.ramp_rate(state.ramp_speed, command.speed)
    return
  end
  if command.type == "set_waypoint" or command.type == "return_to_user" then
    state.waypoint_x = command.x
    state.waypoint_z = command.z
    state.mode = "auto"
    state.phase = "climb"
    return
  end
  if command.type == "set_profile" then
    state.profile = command.profile
  end
end

function M.tick(state, input)
  local cfg = input.config
  apply_command(state, input.command)
  if input.ready == false then
    state.mode = "blocked"
    return state, mix.zero(), status_of(state, input.ship, input.su, nil)
  end
  if state.emergency then
    return state, mix.zero(), status_of(state, input.ship, input.su, nil)
  end
  if state.diagnostic then
    local hover_opt = nil
    if state.hover_diag then
      hover_opt = { enabled = true, rpm = state.diag_elevation }
    end
    local outputs = diagnostic.apply(state.diag_selection, hover_opt)
    return state, outputs, status_of(state, input.ship, input.su, nil)
  end
  if input.stick_fresh ~= true then
    state.stick = { x = 0, y = 0, z = 0 }
  end

  local ship = input.ship
  local outputs = mix.zero()
  local horiz = math.sqrt(ship.vx * ship.vx + ship.vz * ship.vz)
  if ship.dt > 0 then
    local delta = horiz - state.last_horiz
    if delta > 0 then
      state.measured_accel = delta / ship.dt
    end
  end
  state.last_horiz = horiz

  local vx, vy, vz = 0, 0, 0
  local vertical = "hold"
  local reverse = false
  local ref = 3
  if state.mode == "manual" then
    vx, vy, vz = manual.velocity(state.stick.x, state.stick.y, state.stick.z)
    if vz > 0 then
      vertical = "climb"
    elseif vz < 0 then
      vertical = "reverse"
    end
    ref = 3
  elseif state.mode == "semi" then
    state.ramp_speed = speed.apply_ramp(state.ramp_speed, state.target_speed, state.ramp_rate, ship.dt)
    vx = speed.cap(state.ramp_speed, 35)
    ref = 35
    vertical = "hold"
  elseif state.mode == "auto" then
    local dx = state.waypoint_x - ship.x
    local dz = state.waypoint_z - ship.z
    local dist = math.sqrt(dx * dx + dz * dz)
    local stepped = auto.step({
      phase = state.phase,
      y = ship.y,
      dist = dist,
      speed = horiz,
      accel = state.measured_accel,
      profile = state.profile,
    })
    state.phase = stepped.phase
    vx = stepped.horiz_speed
    if stepped.reverse then
      vx = -horiz
    end
    vertical = stepped.vertical
    reverse = stepped.reverse
    ref = 50
    if state.profile == "cruise" then
      ref = 7
    end
  end

  if vertical == "hold" and state.hover_rpm == 0 and math.abs(ship.vy) < 0.05 then
    state.hover_rpm = cfg.climb_rpm * 0.25
  end
  state.hover_rpm = hover.adjust(state.hover_rpm, ship.vy, cfg.hover_gain)
  if state.hover_rpm < 0 then
    state.hover_rpm = 0
  end

  local rsc10, relay2 = mix.x(vx, ref)
  outputs.rsc.rsc10 = rsc10
  outputs.relays.relay2 = relay2
  local rsc11, relay6 = mix.elevation(vertical, state.hover_rpm, cfg.climb_rpm)
  if reverse then
    rsc11, relay6 = mix.elevation("reverse", state.hover_rpm, cfg.climb_rpm)
  end
  outputs.rsc.rsc11 = rsc11
  outputs.relays.relay6 = relay6

  local yaw = 0
  local pitch_err = 0
  local roll_err = 0
  if horiz > 20 or state.mode == "semi" or state.mode == "auto" then
    yaw = wrap(state.bearing - ship.heading)
  end
  if horiz > 20 then
    pitch_err = ship.pitch
    roll_err = ship.roll
  end
  local rsc6, rsc7, rsc8, rsc9 = mix.sides(vy, yaw, cfg.side_gain)
  outputs.rsc.rsc6 = rsc6
  outputs.rsc.rsc7 = rsc7
  outputs.rsc.rsc8 = rsc8
  outputs.rsc.rsc9 = rsc9

  local kind, which = outage.classify(ship.pitch_rate, ship.roll_rate, cfg.outage_threshold)
  local outage_name = nil
  local lift = 0
  if kind == "corner" then
    outage_name = which
    state.balance_time = 0
    local cuts = outage.cutoffs(kind, which)
    for name, on in pairs(cuts) do
      outputs.relays[name] = on
    end
    local live = {
      port_bow = { "rsc2", "rsc5" },
      starboard_stern = { "rsc2", "rsc5" },
      starboard_bow = { "rsc3", "rsc4" },
      port_stern = { "rsc3", "rsc4" },
    }
    for _, rsc_name in ipairs(live[which]) do
      outputs.rsc[rsc_name] = cfg.balance_rpm
    end
  elseif kind == "side" then
    outage_name = which
    if state.balance_side ~= which then
      state.balance_side = which
      state.balance_time = 0
    end
    state.balance_time = state.balance_time + ship.dt
    local toward = (which == "port" and ship.roll_rate < 0) or (which == "starboard" and ship.roll_rate > 0)
    if toward and state.balance_time >= cfg.outage_fail_seconds then
      local cuts = outage.fall_cutoffs()
      for name, on in pairs(cuts) do
        outputs.relays[name] = on
      end
      outputs.rsc.rsc2 = 0
      outputs.rsc.rsc3 = 0
      outputs.rsc.rsc4 = 0
      outputs.rsc.rsc5 = 0
      outputs.rsc.rsc11 = 0
    else
      outputs.rsc.rsc11 = outputs.rsc.rsc11 * outage.live_prop_scale(ship.roll_rate, which)
      if which == "port" then
        outputs.rsc.rsc3 = cfg.balance_rpm
        outputs.rsc.rsc5 = cfg.balance_rpm
      else
        outputs.rsc.rsc2 = cfg.balance_rpm
        outputs.rsc.rsc4 = cfg.balance_rpm
      end
    end
  else
    state.balance_time = 0
    local u2, u3, u4, u5 = mix.ups(pitch_err, roll_err, lift, cfg.up_gain)
    outputs.rsc.rsc2 = u2
    outputs.rsc.rsc3 = u3
    outputs.rsc.rsc4 = u4
    outputs.rsc.rsc5 = u5
  end

  return state, outputs, status_of(state, ship, input.su, outage_name)
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: `ok`

- [ ] **Step 5: Commit**

```
git add src/engine_tick.lua tests/test_engine_tick.lua
git commit -m "Add the engine control tick"
```

---

### Task 13: Peripheral runtime

**Files:**
- Create: `src/runtime.lua`
- Create: `tests/test_runtime.lua`
- Test: `tests/test_runtime.lua`

**Interfaces:**
- Consumes: output tables from `mix.zero` and `diagnostic.apply`
- Produces: `runtime.apply(outputs, devices)`. `devices` is keyed by logical name. A speed controller has `setTargetSpeed(rpm)`. A flight relay boolean uses `setOutput(side, 15 or 0)` on `bottom`, `top`, `front`, `back`, `left`, and `right`. `relay2` uses `setAnalogOutput("bottom", level)`. `outputs.diag_relay` writes only that side on that device and writes 0 on the other five sides.

- [ ] **Step 1: Write the failing test**

```lua
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/test_runtime.lua`
Expected: FAIL, module `runtime` not found.

- [ ] **Step 3: Write minimal implementation**

```lua
local SIDES = { "bottom", "top", "front", "back", "left", "right" }

local M = {}

local function write_all(device, value)
  for _, side in ipairs(SIDES) do
    device.setOutput(side, value)
  end
end

function M.apply(outputs, devices)
  for name, rpm in pairs(outputs.rsc) do
    local device = devices[name]
    if device ~= nil and device.setTargetSpeed ~= nil then
      device.setTargetSpeed(rpm)
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
        local value = 0
        if on == true then
          value = 15
        end
        write_all(device, value)
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
        device.setOutput(side, value)
      end
    end
  end
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: `ok`

- [ ] **Step 5: Commit**

```
git add src/runtime.lua tests/test_runtime.lua
git commit -m "Add peripheral output writes"
```

---

### Task 14: Command keyboard

**Files:**
- Create: `src/command_ui.lua`
- Create: `tests/test_command_ui.lua`
- Test: `tests/test_command_ui.lua`

**Interfaces:**
- Consumes: `protocol.validate`
- Produces: `command_ui.new() -> state` and `command_ui.key(state, name, down) -> state, message or nil`.
  - `up`/`down` held map stick z to 1 and -1. `left`/`right` map stick x to -1 and 1. The pocket's sideways key is not on this computer; `a` and `d` map stick y to -1 and 1.
  - Key up of that name zeros that axis and sends the new stick.
  - `space` is stick z 1. `leftShift` is stick z -1. They share the z axis; releasing either zeros z.
  - `m`, `s`, and `u` send `set_mode` manual, semi, and auto.
  - `e` sends `emergency`. `c` sends `clear_emergency`.
  - `w` toggles profile and sends `set_profile`.
  - Digit entry: `x`, `z`, `y`, `b`, and `v` start a buffer for waypoint x, waypoint z, altitude, bearing, and speed. `enter` sends the matching command. `backspace` deletes one character. `-` and `.` are allowed in the buffer.

- [ ] **Step 1: Write the failing test**

```lua
package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local command_ui = require("command_ui")

local state = command_ui.new()
local msg
state, msg = command_ui.key(state, "right", true)
A.eq(msg.type, "stick", "stick type")
A.eq(msg.x, 1, "forward key is right")
state, msg = command_ui.key(state, "right", false)
A.eq(msg.x, 0, "release")

state, msg = command_ui.key(state, "e", true)
A.eq(msg.type, "emergency", "estop")

state, msg = command_ui.key(state, "y", true)
state, msg = command_ui.key(state, "1", true)
state, msg = command_ui.key(state, "0", true)
state, msg = command_ui.key(state, "enter", true)
A.eq(msg.type, "set_altitude", "altitude")
A.eq(msg.y, 10, "altitude value")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/test_command_ui.lua`
Expected: FAIL, module `command_ui` not found.

- [ ] **Step 3: Write minimal implementation**

```lua
local protocol = require("protocol")

local M = {}

function M.new()
  return {
    stick = { x = 0, y = 0, z = 0 },
    buffer = "",
    field = nil,
    profile = "warp",
    waypoint_x = 0,
    waypoint_z = 0,
  }
end

local function stick_msg(state)
  return protocol.validate({
    type = "stick",
    x = state.stick.x,
    y = state.stick.y,
    z = state.stick.z,
  })
end

local function set_axis(state, axis, value, down)
  if down then
    state.stick[axis] = value
  elseif state.stick[axis] == value then
    state.stick[axis] = 0
  end
  return stick_msg(state)
end

function M.key(state, name, down)
  if name == "right" then
    return state, set_axis(state, "x", 1, down)
  end
  if name == "left" then
    return state, set_axis(state, "x", -1, down)
  end
  if name == "d" then
    return state, set_axis(state, "y", 1, down)
  end
  if name == "a" then
    return state, set_axis(state, "y", -1, down)
  end
  if name == "space" or name == "up" then
    return state, set_axis(state, "z", 1, down)
  end
  if name == "leftShift" or name == "down" then
    return state, set_axis(state, "z", -1, down)
  end
  if not down then
    return state, nil
  end
  if name == "m" then
    return state, protocol.validate({ type = "set_mode", mode = "manual" })
  end
  if name == "s" then
    return state, protocol.validate({ type = "set_mode", mode = "semi" })
  end
  if name == "u" then
    return state, protocol.validate({ type = "set_mode", mode = "auto" })
  end
  if name == "e" then
    return state, protocol.validate({ type = "emergency" })
  end
  if name == "c" then
    return state, protocol.validate({ type = "clear_emergency" })
  end
  if name == "w" then
    if state.profile == "warp" then
      state.profile = "cruise"
    else
      state.profile = "warp"
    end
    return state, protocol.validate({ type = "set_profile", profile = state.profile })
  end
  local fields = { x = "x", z = "z", y = "y", b = "bearing", v = "speed" }
  if fields[name] ~= nil then
    state.field = fields[name]
    state.buffer = ""
    return state, nil
  end
  if state.field ~= nil and (name == "-" or name == "." or (name >= "0" and name <= "9")) then
    state.buffer = state.buffer .. name
    return state, nil
  end
  if name == "backspace" and state.field ~= nil then
    state.buffer = string.sub(state.buffer, 1, #state.buffer - 1)
    return state, nil
  end
  if name == "enter" and state.field ~= nil then
    local number = tonumber(state.buffer)
    local field = state.field
    state.field = nil
    state.buffer = ""
    if number == nil then
      return state, nil
    end
    if field == "x" then
      state.waypoint_x = number
      return state, protocol.validate({ type = "set_waypoint", x = number, z = state.waypoint_z })
    end
    if field == "z" then
      state.waypoint_z = number
      return state, protocol.validate({ type = "set_waypoint", x = state.waypoint_x, z = number })
    end
    if field == "y" then
      return state, protocol.validate({ type = "set_altitude", y = number })
    end
    if field == "bearing" then
      return state, protocol.validate({ type = "set_bearing", bearing = number })
    end
    return state, protocol.validate({ type = "set_speed", speed = number })
  end
  return state, nil
end

return M
```

The waypoint x and z fields must remember the last number on the state. Add `state.waypoint_x` and `state.waypoint_z` inside `M.new` as 0, and in the `enter` branch for `x` and `z` store the number before validating:

```lua
if field == "x" then
  state.waypoint_x = number
  return state, protocol.validate({ type = "set_waypoint", x = number, z = state.waypoint_z })
end
if field == "z" then
  state.waypoint_z = number
  return state, protocol.validate({ type = "set_waypoint", x = state.waypoint_x, z = number })
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: `ok`

- [ ] **Step 5: Commit**

```
git add src/command_ui.lua tests/test_command_ui.lua
git commit -m "Add the command keyboard"
```

---

### Task 15: Pocket screen

**Files:**
- Create: `src/pocket_ui.lua`
- Create: `tests/test_pocket_ui.lua`
- Test: `tests/test_pocket_ui.lua`

**Interfaces:**
- Consumes: `protocol.validate`
- Produces: `pocket_ui.new() -> state` and `pocket_ui.touch(state, x, y, ctx) -> state, message or nil`.
  - Screen is 26 by 20. Buttons, inclusive of their x,y and width, height:
    - manual 1,8 8x2; semi 9,8 8x2; auto 17,8 10x2
    - forward 11,11 4x1; back 11,13 4x1; port 6,12 4x1; starboard 16,12 4x1; up 21,11 5x1; down 21,13 5x1
    - return 1,15 12x2; diagnostic 14,15 12x2
    - emergency 1,18 12x2; clear 14,18 12x2
  - A touch on forward sends stick x=1. Touches outside buttons send nothing.
  - Return calls `ctx.locate()`. A nil or false result returns no message and sets `state.gps_error = true`. A coordinate pair sends `return_to_user`.
  - Diagnostic opens `state.screen = "diagnostic"`. The first device button is `rsc2` at 1,1 8x1 and sends `diagnostic_enter` with `hover = false` the first time, then `diagnostic_set` for `rsc2` at rpm 0.
  - Plus at 10,1 3x1 and minus at 14,1 3x1 change the selected rpm by 1 and send `diagnostic_set`. The pocket does not clamp; the engine does.
  - Hover toggle at 1,3 12x1 sends `diagnostic_enter` with `hover = true`.
  - Elevation plus at 1,4 8x1 sends `diagnostic_elevation` increased by 1 from `state.elevation`.

- [ ] **Step 1: Write the failing test**

```lua
package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local pocket_ui = require("pocket_ui")

local state = pocket_ui.new()
local msg
state, msg = pocket_ui.touch(state, 12, 11, {})
A.eq(msg.type, "stick", "forward")
A.eq(msg.x, 1, "forward axis")

state, msg = pocket_ui.touch(state, 2, 15, { locate = function() return nil end })
A.eq(msg, nil, "no fix")
A.eq(state.gps_error, true, "gps error")

state, msg = pocket_ui.touch(state, 2, 15, { locate = function() return 4, 5 end })
A.eq(msg.type, "return_to_user", "return")
A.eq(msg.x, 4, "return x")
A.eq(msg.z, 5, "return z")

state, msg = pocket_ui.touch(state, 15, 15, {})
A.eq(msg.type, "diagnostic_enter", "enter diag")
state, msg = pocket_ui.touch(state, 11, 1, {})
A.eq(msg.rpm, 1, "plus")
A.eq(msg.device, "rsc2", "device")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `lua tests/test_pocket_ui.lua`
Expected: FAIL, module `pocket_ui` not found.

- [ ] **Step 3: Write minimal implementation**

```lua
local protocol = require("protocol")

local M = {}

local ROOT = {
  { id = "manual", x = 1, y = 8, w = 8, h = 2 },
  { id = "semi", x = 9, y = 8, w = 8, h = 2 },
  { id = "auto", x = 17, y = 8, w = 10, h = 2 },
  { id = "forward", x = 11, y = 11, w = 4, h = 1 },
  { id = "back", x = 11, y = 13, w = 4, h = 1 },
  { id = "port", x = 6, y = 12, w = 4, h = 1 },
  { id = "starboard", x = 16, y = 12, w = 4, h = 1 },
  { id = "up", x = 21, y = 11, w = 5, h = 1 },
  { id = "down", x = 21, y = 13, w = 5, h = 1 },
  { id = "return", x = 1, y = 15, w = 12, h = 2 },
  { id = "diagnostic", x = 14, y = 15, w = 12, h = 2 },
  { id = "emergency", x = 1, y = 18, w = 12, h = 2 },
  { id = "clear", x = 14, y = 18, w = 12, h = 2 },
}

local function inside(button, x, y)
  return x >= button.x and x < button.x + button.w and y >= button.y and y < button.y + button.h
end

local function find(buttons, x, y)
  for _, button in ipairs(buttons) do
    if inside(button, x, y) then
      return button.id
    end
  end
  return nil
end

function M.new()
  return {
    screen = "root",
    gps_error = false,
    device = "rsc2",
    rpm = 0,
    elevation = 0,
    hover = false,
    diag_open = false,
  }
end

local function stick(x, y, z)
  return protocol.validate({ type = "stick", x = x, y = y, z = z })
end

function M.touch(state, x, y, ctx)
  if state.screen == "diagnostic" then
    local id = find({
      { id = "device", x = 1, y = 1, w = 8, h = 1 },
      { id = "plus", x = 10, y = 1, w = 3, h = 1 },
      { id = "minus", x = 14, y = 1, w = 3, h = 1 },
      { id = "hover", x = 1, y = 3, w = 12, h = 1 },
      { id = "elev", x = 1, y = 4, w = 8, h = 1 },
    }, x, y)
    if id == "plus" then
      state.rpm = state.rpm + 1
      return state, protocol.validate({ type = "diagnostic_set", device = state.device, rpm = state.rpm })
    end
    if id == "minus" then
      state.rpm = state.rpm - 1
      return state, protocol.validate({ type = "diagnostic_set", device = state.device, rpm = state.rpm })
    end
    if id == "hover" then
      state.hover = true
      return state, protocol.validate({ type = "diagnostic_enter", hover = true })
    end
    if id == "elev" then
      state.elevation = state.elevation + 1
      return state, protocol.validate({ type = "diagnostic_elevation", rpm = state.elevation })
    end
    if id == "device" and not state.diag_open then
      state.diag_open = true
      return state, protocol.validate({ type = "diagnostic_enter", hover = false })
    end
    return state, nil
  end

  local id = find(ROOT, x, y)
  if id == "forward" then
    return state, stick(1, 0, 0)
  end
  if id == "back" then
    return state, stick(-1, 0, 0)
  end
  if id == "starboard" then
    return state, stick(0, 1, 0)
  end
  if id == "port" then
    return state, stick(0, -1, 0)
  end
  if id == "up" then
    return state, stick(0, 0, 1)
  end
  if id == "down" then
    return state, stick(0, 0, -1)
  end
  if id == "manual" or id == "semi" or id == "auto" then
    return state, protocol.validate({ type = "set_mode", mode = id })
  end
  if id == "emergency" then
    return state, protocol.validate({ type = "emergency" })
  end
  if id == "clear" then
    return state, protocol.validate({ type = "clear_emergency" })
  end
  if id == "return" then
    local gx, gz = ctx.locate()
    if gx == nil then
      state.gps_error = true
      return state, nil
    end
    state.gps_error = false
    return state, protocol.validate({ type = "return_to_user", x = gx, z = gz })
  end
  if id == "diagnostic" then
    state.screen = "diagnostic"
    state.diag_open = true
    return state, protocol.validate({ type = "diagnostic_enter", hover = false })
  end
  return state, nil
end

return M
```

- [ ] **Step 4: Run test to verify it passes**

Run: `lua tests/run.lua`
Expected: `ok`

- [ ] **Step 5: Commit**

```
git add src/pocket_ui.lua tests/test_pocket_ui.lua
git commit -m "Add the pocket screen"
```

---

### Task 16: ComputerCraft entry points

**Files:**
- Create: `programs/engine.lua`
- Create: `programs/command.lua`
- Create: `programs/pocket.lua`
- Test: `tests/run.lua` still passes. These files are loaded by ComputerCraft, not by the desktop runner.

**Interfaces:**
- Consumes: every `src` module above
- Produces: three programs. `programs/engine.lua` calls `engine_tick.tick` and `runtime.apply`. `programs/command.lua` calls `command_ui.key` and `rednet.send`. `programs/pocket.lua` calls `pocket_ui.touch`, `gps.locate`, and `rednet.send`.

- [ ] **Step 1: Write the programs**

`programs/engine.lua` sets `package.path` to the directory containing `src`, loads config, wraps peripherals by `config.names`, and runs:

```lua
local config = require("config")
local startup = require("startup")
local engine_tick = require("engine_tick")
local runtime = require("runtime")
local protocol = require("protocol")
local monitors = require("monitors")
local mfd = require("mfd")

local cfg = config.default()
local state = engine_tick.new_state()
local modem = peripheral.wrap(cfg.names.ender_modem)
rednet.open(cfg.names.ender_modem)
local wired = cfg.names.wired_modem
rednet.open(wired)

local function present_map()
  local found = {}
  for key, network_name in pairs(cfg.names) do
    if peripheral.wrap(network_name) ~= nil or peripheral.isPresent(network_name) then
      found[key] = true
    end
  end
  return found
end

local missing = startup.missing(present_map(), config.required_names(cfg))
local ready = #missing == 0

local function collect_ship()
  local pos = ship.getWorldspacePosition()
  local vel = ship.getVelocity()
  local pitch, yaw, roll = ship.getQuaternion():toEuler()
  local omega = ship.getAngularVelocity()
  return {
    x = pos.x, y = pos.y, z = pos.z,
    vx = vel.x, vy = vel.y, vz = vel.z,
    pitch = pitch, roll = roll, heading = yaw,
    pitch_rate = omega.x, roll_rate = omega.z,
    dt = 0.05,
  }
end
```

`toEuler` on this pack is YXZ and returns pitch, yaw, roll in radians. `getAngularVelocity()` is a vector whose x component is pitch rate and whose z component is roll rate. Positive pitch rate means the nose is dropping. Positive roll rate means starboard is dropping.

Each loop:

```lua
local _, message = rednet.receive(0)
local command = protocol.validate(message)
local su = 0
local stress = peripheral.wrap(cfg.names.stressometer)
if stress ~= nil and stress.getStress ~= nil then
  su = stress.getStress()
end
local sample = collect_ship()
local outputs
state, outputs = engine_tick.tick(state, {
  ship = sample,
  command = command,
  su = su,
  ready = ready,
  stick_fresh = command ~= nil and command.type == "stick",
  config = cfg,
})
local devices = {}
for key, network_name in pairs(cfg.names) do
  devices[key] = peripheral.wrap(network_name)
end
runtime.apply(outputs, devices)
```

Open both modems before the loop. `rednet.receive(0)` is non-blocking when the timeout is 0. Sleep `0.05` at the bottom of the loop so `dt` matches.

On startup, wrap every monitor with `peripheral.find("monitor")`, call `setTextScale(0.5)` and `getSize()`, pass `{name, w, h}` to `monitors.assign`, and draw the page name on line 1. On `monitor_touch`, call `mfd.hit` with that monitor's size and the sorted name list, then `monitors.swap`.

If `ready` is false, write `missing` on the engine term and on every monitor, and still call `runtime.apply` so outputs stay zero.

`programs/command.lua`:

```lua
local command_ui = require("command_ui")
rednet.open("back")
local state = command_ui.new()
while true do
  local event, key, held = os.pullEvent()
  if event == "key" then
    local name = keys.getName(key)
    local _, message = command_ui.key(state, name, true)
    if message ~= nil then
      rednet.broadcast(message)
    end
  elseif event == "key_up" then
    local name = keys.getName(key)
    local _, message = command_ui.key(state, name, false)
    if message ~= nil then
      rednet.broadcast(message)
    end
  end
end
```

The command computer's wired modem is on the side the player attaches. `rednet.open` uses that side name. The plan uses `"back"` as the default; change the string to the side where the modem sits.

`programs/pocket.lua`:

```lua
local pocket_ui = require("pocket_ui")
rednet.open("back")
local state = pocket_ui.new()
while true do
  local event, _, x, y = os.pullEvent()
  if event == "mouse_click" then
    local _, message = pocket_ui.touch(state, x, y, {
      locate = function()
        return gps.locate(2)
      end,
    })
    if message ~= nil then
      rednet.broadcast(message)
    end
  end
end
```

A pocket ender modem opens with `rednet.open("back")` after the ender upgrade is installed. `gps.locate(2)` waits up to 2 seconds.

- [ ] **Step 2: Run the desktop tests**

Run: `lua tests/run.lua`
Expected: `ok`

- [ ] **Step 3: Commit**

```
git add programs/engine.lua programs/command.lua programs/pocket.lua
git commit -m "Add the three computer programs"
```

---

## Spec coverage

- Hardware names, climb rpm, and modem roles: Task 11 and Task 16.
- Shared command tables and ignored unknown messages: Task 8.
- Manual, semi, automatic, hover, brake, return-to-user: Tasks 1-4 and Task 12.
- High-speed nose and heading: `engine_tick.tick` when horizontal speed is above 20.
- One-corner, one-side, and failed-side-thruster outages: Task 5 and Task 12.
- Monitor size, pages, and touch swap: Tasks 6, 7, and 16.
- SU in status: Task 12.
- Diagnostic clamp, one device, hover exclusion, elevation set: Tasks 10 and 15.
- Startup refusal: Tasks 11 and 12.
- Desktop tests versus ship checks: desktop tests are the `lua tests/run.lua` steps. The ship checks in the spec are run after the programs are copied onto the three computers.

## Ship checks after copy

These need the ship. They are not part of `lua tests/run.lua`.

- Remove one configured name and boot the engine. Outputs stay zero and the missing name is on a monitor.
- Manual from the command keys and from the pocket moves at 3 m/s and stops when released.
- Semi reaches a commanded speed and bearing.
- Automatic climbs, tracks, stops inside 10 blocks, and descends.
- The two larger monitors start on Flight and Navigation. A bottom-row touch swaps pages.
- Emergency zeros outputs and ignores stick until clear.
- Return does nothing when GPS has no fix, and sends X and Z when it does.
- Diagnostic refuses a requested 100 RPM and applies 32. Hover diagnostic leaves RSC 11 at the entered elevation and will not cut Relay 7.
