local config = require("config")
local manual = require("manual")
local speed = require("speed")
local hover = require("hover")
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
local protocol = require("protocol")

local M = {}

local wrap = numeric.wrap

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
    forward_integral = 0,
  }
end

local function clamp_outputs(outputs)
  for name, rpm in pairs(outputs.rsc) do
    outputs.rsc[name] = config.clamp_rpm(rpm)
  end
  return outputs
end

local function apply_side_brake(outputs, rpm)
  outputs.rsc.rsc6 = 0
  outputs.rsc.rsc7 = 0
  outputs.rsc.rsc8 = 0
  outputs.rsc.rsc9 = 0
  if rpm > 0 then
    outputs.rsc.rsc6 = rpm
    outputs.rsc.rsc8 = rpm
  elseif rpm < 0 then
    outputs.rsc.rsc7 = -rpm
    outputs.rsc.rsc9 = -rpm
  end
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
    emergency = state.emergency,
    phase = state.phase,
    hover_rpm = state.hover_rpm,
    diag_elevation = state.diag_elevation,
  }
end

local function apply_command(state, command, ship, current_rpm)
  if command == nil then
    return
  end
  if command.type == "emergency" then
    state.emergency = true
    state.stick = {x=0,y=0,z=0}
    if state.mode == "diagnostic" then
      state.mode = "idle"
    end
    state.diagnostic = false
    state.hover_diag = false
    state.diag_selection = nil
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
    state.outputs_disabled = false
    if command.hover and not state.hover_diag then state.diag_elevation = math.abs(current_rpm or state.hover_rpm or 0) end
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
    state.outputs_disabled = true
    state.hover_rpm, state.x_rpm, state.pid_integral = 0,0,0
    state.job, state.waypoint_x, state.waypoint_z = nil,nil,nil
    state.altitude_set = false
    state.target_speed,state.ramp_speed = 0,0
    state.stick = {x=0,y=0,z=0}
    return
  end
  if command.type == "diagnostic_set" then
    if state.diagnostic then state.diag_selection = command end
    return
  end
  if command.type == "diagnostic_elevation" then
    if state.diagnostic and state.hover_diag then state.diag_elevation = command.rpm end
    return
  end
  if state.diagnostic then
    return
  end
  state.outputs_disabled = false
  if command.type == "stick" then
    state.mode = "manual"
    state.stick = { x = command.x, y = command.y, z = command.z }
    if command.x ~= 0 or command.y ~= 0 or command.z ~= 0 then
      state.cancel = false
    end
    return
  end
  if command.type == "set_mode" then
    state.mode = command.mode
    if not state.altitude_set and state.job ~= "altitude" then state.altitude = ship.y; state.pid_integral = 0 end
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
    state.cancel = false
    state.altitude = command.y
    state.altitude_set = true
    state.job = "altitude"
    state.phase = "hold"
    state.brake_elev = nil
    state.waypoint_x = nil
    state.waypoint_z = nil
    state.target_speed = 0
    state.pid_integral = 0
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
    return
  end
  if command.type == "set_speed" then
    state.target_speed = speed.cap(command.speed, 35)
    state.ramp_rate = speed.ramp_rate(state.ramp_speed, state.target_speed)
    return
  end
  if command.type == "set_waypoint" or command.type == "return_to_user" then
    state.cancel = false
    state.waypoint_x = command.x
    state.waypoint_z = command.z
    state.mode = "auto"
    state.phase = "climb"
    state.job = nil
    state.altitude_set = false
    return
  end
  if command.type == "set_profile" then
    state.profile = command.profile
  end
end

function M.tick(state, input)
  local cfg = input.config
  local ship = input.ship
  local forward_speed = ship.forward_speed or ship.vx
  local side_speed = ship.side_speed or ship.vz
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
  for _,command in ipairs(input.commands or {}) do
    apply_command(state, protocol.validate(command), ship, input.current_elevation_rpm)
  end
  apply_command(state, protocol.validate(input.command), ship, input.current_elevation_rpm)
  if state.emergency or state.outputs_disabled then
    state.modeled_su = 0
    return state, clamp_outputs(mix.zero()), status_of(state, input.ship, input.su, nil)
  end
  if input.ready == false then
    local held = mix.zero()
    -- An incomplete rig cannot safely actuate flight or diagnostics.
    state.modeled_su = 0
    local status = status_of(state, ship, input.su, nil)
    status.mode = "blocked"
    return state, clamp_outputs(held), status
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
  local nav_active = false
  local feedforward = 0
  if state.cancel then
    state.mode = "idle"
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
    end
    if state.stick.z ~= 0 then
      state.brake_elev = nil
      local a = control.accel(vz, ship.vy, ship.dt, 3, 1)
      state.hover_rpm = config.clamp_rpm((cfg.hover_equilibrium or 430) * ((10+a)/10)^(1/1.2) * pid.thrust_scale(ship.y))
    end
    vertical = "hold"
    ref = 3
  elseif state.mode == "semi" then
    state.ramp_speed = speed.apply_ramp(state.ramp_speed, state.target_speed, state.ramp_rate, ship.dt)
    local available=math.sqrt(math.max(0,35^2-side_speed^2))
    vx = speed.cap(state.ramp_speed, available)
    if state.ramp_speed ~= state.target_speed then feedforward = state.ramp_rate end
    ref = 35
    vertical = "hold"
  elseif state.mode == "auto" and state.waypoint_x ~= nil and state.waypoint_z ~= nil then
    local dx = state.waypoint_x - ship.x
    local dz = state.waypoint_z - ship.z
    local dist = math.sqrt(dx * dx + dz * dz)
    nav_active = true
    if dist > 0.5 then state.bearing = numeric.atan2(-dz, dx) end
    local stepped = auto.step({
      phase = state.phase,
      y = ship.y,
      dist = dist,
      speed = horiz,
      accel = math.min(state.measured_accel or cfg.forward_accel, cfg.forward_accel),
      profile = state.profile,
    })
    state.phase = stepped.phase
    local desired = math.min(stepped.horiz_speed, math.sqrt(math.max(0,2*cfg.forward_accel*(dist-5))))
    if dist > 0 and not stepped.reverse then
      vx,vy = frame.project(ship,dx/dist*desired,dz/dist*desired)
      if math.abs(wrap(state.bearing-(ship.heading or 0)))>0.3 then vx=0 end
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
    x_hold, state.brake_x = jobs.hold_stop(state.brake_x, forward_speed, cfg.ship_mass, 0, false)
  else
    state.brake_x = nil
  end
  if stop_z then
    z_hold, state.brake_z = jobs.hold_stop(state.brake_z, side_speed, cfg.ship_mass, 0, false)
  else
    state.brake_z = nil
  end
  local elev_reverse = false
  if stop_y then
    y_hold, state.brake_elev, elev_reverse = jobs.hold_stop(state.brake_elev, ship.vy, cfg.ship_mass, rest_elevation(), true)
    if math.abs(ship.vy) >= 0.05 then
      y_hold = config.clamp_rpm(y_hold * pid.thrust_scale(ship.y))
    elseif elev_reverse ~= true and y_hold < rest_elevation() then
      y_hold = rest_elevation()
    end
    if state.brake_elev == nil and math.abs(ship.vy) < 0.05 then
      state.hover_rpm = y_hold
    end
  else
    state.brake_elev = nil
  end
  if state.brake_x ~= nil then
    local distance = jobs.stopping_distance(forward_speed, state.brake_x.rpm, cfg.ship_mass)
    if distance > state.stop_distance and distance < math.huge then
      state.stop_distance = distance
    end
  end
  if state.pid_gains == nil then
    state.pid_gains = pid.calibrate(cfg.hover_equilibrium, 0.05)
  end
  local track_altitude = (not stop_y) and (not stick_vertical) and (
    state.job == "altitude" or state.mode == "semi" or (state.mode == "auto" and not manual_fly)
  )
  if track_altitude then
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
    state.hover_rpm = rpm
    if rev then
      elev_reverse = true
    end
  end

  local rsc10 = 0
  if stop_x then
    rsc10 = x_hold * pid.thrust_scale(ship.y)
  elseif state.mode=="manual" or state.mode=="semi" or nav_active then
    local a=control.accel(vx,forward_speed,ship.dt,cfg.forward_accel,cfg.velocity_response,feedforward)
    rsc10=control.prop_rpm(a,cfg.hover_equilibrium)*pid.thrust_scale(ship.y)
  end
  state.x_rpm = rsc10
  rsc10 = config.clamp_rpm(rsc10)
  outputs.rsc.rsc10 = rsc10
  outputs.relays.relay2 = speed.relay2_level(rsc10, cfg.hover_equilibrium)
  local rsc11, _ = mix.elevation(vertical, state.hover_rpm, cfg.climb_rpm)
  if stop_y then
    rsc11 = y_hold
  end
  outputs.rsc.rsc11 = rsc11
  outputs.relays.relay6 = false

  local pitch_err = 0
  local roll_err = 0
  if horiz > 20 then
    pitch_err = ship.pitch
    roll_err = ship.roll
  end
  local lateral = 0
  if state.mode == "manual" and state.stick.y ~= 0 or nav_active or state.mode=="semi" then
    lateral = control.accel(vy, side_speed, ship.dt, cfg.side_accel, cfg.velocity_response)
  elseif stop_z then
    -- Reuse the bounded stopping force, converting from the propeller model.
    lateral = (z_hold < 0 and -1 or 1) * jobs.thrust(z_hold, cfg.ship_mass) / cfg.ship_mass
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
    state.balance_side = nil
    local u2, u3, u4, u5 = mix.ups(pitch_err, roll_err, lift, cfg.up_gain)
    outputs.rsc.rsc2 = u2
    outputs.rsc.rsc3 = u3
    outputs.rsc.rsc4 = u4
    outputs.rsc.rsc5 = u5
  end
  local yaw_err = wrap((state.bearing or 0) - (ship.heading or 0))
  local yaw = numeric.clamp(yaw_err/math.pi*0.5 - (ship.yaw_rate or 0)*cfg.yaw_damping, -0.5, 0.5)
  if math.abs(yaw_err)<0.02 and math.abs(ship.yaw_rate or 0)<0.01 then yaw = 0 end
  outputs.rsc.rsc6, outputs.rsc.rsc7, outputs.rsc.rsc8, outputs.rsc.rsc9 = control.sides(lateral, yaw, cfg.ship_mass)
  outputs.relays.relay6 = hover.use_reverser(elev_reverse)
  stress.limit_manual(outputs, input.su, input.su_capacity, state.modeled_su)
  state.modeled_su = stress.consumed(outputs)

  return state, clamp_outputs(outputs), status_of(state, ship, input.su, outage_name)
end

return M
