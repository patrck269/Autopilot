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
A.eq(nav.bearing, 1.2, "bearing")
A.eq(string.find(nav.compass, "|", 1, true) ~= nil, true, "compass mark")

local outputs = {
  rsc = {
    rsc2 = 0, rsc3 = 10, rsc4 = 0, rsc5 = 0,
    rsc6 = 0, rsc7 = 0, rsc8 = 0, rsc9 = 0,
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
A.eq(flight.bearing, 0.5, "flight bearing")
local colors = {}
for _, thruster in ipairs(flight.thrusters) do
  colors[thruster.id] = thruster.color
end
A.eq(colors.rsc10, "green", "powered thruster")
A.eq(colors.rsc2, "gray", "idle thruster")

local groups = views.engines(outputs, 256)
local by_type = {}
for _, group in ipairs(groups) do
  by_type[group.type] = group
end
A.eq(by_type["X propellers"].devices[1].rpm, 30, "x rpm")
A.eq(by_type["Elevation propellers"].devices[1].rpm, 20, "elevation rpm")
A.eq(by_type["Upward thrusters"].devices[1].name, "RSC 2", "up group")
A.eq(by_type["Upward thrusters"].devices[2].rpm, 10, "up rpm")
A.eq(by_type["Side thrusters"].devices[1].rpm, 0, "side rpm")
A.eq(by_type["Main shaft"].devices[1].rpm, 256, "shaft rpm")

local diagram = views.emergency(outputs)
local emergency = {}
for _, part in ipairs(diagram) do
  emergency[part.label] = part.color
end
A.eq(emergency["PB prop"], "red", "cut prop")
A.eq(emergency["PB up"], "green", "powered up thruster")
A.eq(emergency["SB up"], "gray", "idle up thruster")
