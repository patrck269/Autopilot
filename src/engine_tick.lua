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

  if state.hover_rpm == 0 and (vertical == "descend" or vertical == "reverse") then
    state.hover_rpm = cfg.climb_rpm * 0.25
  end
  local target_y = state.altitude
  if state.mode == "auto" then
    if vertical == "descend" then
      target_y = 329
    else
      target_y = 400
    end
  end
  if vertical == "climb" or vertical == "hold" then
    state.hover_rpm = hover.seek(
      state.hover_rpm,
      ship.vy,
      ship.y,
      target_y,
      cfg.hover_gain,
      cfg.hover_step,
      cfg.climb_rate,
      cfg.altitude_deadzone
    )
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
