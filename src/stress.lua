local M = {}

-- Create's network stress is impact * abs(RPM). The four elevation props are
-- clockwork bearings (impact 4) on rsc11; rsc10 has X_PROPS forward bearings.
-- Each RCS output is one vstuff
-- mechanical thruster (impact 8).
M.CAPACITY = 479231
-- Leave room for shafts and the rest of the network. Sitting on the exact
-- capacity overstresses Create, the shaft speed falls to 0, and a vstuff
-- thruster then produces no force.
M.USABLE = 431308
M.RCS_IMPACT = 8
M.ELEVATION_IMPACT = 4
M.ELEVATION_PROPS = 4
M.X_IMPACT = 4
M.X_PROPS = 1

local RCS = { "rsc2", "rsc3", "rsc4", "rsc5", "rsc6", "rsc7", "rsc8", "rsc9" }

function M.consumed(outputs)
  local rsc = outputs.rsc or {}
  local su = math.abs(rsc.rsc11 or 0) * M.ELEVATION_PROPS * M.ELEVATION_IMPACT
  su = su + math.abs(rsc.rsc10 or 0)*M.X_PROPS*M.X_IMPACT
  for _, name in ipairs(RCS) do
    su = su + math.abs(rsc[name] or 0) * M.RCS_IMPACT
  end
  return su
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
  local elev_su = math.abs(rsc.rsc11 or 0) * M.ELEVATION_PROPS * M.ELEVATION_IMPACT
  local rcs_abs = 0
  for _, name in ipairs(RCS) do
    rcs_abs = rcs_abs + math.abs(rsc[name] or 0)
  end
  local x_su = math.abs(rsc.rsc10 or 0)*M.X_PROPS*M.X_IMPACT
  local rcs_su = rcs_abs * M.RCS_IMPACT + x_su
  if elev_su + rcs_su <= room then
    return outputs
  end
  if elev_su >= room then
    local max_elev = room / (M.ELEVATION_PROPS * M.ELEVATION_IMPACT)
    if (rsc.rsc11 or 0) < 0 then
      rsc.rsc11 = -max_elev
    else
      rsc.rsc11 = max_elev
    end
    rsc.rsc10 = 0
    for _, name in ipairs(RCS) do
      rsc[name] = 0
    end
    return outputs
  end
  local scale = (room - elev_su) / rcs_su
  rsc.rsc10 = (rsc.rsc10 or 0) * scale
  for _, name in ipairs(RCS) do
    rsc[name] = (rsc[name] or 0) * scale
  end
  if M.consumed(outputs) > room then
    local left = M.consumed(outputs) - elev_su
    if left > 0 then
      local fix = (room - elev_su) / left
      rsc.rsc10 = (rsc.rsc10 or 0)*fix
      for _, name in ipairs(RCS) do
        rsc[name] = (rsc[name] or 0) * fix
      end
    end
  end
  return outputs
end

return M
