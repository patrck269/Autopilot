local M = {}

local function hypot(a, b)
  return math.sqrt(a * a + b * b)
end

function M.navigation(sample)
  local dx = sample.waypoint_x - sample.x
  local dz = sample.waypoint_z - sample.z
  local distance = hypot(dx, dz)
  local overall = math.sqrt(sample.vx * sample.vx + sample.vy * sample.vy + sample.vz * sample.vz)
  local horizontal = hypot(sample.vx, sample.vz)
  local drift = 0
  if distance > 0 then
    drift = (sample.vx * dz - sample.vz * dx) / distance
  end
  local eta = nil
  if sample.mode == "auto" and horizontal > 0 then
    eta = distance / horizontal
  end
  local ticks = {}
  for i = 1, 16 do
    ticks[i] = "-"
  end
  ticks[8] = "|"
  return {
    eta = eta,
    overall = overall,
    altitude = sample.y,
    drift = drift,
    bearing = sample.heading,
    distance = distance,
    compass = table.concat(ticks),
  }
end

local FLIGHT_PARTS = {
  { id = "rsc10", label = "X prop" },
  { id = "rsc11", label = "Elev prop" },
  { id = "rsc2", label = "SB up" },
  { id = "rsc3", label = "PB up" },
  { id = "rsc4", label = "SS up" },
  { id = "rsc5", label = "PS up" },
  { id = "rsc6", label = "PB side" },
  { id = "rsc7", label = "SA side" },
  { id = "rsc8", label = "PA side" },
  { id = "rsc9", label = "BS side" },
}

function M.flight(sample, outputs)
  local thrusters = {}
  for _, part in ipairs(FLIGHT_PARTS) do
    local rpm = outputs.rsc[part.id] or 0
    local powered = math.abs(rpm) > 0
    thrusters[#thrusters + 1] = {
      id = part.id,
      label = part.label,
      rpm = rpm,
      color = powered and "green" or "gray",
    }
  end
  local pitch_rate = sample.pitch_rate or 0
  local roll_rate = sample.roll_rate or 0
  local yaw_rate = sample.yaw_rate or 0
  return {
    vx = sample.vx,
    vy = sample.vy,
    vz = sample.vz,
    rotation = math.sqrt(pitch_rate * pitch_rate + roll_rate * roll_rate + yaw_rate * yaw_rate),
    bearing = sample.heading,
    thrusters = thrusters,
  }
end

local function device(name, rpm)
  return { name = name, rpm = rpm or 0 }
end

function M.engines(outputs, shaft_rpm)
  local rsc = outputs.rsc
  return {
    { type = "Main shaft", devices = { device("Speedometer", shaft_rpm or 0) } },
    { type = "X propellers", devices = { device("RSC 10", rsc.rsc10) } },
    { type = "Elevation propellers", devices = { device("RSC 11", rsc.rsc11) } },
    {
      type = "Upward thrusters",
      devices = {
        device("RSC 2", rsc.rsc2),
        device("RSC 3", rsc.rsc3),
        device("RSC 4", rsc.rsc4),
        device("RSC 5", rsc.rsc5),
      },
    },
    {
      type = "Side thrusters",
      devices = {
        device("RSC 6", rsc.rsc6),
        device("RSC 7", rsc.rsc7),
        device("RSC 8", rsc.rsc8),
        device("RSC 9", rsc.rsc9),
      },
    },
  }
end

local EMERGENCY_PARTS = {
  { label = "PB prop", rpm = "rsc11", cut = "relay7" },
  { label = "SB prop", rpm = "rsc11", cut = "relay8" },
  { label = "SS prop", rpm = "rsc11", cut = "relay9" },
  { label = "PS prop", rpm = "rsc11", cut = "relay10" },
  { label = "PB up", rpm = "rsc3" },
  { label = "SB up", rpm = "rsc2" },
  { label = "PS up", rpm = "rsc5" },
  { label = "SS up", rpm = "rsc4" },
  { label = "PB side", rpm = "rsc6" },
  { label = "SA side", rpm = "rsc7" },
  { label = "PA side", rpm = "rsc8" },
  { label = "BS side", rpm = "rsc9" },
  { label = "X prop", rpm = "rsc10", cut = "relay3" },
}

function M.emergency(outputs)
  local parts = {}
  for _, part in ipairs(EMERGENCY_PARTS) do
    local rpm = outputs.rsc[part.rpm] or 0
    local cut = part.cut ~= nil and outputs.relays[part.cut] == true
    local color = "gray"
    if cut then
      color = "red"
    elseif math.abs(rpm) > 0 then
      color = "green"
    end
    parts[#parts + 1] = { label = part.label, color = color, rpm = rpm }
  end
  return parts
end

return M
