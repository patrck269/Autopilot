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
