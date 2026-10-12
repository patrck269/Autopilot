local M = {}

-- Create's network stress is impact * abs(RPM). Elevation is controller 16.
-- The four RCS pullers are controllers 12, 13, 14, and 15. Forward is 17.
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

local RCS = { "rsc12", "rsc13", "rsc14", "rsc15" }
local FORWARD = "rsc17"

local function elevation_su(rsc)
  return math.abs(rsc.rsc16 or 0) * M.ELEVATION_PROPS * M.ELEVATION_IMPACT
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
  -- Create's network capacity is each source's rating times its speed. A
  -- stopped shaft therefore reads 0. Treating that as an empty budget commands
  -- zero RPM forever, so the shaft can never start. Shed the load only when a
  -- live network drops to 0.
  if type(capacity) ~= "number" or capacity < 0 then
    return room
  end
  if capacity == 0 then
    if (M.network_capacity or 0) > 0 then
      M.network_capacity = 0
      return 0
    end
    return room
  end
  M.network_capacity = capacity
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
  return M.limit_budget(outputs, M.budget(measured, capacity, previous))
end

function M.limit_budget(outputs, room)
  if outputs == nil or outputs.rsc == nil then
    return outputs
  end
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
    if (rsc.rsc16 or 0) < 0 then
      rsc.rsc16 = -max_elev
    else
      rsc.rsc16 = max_elev
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
