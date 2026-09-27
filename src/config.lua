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
