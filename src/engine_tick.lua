local manual = require("manual")
local speed = require("speed")
local hover = require("hover")
local auto = require("auto")
local outage = require("outage")
local mix = require("mix")
local diagnostic = require("diagnostic")
local jobs = require("jobs")

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
    x_rpm = 0,
    seeded = false,
    altitude_set = false,
    job = nil,
    cancel = false,
    rpm_memory = {},
    elevation_equilibrium = nil,
    stop_distance = 0,
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
    su_remaining = state.su_remaining,
    stop_distance = state.stop_distance,
    job = state.job,
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
    if command.x ~= 0 or command.y ~= 0 or command.z ~= 0 then
      state.job = nil
      state.cancel = false
    end
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
    state.altitude_set = true
    state.job = "altitude"
    state.phase = "hold"
    state.waypoint_x = nil
    state.waypoint_z = nil
    state.target_speed = 0
    local known = hover.recall(state.rpm_memory, command.y)
    if known ~= nil then
      state.hover_rpm = known
    end
    return
  end
  if command.type == "cancel_jobs" then
    state.cancel = true
    state.job = "hover"
    state.phase = "hold"
    state.target_speed = 0
    state.waypoint_x = nil
    state.waypoint_z = nil
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
    state.job = nil
    return
  end
  if command.type == "set_profile" then
    state.profile = command.profile
  end
end

function M.tick(state, input)
  local cfg = input.config
  apply_command(state, input.command)
  local ship = input.ship
  if not state.seeded then
    local recalled = state.altitude_set and state.hover_rpm > 0
    if input.current_elevation_rpm ~= nil and not recalled then
      state.hover_rpm = math.abs(input.current_elevation_rpm)
    end
    if not state.altitude_set and ship ~= nil and ship.y ~= nil then
      state.altitude = ship.y
    end
    if state.hover_rpm > 0 then
      state.elevation_equilibrium = state.hover_rpm
    elseif cfg.hover_equilibrium ~= nil then
      state.elevation_equilibrium = cfg.hover_equilibrium
    end
    state.seeded = true
  end
  if input.ready == false then
    state.mode = "blocked"
    local held = mix.zero()
    held.rsc.rsc11 = state.hover_rpm
    return state, held, status_of(state, ship, input.su, nil)
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
  local ref = 3
  if state.cancel then
    state.mode = "semi"
    state.job = "hover"
    state.phase = "hold"
    state.altitude = ship.y
    state.bearing = ship.heading
    state.waypoint_x = nil
    state.waypoint_z = nil
    state.target_speed = 0
    state.cancel = false
  end

  local manual_fly = state.mode == "manual" and (state.stick.x ~= 0 or state.stick.y ~= 0 or state.stick.z ~= 0)
  if state.job == "hover" then
    state.stop_distance = jobs.stop_distance(horiz)
    if math.abs(ship.vx) > 0.05 then
      vx = -ship.vx
    end
    if math.abs(ship.vz) > 0.05 then
      vz = -ship.vz
    end
    vertical = "hold"
  elseif state.job == "altitude" then
    vertical = "hold"
  elseif manual_fly or state.mode == "manual" then
    vx, vy, vz = manual.velocity(state.stick.x, state.stick.y, state.stick.z)
    if state.stick.x == 0 then
      vx = manual.release_effort(ship.vx) * 3
    end
    state.x_rpm = manual.x_rpm(state.x_rpm, ship.vx, vx, cfg.hover_step)
    local target_vy = 0
    if state.stick.z ~= 0 then
      target_vy = vz
    else
      target_vy = manual.release_effort(ship.vy) * 3
    end
    state.hover_rpm = manual.x_rpm(state.hover_rpm, ship.vy, target_vy, cfg.hover_step, true)
    vertical = "hold"
    ref = 3
  elseif state.mode == "semi" then
    state.ramp_speed = speed.apply_ramp(state.ramp_speed, state.target_speed, state.ramp_rate, ship.dt)
    vx = speed.cap(state.ramp_speed, 35)
    ref = 35
    vertical = "hold"
  elseif state.mode == "auto" and state.waypoint_x ~= nil and state.waypoint_z ~= nil then
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
    ref = 50
    if state.profile == "cruise" then
      ref = 7
    end
  end

  if state.hover_rpm == 0 and (vertical == "descend" or vertical == "reverse") then
    state.hover_rpm = cfg.climb_rpm * 0.25
  end
  local target_y = state.altitude
  if state.job == nil and state.mode == "auto" then
    if vertical == "descend" then
      target_y = 329
    else
      target_y = 400
    end
  end
  if state.mode ~= "manual" or state.job == "hover" or state.job == "altitude" then
    if ship.y > target_y + cfg.altitude_deadzone then
      local equilibrium = state.elevation_equilibrium
      if equilibrium == nil or equilibrium <= 0 then
        equilibrium = cfg.hover_equilibrium
      end
      state.hover_rpm = hover.descend_rpm(
        state.hover_rpm,
        ship.vy,
        ship.y,
        target_y,
        cfg.altitude_deadzone,
        ship.dt,
        equilibrium
      )
    elseif vertical == "climb" or vertical == "hold" or vertical == "descend" then
      state.hover_rpm = hover.seek(
        state.hover_rpm,
        ship.vy,
        ship.y,
        target_y,
        cfg.hover_gain,
        cfg.hover_step,
        cfg.altitude_deadzone,
        cfg.altitude_approach,
        cfg.hover_gain_near,
        cfg.hover_step_near
      )
    end
  end

  local rsc10, relay2 = mix.x(vx, ref)
  if state.mode == "manual" then
    rsc10 = state.x_rpm
  end
  outputs.rsc.rsc10 = rsc10
  outputs.relays.relay2 = relay2
  local rsc11, _ = mix.elevation(vertical, state.hover_rpm, cfg.climb_rpm)
  outputs.rsc.rsc11 = rsc11
  outputs.relays.relay6 = false

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
  if state.mode == "manual" and state.stick.y ~= 0 then
    local side_rpm = manual.rcs_rpm(math.abs(state.stick.y), cfg.ship_mass)
    rsc6, rsc7, rsc8, rsc9 = 0, 0, 0, 0
    if state.stick.y > 0 then
      rsc6 = side_rpm
      rsc8 = side_rpm
    else
      rsc7 = side_rpm
      rsc9 = side_rpm
    end
  end
  outputs.rsc.rsc6 = rsc6
  outputs.rsc.rsc7 = rsc7
  outputs.rsc.rsc8 = rsc8
  outputs.rsc.rsc9 = rsc9
  if math.abs(ship.vy) < 0.05 and math.abs(ship.y - target_y) <= cfg.altitude_deadzone and state.hover_rpm > 0 then
    hover.remember(state.rpm_memory, ship.y, state.hover_rpm)
    state.elevation_equilibrium = state.hover_rpm
  end

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
    if state.mode == "manual" and state.stick.z ~= 0 then
      local vert_rpm = manual.rcs_rpm(math.abs(state.stick.z), cfg.ship_mass)
      if state.stick.z < 0 then
        vert_rpm = -vert_rpm
      end
      outputs.rsc.rsc2 = vert_rpm
      outputs.rsc.rsc3 = vert_rpm
      outputs.rsc.rsc4 = vert_rpm
      outputs.rsc.rsc5 = vert_rpm
    end
  end
  outputs.relays.relay6 = hover.use_reverser(kind == "corner" or kind == "side")

  return state, outputs, status_of(state, ship, input.su, outage_name)
end

return M
