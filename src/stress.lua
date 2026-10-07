local M = {}

-- Create's network stress is impact * abs(RPM). The four elevation props are
-- clockwork bearings (impact 4) on rsc11. Each side output is one reversible
-- clockwork propeller on its own controller (impact 8).
M.CAPACITY = 479231
-- Leave room for shafts and the rest of the network. Sitting on the exact
-- capacity overstresses Create, the shaft speed falls to 0, and a vstuff
-- thruster then produces no force.
M.USABLE = 431308
M.RCS_IMPACT = 8
M.ELEVATION_IMPACT = 4
M.ELEVATION_PROPS = 4
-- The forward controller's propeller bearing. A cruise climb leaves it
-- running, so its SU has to come out of the same budget as the climb.
M.X_IMPACT = 4
M.X_PROPS = 1

local RCS = { "rsc6", "rsc7", "rsc8", "rsc9" }
local FORWARD = "rsc10"

local function elevation_su(rsc)
  return math.abs(rsc.rsc11 or 0) * M.ELEVATION_PROPS * M.ELEVATION_IMPACT
end

local function other_su(rsc)
  local su = math.abs(rsc[FORWARD] or 0) * M.X_IMPACT * M.X_PROPS
  for _, name in ipairs(RCS) do
    su = su + math.abs(rsc[name] or 0) * M.RCS_IMPACT
  end
  return su
end

local function scale_others(rsc, factor)
  rsc[FORWARD] = (rsc[FORWARD] or 0) * factor
  for _, name in ipairs(RCS) do
    rsc[name] = (rsc[name] or 0) * factor
  end
end

function M.consumed(outputs)
  local rsc = outputs.rsc or {}
  return elevation_su(rsc) + other_su(rsc)
end

function M.budget(measured, capacity, previous)
  local room = M.USABLE
  if type(capacity) ~= "number" or capacity <= 0 then
    return room
  end
  local external = 0
  if type(measured) == "number" then
    external = measured - (previous or 0)
    if external < 0 then
      external = 0
    end
  end
  local free = capacity - external
  if free < 0 then
    free = 0
  end
  local share = free * M.USABLE / M.CAPACITY
  if share < room then
    room = share
  end
  return room
end

function M.limit_manual(outputs, measured, capacity, previous)
  if outputs == nil or outputs.rsc == nil then
    return outputs
  end
  local room = M.budget(measured, capacity, previous)
  local rsc = outputs.rsc
  local elev_su = elevation_su(rsc)
  local rest_su = other_su(rsc)
  if elev_su + rest_su <= room then
    return outputs
  end
  -- Shed the forward and side controllers before cutting the climb. The
  -- climb stays at least as high as the hover this budget can hold.
  if elev_su >= room then
    local max_elev = room / (M.ELEVATION_PROPS * M.ELEVATION_IMPACT)
    if (rsc.rsc11 or 0) < 0 then
      rsc.rsc11 = -max_elev
    else
      rsc.rsc11 = max_elev
    end
    scale_others(rsc, 0)
    return outputs
  end
  scale_others(rsc, (room - elev_su) / rest_su)
  if M.consumed(outputs) > room then
    local left = other_su(rsc)
    if left > 0 then
      scale_others(rsc, (room - elev_su) / left)
    end
  end
  return outputs
end

return M
