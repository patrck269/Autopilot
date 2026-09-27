local M = {}

function M.adjust(rpm, vertical_speed, gain)
  return rpm - gain * vertical_speed
end

return M
