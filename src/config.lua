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
      relay2 = "redstone_relay_2",
      relay3 = "redstone_relay_3",
      relay5 = "redstone_relay_5",
      relay6 = "redstone_relay_6",
      relay7 = "redstone_relay_7",
      relay8 = "redstone_relay_8",
      relay9 = "redstone_relay_9",
      relay10 = "redstone_relay_10",
      rsc2 = "Create_RotationSpeedController_2",
      rsc3 = "Create_RotationSpeedController_3",
      rsc4 = "Create_RotationSpeedController_4",
      rsc5 = "Create_RotationSpeedController_5",
      rsc6 = "Create_RotationSpeedController_6",
      rsc7 = "Create_RotationSpeedController_7",
      rsc8 = "Create_RotationSpeedController_8",
      rsc9 = "Create_RotationSpeedController_9",
      rsc10 = "Create_RotationSpeedController_10",
      rsc11 = "Create_RotationSpeedController_11",
      speedometer = "Create_Speedometer_0",
      stressometer = "Create_Stressometer_0",
      wired_modem = "back",
      ender_modem = "right",
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
