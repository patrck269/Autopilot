local numeric = require("numeric")

local M = {}

local MAX_RPM = 32769

function M.clamp_rpm(rpm)
  if not numeric.finite(rpm) then
    return 0
  end
  if rpm > MAX_RPM then
    return MAX_RPM
  end
  if rpm < -MAX_RPM then
    return -MAX_RPM
  end
  return rpm
end

function M.default()
  return {
    max_rpm = MAX_RPM,
    stick_timeout = 0.35,
    velocity_response = 1,
    forward_accel = 50 / 15,
    side_accel = 0.5,
    yaw_damping = 2,
    frame = { forward = { x = 1, y = 0, z = 0 }, right = { x = 0, y = 0, z = -1 }, up = { x = 0, y = 1, z = 0 } },
    climb_rpm = 256,
    climb_rate = 4,
    altitude_deadzone = 8,
    altitude_approach = 20,
    hover_step = 10,
    hover_gain_near = 0.2,
    hover_step_near = 1,
    outage_threshold = 0.2,
    outage_fail_seconds = 5,
    hover_gain = 2,
    hover_equilibrium = 430,
    ship_mass = 200000000,
    side_gain = 10,
    -- +1 keeps the mixer sign. -1 flips that propeller after a measured pulse.
    side_sign = {
      rsc12 = 1,
      rsc13 = 1,
      rsc14 = 1,
      rsc15 = 1,
    },
    names = {
      rsc12 = "Create_RotationSpeedController_12",
      rsc13 = "Create_RotationSpeedController_13",
      rsc14 = "Create_RotationSpeedController_14",
      rsc15 = "Create_RotationSpeedController_15",
      rsc16 = "Create_RotationSpeedController_16",
      rsc17 = "Create_RotationSpeedController_17",
      speedometer = "Create_Speedometer_1",
      stressometer = "Create_Stressometer_2",
      wired_modem = "back",
      ender_modem = "wireless",
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
