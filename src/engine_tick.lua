local config = require("config")
local manual = require("manual")
local speed = require("speed")
local auto = require("auto")
local outage = require("outage")
local mix = require("mix")
local diagnostic = require("diagnostic")
local jobs = require("jobs")
local pid = require("pid")
local stress = require("stress")
local numeric = require("numeric")
local frame = require("frame")
local control = require("control")

local M = {}

-- The elevation actuator keeps one integer for about this long. The command
-- is the acceleration that still finishes that window near the setpoint, so a
-- held target cannot bang between a near-cut and a hard climb.
local HOLD_WINDOW = 1.5
local ACCEL_CAP = 4
local HOLD_ROOM = 2

local function clamp_accel(accel)
  if accel > ACCEL_CAP then
    return ACCEL_CAP
  end
  if accel < -ACCEL_CAP then
    return -ACCEL_CAP
  end
  return accel
end

local function accel_from_rpm(rpm, equilibrium, at_y)
  local eq = equilibrium * pid.thrust_scale(at_y)
  if eq <= 0 or rpm == nil or rpm <= 0 then
    return -10
  end
  local specific = 10 * ((rpm / eq) ^ 1.2)
  return specific - 10
end

local function rpm_for_accel(accel, equilibrium, at_y)
  local specific = 10 + accel
  if specific < 0 then
    specific = 0
  end
  local eq = equilibrium * pid.thrust_scale(at_y)
  return config.clamp_rpm(eq * ((specific / 10) ^ (1 / 1.2)))
end

local function accel_vs_anchor(rpm, anchor)
  if anchor == nil or anchor <= 0 or rpm == nil or rpm <= 0 then
    return nil
  end
  return 10 * ((rpm / anchor) ^ 1.2) - 10
end

local function rpm_vs_anchor(anchor, accel)
  local specific = 10 + accel
  if specific < 0 then
    specific = 0
  end
  return config.clamp_rpm(anchor * ((specific / 10) ^ (1 / 1.2)))
end

-- The flying RPM, moved with the density curve when the ship changes height.
local function anchor_here(state, ship)
  local anchor = state.elev_anchor
  if anchor == nil or anchor <= 0 or ship == nil or ship.y == nil or state.elev_anchor_y == nil then
    return nil
  end
  local from_scale = pid.thrust_scale(state.elev_anchor_y)
  local to_scale = pid.thrust_scale(ship.y)
  if from_scale <= 0 then
    return nil
  end
  return anchor * to_scale / from_scale
end

local function note_anchor(state, ship, rpm, measured, vy)
  if rpm == nil or rpm <= 0 or ship == nil or ship.y == nil then
    return
  end
  -- A steady climb has almost no acceleration. Storing that RPM as the hover
  -- makes the next stop the climbing integer, and the hold freezes it.
  if measured == nil or math.abs(measured) >= 0.35 or vy == nil or math.abs(vy) >= 0.1 then
    return
  end
  if state.elev_anchor ~= nil and state.elev_anchor_y ~= nil then
    local from_scale = pid.thrust_scale(state.elev_anchor_y)
    local to_scale = pid.thrust_scale(ship.y)
    local projected = state.elev_anchor
    if from_scale > 0 then
      projected = state.elev_anchor * to_scale / from_scale
    end
    if projected <= 0 or math.abs(rpm - projected) / projected > 0.15 then
      return
    end
  end
  state.elev_anchor = rpm
  state.elev_anchor_y = ship.y
end

-- A stale trim divides the model RPM into a harder acceleration than the one
-- just requested. Once the hull has actually held an RPM, keep that request.
local function clamp_to_anchor(state, ship, rpm, intended)
  local anchor = anchor_here(state, ship)
  if anchor == nil or rpm == nil or intended == nil then
    return rpm
  end
  local got = accel_vs_anchor(rpm, anchor)
  if got == nil or math.abs(got - intended) <= 0.15 then
    return rpm
  end
  return rpm_vs_anchor(anchor, intended)
end

-- The density curve used to turn acceleration into RPM does not match this
-- hull. When the held target is the RPM we just sent and the ship does not
-- accelerate the way that RPM predicts, shift later commands onto the
-- equilibrium the ship is actually flying. A 0.05s tick is shorter than the
-- sample, so the window stays open across ticks instead of restarting.
local function arm_elev_window(state, ship, held_rpm, now)
  state.elev_window_vy = ship.vy
  state.elev_window_clock = now
  state.elev_window_rpm = held_rpm
  state.elev_window_ticks = 0
end

local function learn_elev_scale(state, ship, held_rpm)
  if ship == nil or ship.vy == nil or ship.y == nil or state.pid_gains == nil then
    return
  end
  local now = os.clock()
  if held_rpm ~= nil then
    held_rpm = math.abs(held_rpm)
  end
  local window_rpm = state.elev_window_rpm
  local window_clock = state.elev_window_clock
  local window_vy = state.elev_window_vy
  local same_rpm = held_rpm ~= nil and held_rpm > 0 and window_rpm ~= nil
      and math.abs(held_rpm - window_rpm) <= 1
  if window_clock == nil or window_vy == nil or not same_rpm then
    if held_rpm ~= nil and held_rpm > 0 and state.elev_cmd ~= nil
        and math.abs(held_rpm - state.elev_cmd) <= 1 then
      arm_elev_window(state, ship, held_rpm, now)
    else
      state.elev_window_vy = nil
      state.elev_window_clock = nil
      state.elev_window_rpm = nil
      state.elev_window_ticks = nil
    end
    return
  end
  state.elev_window_ticks = (state.elev_window_ticks or 0) + 1
  local wall = now - window_clock
  if wall < 0.15 then
    return
  end
  if wall > 1.5 then
    arm_elev_window(state, ship, held_rpm, now)
    return
  end
  -- The live computer often waits longer than the nominal step, and the
  -- hull's equilibrium is a small velocity change. That sample used to be
  -- dropped, so the trim stayed low and the command kept climbing.
  local actual_dv = ship.vy - window_vy
  local predicted = accel_from_rpm(held_rpm, state.pid_gains.equilibrium, ship.y)
  if math.abs(actual_dv - predicted * wall) <= 0.08 then
    local matched = actual_dv / wall
    if math.abs(matched) < 0.15 then
      note_anchor(state, ship, held_rpm, matched, ship.vy)
    end
    arm_elev_window(state, ship, held_rpm, now)
    return
  end
  local measured = actual_dv / wall
  if measured > 8 or measured < -8 then
    arm_elev_window(state, ship, held_rpm, now)
    return
  end
  local specific = measured + 10
  if specific < 0.5 then
    arm_elev_window(state, ship, held_rpm, now)
    return
  end
  local model_eq = state.pid_gains.equilibrium * pid.thrust_scale(ship.y)
  if model_eq <= 0 then
    arm_elev_window(state, ship, held_rpm, now)
    return
  end
  local true_eq = held_rpm / ((specific / 10) ^ (1 / 1.2))
  if true_eq <= 0 then
    arm_elev_window(state, ship, held_rpm, now)
    return
  end
  local sample = model_eq / true_eq
  -- The live hull hovers well below the density curve. A sample outside a
  -- narrow band is still the equilibrium, and dropping it leaves every mode
  -- commanding a climb.
  if sample < 0.5 or sample > 4 then
    arm_elev_window(state, ship, held_rpm, now)
    return
  end
  note_anchor(state, ship, true_eq, measured, ship.vy)
  local prev = state.elev_scale
  if prev == nil then
    prev = 1
  end
  -- A held integer is one window behind the speed it was chosen for, so a
  -- single window can read the opposite acceleration. Step only after two
  -- samples agree on the direction.
  local direction = 0
  if sample > prev + 0.01 then
    direction = 1
  elseif sample < prev - 0.01 then
    direction = -1
  end
  if direction == 0 or direction ~= state.elev_scale_sign then
    state.elev_scale_sign = direction
    if direction == 0 then
      state.elev_scale_run = 0
    else
      state.elev_scale_run = 1
    end
    arm_elev_window(state, ship, held_rpm, now)
    return
  end
  state.elev_scale_run = (state.elev_scale_run or 1) + 1
  -- A single laggy tick can see the rotor still changing speed. Step toward
  -- the sample instead of jumping, so that noise cannot swing the hover RPM.
  local delta = 0.5 * (sample - prev)
  local cap = 0.04
  if math.abs(sample - prev) > 0.25 then
    cap = 0.35
  end
  if delta > cap then
    delta = cap
  elseif delta < -cap then
    delta = -cap
  end
  local blended = prev + delta
  if blended < 0.5 then
    blended = 0.5
  elseif blended > 4 then
    blended = 4
  end
  state.elev_scale = blended
  arm_elev_window(state, ship, held_rpm, now)
end

-- 430 RPM is the light-hull hover. Clockwork propeller force depends on
-- blade length, pitch, and rotational speed, and each prop is force-capped,
-- so ship mass does not convert to an RPM. While this hull is asked to climb
-- and is not rising, raise that sea-level equilibrium by half, no more than
-- once every two seconds. Once it is above the target and still climbing,
-- lower the equilibrium so the hover RPM can level the ship. Side and
-- forward props use the same scale.
local LIFT_VY = 0.25
local LIFT_WAIT = 2
local LIFT_STEP = 2
local LIFT_TRIM = 1.15

local function set_lift_equilibrium(state, eq, cfg)
  local floor_rpm = cfg.hover_equilibrium or 430
  local cap = cfg.max_rpm or 32769
  if eq < floor_rpm then
    eq = floor_rpm
  end
  if eq > cap then
    eq = cap
  end
  local current = state.pid_gains.equilibrium or floor_rpm
  if math.abs(eq - current) <= current * 0.02 then
    return false
  end
  state.pid_gains = pid.calibrate(eq, 0.05)
  state.elevation_equilibrium = eq
  state.lift_jump = true
  return true
end

local function calibrate_lift(state, ship, cfg, now)
  if ship == nil or ship.y == nil or ship.vy == nil then
    return
  end
  if state.pid_gains == nil then
    state.pid_gains = pid.calibrate(cfg.hover_equilibrium, 0.05)
  end
  local dead = cfg.altitude_deadzone or 8
  local target = state.altitude
  local eq = state.pid_gains.equilibrium or cfg.hover_equilibrium or 430
  -- Past the setpoint and still going up. The RPM that broke ground is more
  -- than hover, and the altitude controller cannot command below a fraction
  -- of it, so the hull would climb without a lower equilibrium.
  if target ~= nil and ship.y > target and ship.vy > 0.05 then
    state.lift_stuck_since = nil
    if state.lift_trim_since == nil then
      state.lift_trim_since = now
      return
    end
    if now - state.lift_trim_since < LIFT_WAIT then
      return
    end
    if set_lift_equilibrium(state, eq / LIFT_TRIM, cfg) then
      state.lift_trim_since = now
    end
    return
  end
  state.lift_trim_since = nil
  if target == nil or ship.y + dead >= target or ship.vy >= LIFT_VY then
    state.lift_stuck_since = nil
    return
  end
  if state.lift_stuck_since == nil then
    state.lift_stuck_since = now
    return
  end
  if now - state.lift_stuck_since < LIFT_WAIT then
    return
  end
  local cap = cfg.max_rpm or 32769
  local raised = eq * LIFT_STEP
  if raised > cap then
    raised = cap
  end
  if set_lift_equilibrium(state, raised, cfg) then
    -- The old anchor was learned while the hull was not leaving the ground.
    -- Leaving it in place pulls the new climb straight back down.
    state.elev_anchor = nil
    state.elev_anchor_y = nil
    state.lift_stuck_since = now
  end
end

local function device_scale(scale)
  if scale == nil or scale <= 0 then
    return 1
  end
  return scale
end

-- Accel of a device RPM after the learned hull scale. The model equation
-- wants the unscaled equilibrium RPM.
local function device_accel(device_rpm, equilibrium, at_y, scale)
  scale = device_scale(scale)
  if device_rpm == nil or device_rpm <= 0 then
    return -10
  end
  return accel_from_rpm(device_rpm * scale, equilibrium, at_y)
end

-- Where a descent ends if this integer stays on the shaft. Crediting a later
-- spool-up lets every tick postpone the brake, and the ship arrives at the
-- target still doing the speed that spool was supposed to remove.
local function descent_hold_y(y, vy, rpm, equilibrium, scale)
  scale = device_scale(scale)
  for _ = 1, 80 do
    if vy >= -0.05 then
      return y
    end
    local accel = device_accel(rpm, equilibrium, y, scale)
    y = y + vy * HOLD_WINDOW + 0.5 * accel * HOLD_WINDOW * HOLD_WINDOW
    vy = vy + accel * HOLD_WINDOW
  end
  return y
end

local function descent_step_stops(y, vy, target, device_rpm, equilibrium, scale)
  local accel = device_accel(device_rpm, equilibrium, y, scale)
  local next_v = vy + accel * HOLD_WINDOW
  -- Budget the fall against a 0.5 m/s^2 stop. The density model can arrest a
  -- faster fall on paper and still cross the target once the spool is late.
  local gap = y - target
  if gap < 4 then
    gap = 4
  end
  -- Half of the 0.5 m/s^2 cap. Tracking the looser cap still arrives at the
  -- target near 16 m/s, and the following spool cannot take that speed out.
  local v_cap = 0.5 * math.sqrt(gap)
  if next_v < -v_cap then
    return false
  end
  local next_y = y + vy * HOLD_WINDOW + 0.5 * accel * HOLD_WINDOW * HOLD_WINDOW
  local stopped = descent_hold_y(next_y, next_v, device_rpm, equilibrium, scale)
  -- Keep a quarter of the gap in hand. A stop that spends the whole gap
  -- crosses the target when this integer is late onto the shaft.
  local keep = (y - target) * 0.25
  if keep < HOLD_ROOM then
    keep = HOLD_ROOM
  end
  return stopped >= target + keep
end

-- Where constant accel for one hold, then a full-cap stop, comes to rest.
local function held_stop(y, vy, accel)
  local H = HOLD_WINDOW
  local y1 = y + vy * H + 0.5 * accel * H * H
  local v1 = vy + accel * H
  if v1 > 0 then
    y1 = y1 + (v1 * v1) / (2 * ACCEL_CAP)
  elseif v1 < 0 then
    y1 = y1 - (v1 * v1) / (2 * ACCEL_CAP)
  end
  return y1
end

-- Keep the requested acceleration when freezing it cannot fly through the
-- setpoint. Otherwise use the strongest acceleration toward the setpoint
-- that still stops inside the room after one held window.
-- A derivative brake can come to rest while the ship is still outside that
-- room. The hold freezes the brake and altitude cycles short of the setpoint.
-- Ease only that early brake so the same acceleration reaches the room.
local function hold_safe_accel(y, vy, target, requested, speed_cap)
  if y == nil or target == nil then
    return clamp_accel(requested)
  end
  vy = vy or 0
  local accel = clamp_accel(requested)
  local function far_side(a)
    local y_stop = held_stop(y, vy, a)
    if y <= target and y_stop > target + HOLD_ROOM then
      return true
    end
    if y >= target and y_stop < target - HOLD_ROOM then
      return true
    end
    return false
  end
  -- Positive acceleration above the setpoint is a climb. Negative acceleration
  -- below it is a descent. Braking the opposite velocity has to stay available.
  if y < target - HOLD_ROOM and vy <= 0 and accel < 0 then
    accel = 0
  elseif y > target + HOLD_ROOM and vy >= 0 and accel > 0 then
    accel = 0
  end
  local toward = (y < target - HOLD_ROOM and vy > 0) or (y > target + HOLD_ROOM and vy < 0)
  if toward and accel * vy < 0 then
    local rest = y - (vy * vy) / (2 * accel)
    local short = (y < target and rest < target - HOLD_ROOM) or (y > target and rest > target + HOLD_ROOM)
    if short then
      local aim = target - HOLD_ROOM
      if y > target then
        aim = target + HOLD_ROOM
      end
      local gap = aim - y
      if gap ~= 0 then
        local softer = -(vy * vy) / (2 * gap)
        local brakes = (vy > 0 and softer < 0) or (vy < 0 and softer > 0)
        if brakes and math.abs(softer) < math.abs(accel) then
          accel = clamp_accel(softer)
        end
      end
    end
  end
  -- Holding a brake past zero speed starts the next window the other way.
  -- Take off at most the speed this window can remove.
  if math.abs(vy) > 0.2 and accel * vy < 0 then
    local limit = -vy / HOLD_WINDOW
    if math.abs(accel) > math.abs(limit) then
      accel = limit
    end
  end
  -- The integer stays out for the whole window. After a reversal, that
  -- window may not build a faster speed than the one it just removed.
  local function finish(chosen)
    if speed_cap ~= nil and speed_cap > 0 then
      local end_v = vy + chosen * HOLD_WINDOW
      if end_v > speed_cap then
        chosen = (speed_cap - vy) / HOLD_WINDOW
      elseif end_v < -speed_cap then
        chosen = (-speed_cap - vy) / HOLD_WINDOW
      end
    end
    return clamp_accel(chosen)
  end
  if not far_side(accel) then
    return finish(accel)
  end
  local lo, hi
  if y <= target then
    if far_side(-ACCEL_CAP) then
      return finish(-ACCEL_CAP)
    end
    lo = -ACCEL_CAP
    hi = accel
  else
    if far_side(ACCEL_CAP) then
      return finish(ACCEL_CAP)
    end
    lo = accel
    hi = ACCEL_CAP
  end
  for _ = 1, 24 do
    local mid = (lo + hi) / 2
    if y <= target then
      if far_side(mid) then
        hi = mid
      else
        lo = mid
      end
    elseif far_side(mid) then
      lo = mid
    else
      hi = mid
    end
  end
  if y <= target then
    return finish(lo)
  end
  return finish(hi)
end

local function wrap(angle)
  return numeric.wrap(angle)
end

function M.new_state()
  return {
    mode = "semi",
    emergency = false,
    stick = { x = 0, y = 0, z = 0 },
    altitude = 100,
    bearing = 0,
    target_speed = 0,
    ramp_rate = 0,
    ramp_speed = 0,
    waypoint_x = nil,
    waypoint_z = nil,
    profile = "warp",
    phase = "climb",
    hover_rpm = 0,
    x_rpm = 0,
    seeded = false,
    altitude_set = false,
    job = nil,
    cancel = false,
    pid_integral = 0,
    pid_gains = nil,
    elevation_equilibrium = nil,
    brake_x = nil,
    brake_z = nil,
    brake_elev = nil,
    stop_distance = 0,
    measured_accel = nil,
    last_horiz = 0,
    speed_seeded = false,
    balance_time = 0,
    balance_side = nil,
    modeled_su = 0,
    diagnostic = false,
    hover_diag = false,
    diag_selection = nil,
    diag_elevation = 0,
    outputs_disabled = false,
  }
end

local function clamp_outputs(outputs)
  for name, rpm in pairs(outputs.rsc) do
    outputs.rsc[name] = config.clamp_rpm(rpm)
  end
  return outputs
end

local SIDE_NAMES = { "rsc13", "rsc14", "rsc15", "rsc12" }
local RCS_RPM_CAP = 1000
local ELEVATION_RPM_CAP = 4000

-- hold_stop sizes rpm for one propeller. Four signed props share that force.
local function share_rpm(rpm, props)
  if rpm == nil or rpm == 0 then
    return 0
  end
  local magnitude = math.abs(rpm) * ((1 / props) ^ (1 / 1.2))
  if rpm < 0 then
    return -magnitude
  end
  return magnitude
end

local function apply_side_brake(outputs, rpm)
  local shared = share_rpm(rpm, #SIDE_NAMES)
  local rsc13, rsc14, rsc15, rsc12 = mix.sides(shared, 0, 1)
  outputs.rsc.rsc13 = rsc13
  outputs.rsc.rsc14 = rsc14
  outputs.rsc.rsc15 = rsc15
  outputs.rsc.rsc12 = rsc12
end

local function cap_rpm(rpm, limit)
  if rpm == nil then
    return rpm
  end
  if rpm > limit then
    return limit
  end
  if rpm < -limit then
    return -limit
  end
  return rpm
end

local function cap_side_rpm(outputs)
  for _, name in ipairs(SIDE_NAMES) do
    local rpm = outputs.rsc[name]
    if rpm ~= nil then
      outputs.rsc[name] = cap_rpm(rpm, RCS_RPM_CAP)
    end
  end
end

local function apply_side_signs(outputs, cfg)
  local signs = cfg.side_sign
  if signs == nil then
    return
  end
  for _, name in ipairs(SIDE_NAMES) do
    local sign = signs[name]
    if type(sign) == "number" and sign ~= 1 then
      outputs.rsc[name] = (outputs.rsc[name] or 0) * sign
    end
  end
end

local function status_of(state, ship, su, outage_name)
  local altitude = ship.y
  if state.altitude_set and type(state.altitude) == "number" then
    altitude = state.altitude
  end
  return {
    mode = state.mode,
    altitude = altitude,
    vertical_speed = ship.vy,
    horizontal_speed = math.sqrt(ship.vx * ship.vx + ship.vz * ship.vz),
    heading = ship.heading,
    target = state.mode,
    su = su,
    su_remaining = state.su_remaining,
    stop_distance = state.stop_distance,
    job = state.job,
    outage = outage_name,
    emergency = state.emergency,
    phase = state.phase,
    hover_rpm = state.hover_rpm,
    diag_elevation = state.diag_elevation,
  }
end

local function clear_approach(state)
  state.approach_cap = nil
  state.approach_sign = nil
  state.approach_peak = nil
end

local function adopt_altitude(state, y)
  state.cancel = false
  state.altitude = y
  state.altitude_set = true
  state.job = "altitude"
  state.phase = "hold"
  state.brake_elev = nil
  clear_approach(state)
  state.waypoint_x = nil
  state.waypoint_z = nil
  state.target_speed = 0
  state.pid_integral = 0
  state.altitude_adopted = true
end

local function apply_command(state, command, current_rpm)
  if command == nil then
    return
  end
  if command.type == "emergency" then
    state.emergency = true
    state.stick = { x = 0, y = 0, z = 0 }
    if state.mode == "diagnostic" then
      state.mode = "semi"
    end
    state.diagnostic = false
    state.hover_diag = false
    state.diag_selection = nil
    return
  end
  if command.type == "clear_emergency" then
    state.emergency = false
    state.outputs_disabled = false
    state.mode = "semi"
    return
  end
  if state.emergency then
    return
  end
  if command.type == "diagnostic_all" then
    state.outputs_disabled = false
    state.diagnostic = true
    state.hover_diag = false
    state.mode = "diagnostic"
    state.diag_selection = { type = "diagnostic_all", rpm = 15 }
    state.stick = { x = 0, y = 0, z = 0 }
    return
  end
  if command.type == "diagnostic_enter" then
    state.outputs_disabled = false
    if command.hover and not state.hover_diag then
      state.diag_elevation = math.abs(current_rpm or state.hover_rpm or 0)
    end
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
    state.mode = "semi"
    state.outputs_disabled = true
    state.hover_rpm = 0
    state.x_rpm = 0
    state.pid_integral = 0
    state.job = nil
    state.waypoint_x = nil
    state.waypoint_z = nil
    state.altitude_set = false
    state.target_speed = 0
    state.ramp_speed = 0
    state.stick = { x = 0, y = 0, z = 0 }
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
  if state.diagnostic and (command.type == "set_mode" or command.type == "cancel_jobs") then
    state.diagnostic = false
    state.hover_diag = false
    state.diag_selection = nil
    state.mode = "semi"
  end
  if state.diagnostic then
    return
  end
  state.outputs_disabled = false
  if command.type == "stick" then
    local latched = command.latched_altitude
    if type(latched) == "number" and (state.altitude_set ~= true or state.altitude ~= latched) then
      adopt_altitude(state, latched)
    end
    state.stick = { x = command.x, y = command.y, z = command.z }
    if command.x ~= 0 or command.y ~= 0 or command.z ~= 0 then
      state.cancel = false
    end
    return
  end
  if command.type == "set_mode" then
    -- Semi is the only flight mode. Manual, automatic, and idle do not apply.
    if command.mode ~= "semi" then
      return
    end
    state.mode = "semi"
    clear_approach(state)
    state.ramp_speed = 0
    state.ramp_rate = speed.ramp_rate(0, state.target_speed)
    return
  end
  if command.type == "set_altitude" then
    adopt_altitude(state, command.y)
    return
  end
  if command.type == "cancel_jobs" then
    state.cancel = true
    state.job = nil
    state.altitude_set = false
    state.phase = "hold"
    state.target_speed = 0
    state.ramp_speed = 0
    state.ramp_rate = 0
    state.waypoint_x = nil
    state.waypoint_z = nil
    state.pid_integral = 0
    state.brake_x = nil
    state.brake_z = nil
    state.brake_elev = nil
    return
  end
  if command.type == "set_bearing" then
    state.bearing = command.bearing
    state.bearing_set = true
    return
  end
  if command.type == "set_speed" then
    local target = speed.cap(command.speed, 35)
    state.ramp_speed = speed.cap(state.ramp_speed or 0, 35)
    state.target_speed = target
    state.ramp_rate = speed.ramp_rate(state.ramp_speed, target)
    return
  end
  if command.type == "set_waypoint" or command.type == "return_to_user" or command.type == "set_profile" then
    return
  end
end

function M.tick(state, input)
  -- A rednet event queued from the debug shell is pulled by that shell and
  -- never reaches this loop. One command left on the state takes the empty
  -- slot and runs through the same handler as a delivered command.
  local commands = {}
  if type(input.commands) == "table" then
    for i = 1, #input.commands do
      commands[#commands + 1] = input.commands[i]
    end
  end
  if input.command ~= nil then
    commands[#commands + 1] = input.command
  end
  if #commands == 0 and type(state.command_queue) == "table" and state.command_queue.type ~= nil then
    commands[1] = state.command_queue
    state.command_queue = nil
    if commands[1].type == "stick" then
      input.stick_fresh = true
    end
  end
  local cfg = input.config
  state.altitude_adopted = false
  for i = 1, #commands do
    apply_command(state, commands[i], input.current_elevation_rpm)
  end
  if state.mode ~= "diagnostic" then
    state.mode = "semi"
  end
  local ship = input.ship
  -- A missing device or an emergency stop must not store the controller RPM.
  -- The next ready tick would command it.
  if not state.seeded and input.ready ~= false and not state.emergency then
    local recalled = state.altitude_set and state.hover_rpm > 0
    if input.current_elevation_rpm ~= nil and not recalled then
      state.hover_rpm = math.abs(input.current_elevation_rpm)
    end
    if not state.altitude_set and ship ~= nil and ship.y ~= nil then
      state.altitude = ship.y
      state.altitude_set = true
      if state.job == nil then
        state.job = "altitude"
      end
    end
    if state.hover_rpm > 0 then
      state.elevation_equilibrium = state.hover_rpm
    elseif cfg.hover_equilibrium ~= nil then
      state.elevation_equilibrium = cfg.hover_equilibrium
    end
    state.seeded = true
  end
  local mode_command = nil
  for i = 1, #commands do
    if commands[i].type == "set_mode" then
      mode_command = commands[i]
    end
  end
  if mode_command ~= nil
      and not state.emergency
      and not state.diagnostic
      and state.mode == mode_command.mode
      and not state.altitude_set
      and state.job ~= "altitude"
      and ship ~= nil
      and ship.y ~= nil then
    state.altitude = ship.y
    state.pid_integral = 0
  end
  if state.emergency or state.outputs_disabled then
    state.modeled_su = 0
    return state, clamp_outputs(mix.zero()), status_of(state, input.ship, input.su, nil)
  end
  if input.ready == false then
    state.modeled_su = 0
    local status = status_of(state, ship, input.su, nil)
    status.mode = "blocked"
    return state, clamp_outputs(mix.zero()), status
  end
  local forward_speed = ship.vx
  local side_speed = ship.vz
  if ship.forward_speed ~= nil then
    forward_speed = ship.forward_speed
  end
  if ship.side_speed ~= nil then
    side_speed = ship.side_speed
  end
  if state.diagnostic then
    local hover_opt = nil
    if state.hover_diag then
      hover_opt = { enabled = true, rpm = state.diag_elevation }
    end
    local outputs = diagnostic.apply(state.diag_selection, hover_opt)
    return state, clamp_outputs(outputs), status_of(state, input.ship, input.su, nil)
  end
  if input.stick_fresh ~= true then
    state.stick = { x = 0, y = 0, z = 0 }
  end

  local outputs = mix.zero()
  local horiz = math.sqrt(ship.vx * ship.vx + ship.vz * ship.vz)
  if not state.speed_seeded then
    state.last_horiz = horiz
    state.speed_seeded = true
  elseif ship.dt > 0 then
    local delta = horiz - state.last_horiz
    if delta > 0 then
      local sample = delta / ship.dt
      if state.measured_accel == nil or sample > state.measured_accel then
        state.measured_accel = sample
      end
    end
    state.last_horiz = horiz
  end

  local vx, vy, vz = 0, 0, 0
  local vertical = "hold"
  local ref = 3
  if state.cancel then
    state.mode = "semi"
    state.job = nil
    state.altitude_set = false
    state.phase = "hold"
    state.waypoint_x = nil
    state.waypoint_z = nil
    state.target_speed = 0
    state.ramp_speed = 0
    state.ramp_rate = 0
    state.pid_integral = 0
    state.brake_x = nil
    state.brake_z = nil
    state.brake_elev = nil
    state.cancel = false
  end

  local manual_fly = state.mode == "manual" and (state.stick.x ~= 0 or state.stick.y ~= 0 or state.stick.z ~= 0)
  if state.job == "hover" and not manual_fly then
    vertical = "hold"
  elseif state.job == "altitude" and not manual_fly and state.mode ~= "semi" then
    vertical = "hold"
  elseif manual_fly or state.mode == "manual" then
    vx, vy, vz = manual.velocity(state.stick.x, state.stick.y, state.stick.z)
    if state.stick.x ~= 0 then
      state.brake_x = nil
      state.x_rpm = manual.x_rpm(state.x_rpm, forward_speed, vx, cfg.hover_step)
      -- A single step must not carry the hull past the stick's speed.
      local dt = ship.dt or 0.05
      if dt < 0.001 then
        dt = 0.001
      end
      local room = (vx - forward_speed) / dt
      local limit_rpm = control.prop_rpm(room, cfg.hover_equilibrium) * pid.thrust_scale(ship.y)
      if room >= 0 and state.x_rpm > limit_rpm then
        state.x_rpm = limit_rpm
      elseif room < 0 and state.x_rpm < limit_rpm then
        state.x_rpm = limit_rpm
      end
    end
    if state.stick.z > 0 then
      state.brake_elev = nil
      local lift = cfg.hover_equilibrium or 430
      if state.hover_rpm < lift then
        state.hover_rpm = lift
      end
      state.hover_rpm = manual.x_rpm(state.hover_rpm, ship.vy, vz, cfg.hover_step, true)
      if state.hover_rpm < lift then
        state.hover_rpm = lift + cfg.hover_step
      end
    elseif state.stick.z < 0 then
      state.brake_elev = nil
      state.hover_rpm = manual.x_rpm(state.hover_rpm, ship.vy, vz, cfg.hover_step, true)
    end
    vertical = "hold"
    ref = 3
  elseif state.mode == "semi" then
    state.target_speed = speed.cap(state.target_speed or 0, 35)
    state.ramp_speed = speed.cap(state.ramp_speed or 0, 35)
    state.ramp_speed = speed.apply_ramp(state.ramp_speed, state.target_speed, state.ramp_rate or 0, ship.dt)
    state.ramp_speed = speed.cap(state.ramp_speed, 35)
    vx = state.ramp_speed
    ref = 35
    vertical = "hold"
  elseif state.mode == "auto" and state.waypoint_x ~= nil and state.waypoint_z ~= nil then
    local dx = state.waypoint_x - ship.x
    local dz = state.waypoint_z - ship.z
    local dist = math.sqrt(dx * dx + dz * dz)
    if dist > 0.5 then
      state.bearing = numeric.atan2(-dz, dx)
      state.bearing_set = true
    end
    local limit = cfg.forward_accel or 1
    local stepped = auto.step({
      phase = state.phase,
      y = ship.y,
      dist = dist,
      speed = horiz,
      accel = math.min(state.measured_accel or limit, limit),
      profile = state.profile,
    })
    state.phase = stepped.phase
    if dist > 0 and not stepped.reverse and ship.forward ~= nil then
      local desired = math.min(stepped.horiz_speed, math.sqrt(math.max(0, 2 * limit * math.max(dist - 5, 0))))
      local yaw_err = wrap((state.bearing or 0) - (ship.heading or 0))
      vx, vy = frame.project(ship, dx / dist * desired, dz / dist * desired)
      -- Hold the forward prop while the nose is off the line. Side thrust
      -- still slides the hull toward the waypoint.
      if math.abs(yaw_err) > 0.3 then
        vx = 0
      end
    elseif stepped.reverse and ship.forward_speed == nil then
      -- The older speed-as-RPM path brakes by commanding the reverse of the
      -- measured speed. A velocity controller brakes by aiming at zero.
      vx = -horiz
    elseif not stepped.reverse then
      vx = stepped.horiz_speed
    end
    vertical = stepped.vertical
    ref = 50
    if state.profile == "cruise" then
      ref = 7
    end
  end

  if state.hover_rpm == 0 and (vertical == "descend" or vertical == "reverse") then
    state.hover_rpm = cfg.climb_rpm * 0.25
  end
  -- The 100000 N curve in the RPM helpers is a control gain, not Clockwork
  -- thrust. Keep it on the tuned mass. The learned hover RPM carries the
  -- heavy-hull scale instead.
  local mass = cfg.ship_mass
  state.lift_jump = false
  if type(input.ship_mass) == "number" and input.ship_mass > 0 then
    state.ship_mass = input.ship_mass
    calibrate_lift(state, ship, cfg, os.clock())
  end
  local function prop_equilibrium()
    local base = cfg.hover_equilibrium or 430
    if state.pid_gains ~= nil and type(state.pid_gains.equilibrium) == "number"
        and state.pid_gains.equilibrium > 0 then
      return state.pid_gains.equilibrium
    end
    return base
  end
  local target_y = state.altitude
  if state.job == nil and state.mode == "auto" and not state.altitude_set
      and state.waypoint_x ~= nil and state.waypoint_z ~= nil then
    if vertical == "descend" or state.phase == "hold" then
      target_y = 329
    else
      target_y = 400
    end
  end
  local function rest_elevation()
    if state.pid_gains == nil then
      state.pid_gains = pid.calibrate(cfg.hover_equilibrium, 0.05)
    end
    return pid.command(state.pid_gains, 0, ship.y, ship.y, 0, ship.dt or 0.05)
  end
  local stick_vertical = manual_fly and state.stick.z ~= 0
  local stop_x = state.job == "hover" or (state.mode == "manual" and state.stick.x == 0)
  local stop_z = state.job == "hover" or (state.mode == "manual" and state.stick.y == 0)
  local stop_y = (not stick_vertical) and (state.job == "hover" or (state.job ~= "altitude" and state.mode == "manual" and state.stick.z == 0))
  local x_hold, z_hold, y_hold = 0, 0, rest_elevation()
  if stop_x then
    x_hold, state.brake_x = jobs.hold_stop(state.brake_x, forward_speed, mass, 0, false)
  else
    state.brake_x = nil
  end
  if stop_z then
    z_hold, state.brake_z = jobs.hold_stop(state.brake_z, side_speed, mass, 0, false)
  else
    state.brake_z = nil
  end
  local elev_reverse = false
  if stop_y then
    y_hold, state.brake_elev, elev_reverse = jobs.hold_stop(state.brake_elev, ship.vy, mass, rest_elevation(), true)
    if math.abs(ship.vy) >= 0.05 then
      y_hold = config.clamp_rpm(y_hold * pid.thrust_scale(ship.y))
    elseif elev_reverse ~= true and y_hold < rest_elevation() then
      y_hold = rest_elevation()
    end
    local intended = accel_from_rpm(y_hold, state.pid_gains.equilibrium, ship.y)
    learn_elev_scale(state, ship, input.current_elevation_rpm)
    if state.elev_scale ~= nil and math.abs(state.elev_scale - 1) > 1e-6 then
      y_hold = config.clamp_rpm(y_hold / state.elev_scale)
    end
    y_hold = clamp_to_anchor(state, ship, y_hold, intended)
    -- The runtime holds whatever integer we send for the whole window. A
    -- captured full brake then reverses the ship and the next swing is larger.
    -- Follow the shaft, and only ask for the acceleration that zeros this
    -- speed inside that window. A pinned read never moves, so the tests that
    -- apply the command themselves keep the captured brake.
    local shaft = input.current_elevation_rpm
    if shaft ~= nil and state.elev_shaft ~= nil and math.abs(shaft - state.elev_shaft) > 1 then
      state.elev_shaft_live = true
    end
    if shaft ~= nil then
      state.elev_shaft = shaft
    end
    if state.elev_shaft_live and elev_reverse ~= true and math.abs(ship.vy) >= 0.05
        and shaft ~= nil and shaft > 0 then
      local scale = device_scale(state.elev_scale)
      -- Recompute every tick. A captured brake stays at the opening cut after
      -- the speed is already gone, and the hold then builds the opposite swing.
      local accel = -ship.vy / HOLD_WINDOW
      if accel > ACCEL_CAP then
        accel = ACCEL_CAP
      elseif accel < -ACCEL_CAP then
        accel = -ACCEL_CAP
      end
      local soft = rpm_for_accel(accel, state.pid_gains.equilibrium, ship.y) / scale
      if soft < 1 then
        soft = 1
      end
      y_hold = config.clamp_rpm(soft)
      intended = accel
      elev_reverse = false
      state.brake_elev = nil
    end
    state.elev_cmd = y_hold
    if state.brake_elev == nil and math.abs(ship.vy) < 0.05 then
      state.hover_rpm = y_hold
    end
  else
    state.brake_elev = nil
  end
  if state.brake_x ~= nil then
    local distance = jobs.stopping_distance(forward_speed, state.brake_x.rpm, mass)
    if distance > state.stop_distance and distance < math.huge then
      state.stop_distance = distance
    end
  end
  if state.pid_gains == nil then
    state.pid_gains = pid.calibrate(cfg.hover_equilibrium, 0.05)
  end
  local track_altitude = (not stop_y) and (not stick_vertical) and (
    state.job == "altitude" or (state.mode == "semi" and state.altitude_set)
  )
  if track_altitude then
    learn_elev_scale(state, ship, input.current_elevation_rpm)
    local integral_before = state.pid_integral
    local rpm, integral, rev = pid.command(
      state.pid_gains,
      state.pid_integral,
      ship.y,
      target_y,
      ship.vy,
      ship.dt
    )
    state.pid_integral = integral
    local raw_err = target_y - ship.y
    local max_err = state.pid_gains.max_rate * state.pid_gains.kd / state.pid_gains.kp
    if max_err > 0 then
      local clamped = raw_err
      if clamped > max_err then
        clamped = max_err
      elseif clamped < -max_err then
        clamped = -max_err
      end
      local excess = raw_err - clamped
      if excess ~= 0 then
        local reach = math.abs(excess) / (math.abs(excess) + max_err)
        local nudge = state.pid_gains.equilibrium * pid.thrust_scale(ship.y) * reach
        if excess < 0 then
          nudge = -nudge
        end
        if rev then
          rpm = rpm - nudge
        else
          rpm = rpm + nudge
        end
        if rpm < 0 then
          rpm = 0
        end
        rpm = config.clamp_rpm(rpm)
      end
    end
    local raw_vy = ship.vy or 0
    local intended_accel = 0
    local anchor_trim = false
    local governed = false
    if math.abs(raw_err) > 1e-9 or math.abs(raw_vy) > 1e-9 then
      -- A wound-up integral keeps commanding a climb after arrival, and the
      -- speed hold freezes it. Use it only for the last blocks, once the
      -- rate is already small.
      local basis = rpm
      local close = math.abs(raw_err) <= HOLD_ROOM and math.abs(raw_vy) < 0.5
      if not close then
        basis = pid.command(state.pid_gains, 0, ship.y, target_y, raw_vy, ship.dt)
        state.pid_integral = 0
      end
      local requested = accel_from_rpm(basis, state.pid_gains.equilibrium, ship.y)
      local sign = 0
      if raw_vy > 0.05 then
        sign = 1
      elseif raw_vy < -0.05 then
        sign = -1
      end
      if sign ~= 0 and state.approach_sign ~= nil and sign ~= state.approach_sign then
        state.approach_cap = state.approach_peak
        state.approach_peak = math.abs(raw_vy)
      end
      if sign ~= 0 then
        state.approach_sign = sign
        if math.abs(raw_vy) > (state.approach_peak or 0) then
          state.approach_peak = math.abs(raw_vy)
        end
      end
      if close and state.elev_scale ~= nil then
        -- The held integer is the command from the end of the previous window.
        -- Once the hull equilibrium is known, derivative tracking reverses
        -- vertical speed across that delay. Proportional acceleration while
        -- the ship is already moving toward the setpoint is frozen for that
        -- same window and pumps the next swing. Coast on the anchor instead,
        -- and spend an away-from-setpoint window removing the speed already
        -- there. A near-stop still uses the position term so the last blocks close.
        local integral = state.pid_integral or 0
        if raw_err * raw_vy > 0 and math.abs(raw_vy) > 0.1 then
          requested = 0
          anchor_trim = true
          state.pid_integral = integral_before
        elseif raw_err * raw_vy < 0 and math.abs(raw_vy) > 0.05 then
          requested = -raw_vy / HOLD_WINDOW
          anchor_trim = true
          state.pid_integral = integral_before
        else
          requested = state.pid_gains.kp * raw_err + state.pid_gains.ki * integral
        end
      end
      -- The shaft, not the last request, is what is holding the ship. The
      -- runtime holds one integer for the whole window, and a stop planned
      -- from the request falls through. A read that never moves is not the
      -- shaft; tests pin it.
      local shaft = input.current_elevation_rpm
      if shaft ~= nil and state.descent_shaft ~= nil and math.abs(shaft - state.descent_shaft) > 1 then
        state.descent_shaft_live = true
      end
      if shaft ~= nil then
        state.descent_shaft = shaft
      end
      local held = state.hover_rpm
      if state.descent_shaft_live and shaft ~= nil and shaft > 0 then
        held = shaft
      end
      if held == nil or held <= 0 then
        held = shaft
      end
      local scale = device_scale(state.elev_scale)
      -- Only while already descending. A climb that is still going up must be
      -- allowed to cut RPM even when the target is now below the ship.
      local gap_left = ship.y - target_y
      local settling = gap_left < 24 and raw_vy > -2
      if not settling and ship.y > target_y + HOLD_ROOM and raw_vy < -0.05 and held ~= nil and held > 0 then
        local desired = rpm_for_accel(requested, state.pid_gains.equilibrium, ship.y) / scale
        local function choice_ok(rpm_choice)
          return rpm_choice > 0 and descent_step_stops(
            ship.y, raw_vy, target_y, rpm_choice, state.pid_gains.equilibrium, scale
          )
        end
        -- Use the whole requested RPM when it still stops. When a cut is too
        -- deep, use the lowest RPM that stops instead of walking by 99.
        local choice = desired
        if held ~= nil and held > 0 and not choice_ok(desired) and choice_ok(held) then
          local low = math.min(math.max(desired, 0), held)
          local high = math.max(desired, held)
          choice = high
          for _ = 1, 16 do
            local mid = (low + high) / 2
            if choice_ok(mid) then
              choice = mid
              high = mid
            else
              low = mid
            end
          end
        elseif desired <= 0 or not choice_ok(desired) then
          if held ~= nil and choice_ok(held) then
            choice = held
          elseif desired > 0 then
            choice = desired
          end
        end
        rpm = config.clamp_rpm(choice)
        intended_accel = device_accel(rpm, state.pid_gains.equilibrium, ship.y, scale)
        governed = true
      end
      if not governed then
        local safe = hold_safe_accel(ship.y, raw_vy, target_y, requested, state.approach_cap)
        intended_accel = safe
        rpm = rpm_for_accel(safe, state.pid_gains.equilibrium, ship.y)
      end
      rev = false
    end
    if not governed and state.elev_scale ~= nil and math.abs(state.elev_scale - 1) > 1e-6 then
      rpm = config.clamp_rpm(rpm / state.elev_scale)
    end
    if anchor_trim and math.abs(intended_accel) <= 0.5 then
      -- A small acceleration divided by the learned scale falls inside the
      -- anchor tolerance and never reaches the hull. Realize it on the RPM
      -- that is actually holding the ship.
      local anchored = anchor_here(state, ship)
      if anchored ~= nil then
        rpm = rpm_vs_anchor(anchored, intended_accel)
      end
    end
    -- A short hop freezes one integer for the hold. The density curve sits
    -- above this hull, so that integer climbs when the hop is a descent.
    -- The RPM already holding the ship is the equilibrium for this approach.
    -- The live hull is near 1/1.85 and 1/2.2 of the density hover, so the
    -- resting RPM has to count even when it is that far below the curve.
    local gap = target_y - ship.y
    local flown = input.current_elevation_rpm
    if state.altitude_adopted
        and state.elev_anchor == nil and flown ~= nil and flown > 0
        and math.abs(gap) > 1 and math.abs(gap) <= 16
        and math.abs(ship.vy or 0) < 0.1 then
      local model_hover = state.pid_gains.equilibrium * pid.thrust_scale(ship.y)
      if model_hover > 0 and flown > model_hover / 2.5 and flown < model_hover * 1.25 then
        state.elev_anchor = flown
        state.elev_anchor_y = ship.y
      end
    end
    rpm = clamp_to_anchor(state, ship, rpm, intended_accel)
    state.elev_cmd = rpm
    state.hover_rpm = rpm
    if rev then
      elev_reverse = true
    end
  elseif not stop_y then
    -- Idle never rewrote the command, so a trim from another height survived
    -- until the next release and divided that release. Sample the hold that
    -- is actually flying; leave the commanded RPM where it is.
    if input.current_elevation_rpm ~= nil and state.hover_rpm ~= nil
        and state.hover_rpm > 0
        and math.abs(input.current_elevation_rpm - state.hover_rpm) <= 1 then
      state.elev_cmd = state.hover_rpm
    end
    learn_elev_scale(state, ship, input.current_elevation_rpm)
  end

  local rsc17, relay2 = mix.x(vx, ref)
  if stop_x then
    rsc17 = x_hold
  elseif not stop_x and state.mode == "semi" then
    local feed = 0
    if state.ramp_speed ~= state.target_speed then
      feed = state.ramp_rate or 0
    end
    -- The ramp rate must not keep thrusting after the hull is already at the cap.
    if (forward_speed or 0) >= 35 and feed > 0 then
      feed = 0
    elseif (forward_speed or 0) <= -35 and feed < 0 then
      feed = 0
    end
    local accel = control.accel(
      vx,
      forward_speed,
      ship.dt,
      cfg.forward_accel or (50 / 15),
      cfg.velocity_response or 1,
      feed
    )
    local eq = prop_equilibrium()
    -- Positive RPM on the rear thrusters pushes the ship forward.
    rsc17 = control.prop_rpm(accel, eq) * pid.thrust_scale(ship.y)
    relay2 = speed.relay2_level(rsc17, eq)
  end
  rsc17 = config.clamp_rpm(rsc17)
  outputs.rsc.rsc17 = rsc17
  outputs.relays.relay2 = relay2
  local rsc16, _ = mix.elevation(vertical, state.hover_rpm, cfg.climb_rpm)
  if stop_y then
    rsc16 = y_hold
  end
  outputs.rsc.rsc16 = rsc16
  outputs.relays.relay6 = false

  -- A fresh stick to the side is a pull toward that side, not the old
  -- velocity hold. Positive stick y pulls starboard.
  local lateral = 0
  if state.stick.y ~= 0 then
    lateral = state.stick.y
  end
  local rsc13, rsc14, rsc15, rsc12 = mix.sides(lateral, 0, cfg.side_gain)
  outputs.rsc.rsc13 = rsc13
  outputs.rsc.rsc14 = rsc14
  outputs.rsc.rsc15 = rsc15
  outputs.rsc.rsc12 = rsc12
  local kind, which = outage.classify(ship.pitch_rate, ship.roll_rate, cfg.outage_threshold)
  local outage_name = nil
  if kind == "corner" then
    outage_name = which
    state.balance_time = 0
    local cuts = outage.cutoffs(kind, which)
    for name, on in pairs(cuts) do
      outputs.relays[name] = on
    end
  elseif kind == "side" then
    outage_name = which
    state.balance_time = 0
    local cuts = outage.fall_cutoffs()
    for name, on in pairs(cuts) do
      outputs.relays[name] = on
    end
    outputs.rsc.rsc16 = 0
  else
    state.balance_time = 0
  end
  if stop_z then
    apply_side_brake(outputs, z_hold)
  end
  -- Bearing 0 is the boot value. Yaw only after an explicit bearing command,
  -- otherwise a restart slews the ship onto heading 0 at the stress limit.
  if not state.bearing_set and ship ~= nil and type(ship.heading) == "number" then
    state.bearing = ship.heading
  end
  if not (state.mode == "manual" and state.stick.y ~= 0) then
    local yaw_err = wrap((state.bearing or 0) - (ship.heading or 0))
    local spin = manual.yaw_rpm(yaw_err, ship.yaw_rate, mass, cfg.yaw_damping)
    local base_eq = cfg.hover_equilibrium or 430
    if spin ~= 0 and base_eq > 0 then
      local prop_scale = prop_equilibrium() / base_eq
      if prop_scale > 1 then
        spin = spin * prop_scale
      end
    end
    if spin ~= 0 then
      local y13, y14, y15, y12 = mix.sides(0, spin, 1)
      outputs.rsc.rsc13 = mix.add_rpm(outputs.rsc.rsc13, y13)
      outputs.rsc.rsc14 = mix.add_rpm(outputs.rsc.rsc14, y14)
      outputs.rsc.rsc15 = mix.add_rpm(outputs.rsc.rsc15, y15)
      outputs.rsc.rsc12 = mix.add_rpm(outputs.rsc.rsc12, y12)
    end
  end
  apply_side_signs(outputs, cfg)
  cap_side_rpm(outputs)
  outputs.rsc.rsc16 = cap_rpm(outputs.rsc.rsc16, ELEVATION_RPM_CAP)
  -- A failed corner is handled by cutoffs. Reversing the surviving props
  -- would turn the remaining upward lift into additional downward force.
  outputs.relays.relay6 = elev_reverse == true
  stress.limit_manual(outputs, input.su, input.su_capacity, state.modeled_su)
  state.modeled_su = stress.consumed(outputs)

  return state, clamp_outputs(outputs), status_of(state, ship, input.su, outage_name)
end

return M
