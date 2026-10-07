package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local views = require("views")

local nav = views.navigation({
  x = 0, y = 100, z = 0,
  vx = 10, vy = 0, vz = 0,
  heading = 1.2,
  mode = "auto",
  waypoint_x = 0,
  waypoint_z = 100,
})
A.near(nav.overall, 10, 1e-6, "overall speed")
A.near(nav.eta, 10, 1e-6, "eta")
A.near(nav.drift, 10, 1e-6, "drift off the track")
A.eq(nav.altitude, 100, "altitude")
A.near(nav.bearing, 1.2 * 180 / math.pi, 1e-6, "bearing")
local wrapped = views.navigation({
  x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0,
  heading = -1, mode = "manual", waypoint_x = 1, waypoint_z = 0,
})
if not (wrapped.bearing >= 0) then
  error("bearing must not be negative, got " .. tostring(wrapped.bearing))
end
local circle = 360
for step = -8, 8 do
  local heading = step * 0.7
  local spun = views.navigation({
    x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0,
    heading = heading, mode = "manual", waypoint_x = 0, waypoint_z = 0,
  })
  if spun.bearing < 0 or spun.bearing >= circle then
    error("bearing left the non-negative circle: " .. tostring(spun.bearing))
  end
end
A.eq(string.find(nav.compass, "|", 1, true) ~= nil, true, "compass mark")
local north = views.navigation({
  x = 0, y = 100, z = 0, vx = 0, vy = 0, vz = 0,
  heading = 0, mode = "manual", waypoint_x = 0, waypoint_z = 1,
})
local south = views.navigation({
  x = 0, y = 100, z = 0, vx = 0, vy = 0, vz = 0,
  heading = math.pi, mode = "manual", waypoint_x = 0, waypoint_z = 1,
})
A.eq(north.compass == south.compass, false, "compass follows heading")

local outputs = {
  rsc = {
    rsc6 = 0, rsc7 = 10, rsc8 = 0, rsc9 = 0,
    rsc10 = 30, rsc11 = 20,
  },
  relays = { relay7 = true, relay3 = false },
}
local sample = {
  vx = 3, vy = -1, vz = 4,
  heading = 0.5,
  pitch_rate = 0, roll_rate = 0.3, yaw_rate = 0.4,
}
local flight = views.flight(sample, outputs)
A.eq(flight.vx, 3, "speed x")
A.eq(flight.vy, -1, "speed y")
A.eq(flight.vz, 4, "speed z")
A.near(flight.rotation, 0.5, 1e-6, "rotation")
A.near(flight.bearing, 0.5 * 180 / math.pi, 1e-6, "flight bearing")
A.near(views.navigation({
  x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0,
  heading = 0, mode = "manual", waypoint_x = 0, waypoint_z = 0,
}).bearing, 0, 1e-9, "yaw 0 displays as 0 degrees")
A.near(views.navigation({
  x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0,
  heading = math.pi, mode = "manual", waypoint_x = 0, waypoint_z = 0,
}).bearing, 180, 1e-6, "yaw pi displays as 180 degrees")
local colors = {}
for _, thruster in ipairs(flight.thrusters) do
  colors[thruster.id] = thruster.color
end
A.eq(colors.rsc10, "green", "powered thruster")
A.eq(colors.rsc6, "gray", "idle thruster")
A.eq(colors.rsc2, nil, "bottom thruster is not on the flight page")

local groups = views.engines(outputs, 256)
local by_type = {}
for _, group in ipairs(groups) do
  by_type[group.type] = group
end
A.eq(by_type["X axis propellers"].devices[1].rpm, 30, "x rpm")
A.eq(by_type["Z axis propellers"].devices[1].rpm, 20, "z rpm")
A.eq(by_type["RCS"].devices[1].name, "RSC 6", "rcs group")
A.eq(by_type["RCS"].devices[2].rpm, 10, "rcs rpm")
A.eq(#by_type["RCS"].devices, 4, "side props only")
A.eq(by_type["Main shaft"].devices[1].rpm, 256, "shaft rpm")
local stress = views.stress(40, 100, outputs)
A.eq(stress.consumed, 40, "su consumed")
A.eq(stress.remaining, 60, "su remaining")
if not (stress.x_axis_propellers > 0 and stress.z_axis_propellers > 0 and stress.rcs > 0) then
  error("expected SU on all three types")
end

local diagram = views.emergency(outputs)
local emergency = {}
for _, part in ipairs(diagram) do
  emergency[part.label] = part.color
end
A.eq(emergency["PB prop"], "red", "cut prop")
A.eq(emergency["SA side"], "green", "powered side prop")
A.eq(emergency["PB side"], "gray", "idle side prop")
A.eq(emergency["PB up"], nil, "bottom thruster is not on the emergency page")
local placed = {}
for _, part in ipairs(diagram) do
  placed[part.label] = part
end
A.eq(placed["PB prop"].x < placed["SB prop"].x, true, "port is left of starboard")
A.eq(placed["PB prop"].y < placed["PS prop"].y, true, "bow is ahead of stern")
