package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local diagnostic = require("diagnostic")

local clamped = diagnostic.apply({ device = "rsc17", rpm = 100 }, nil)
A.eq(clamped.rsc.rsc17, 32, "upper clamp")
A.eq(clamped.rsc.rsc16, 0, "others zero")

local neg = diagnostic.apply({ device = "rsc17", rpm = -100 }, nil)
A.eq(neg.rsc.rsc17, -32, "lower clamp")

local relay = diagnostic.apply({ device = "relay7", side = "bottom", level = 20 }, nil)
A.eq(relay.diag_relay.level, 15, "level clamp")
A.eq(relay.diag_relay.side, "bottom", "side")
A.eq(relay.relays.relay7, false, "flight cutoff stays false")

local hover = diagnostic.apply(
  { device = "relay7", side = "top", level = 15 },
  { enabled = true, rpm = 180 }
)
A.eq(hover.diag_relay, nil, "corner cutoff locked")
A.eq(hover.rsc.rsc16, 180, "elevation set past 32")

local blocked = diagnostic.apply({ device = "rsc16", rpm = 10 }, { enabled = true, rpm = 90 })
A.eq(blocked.rsc.rsc16, 90, "rsc16 not the test device")

local all = diagnostic.apply({ type = "diagnostic_all", rpm = 15 }, { enabled = true, rpm = 90 })
for _, name in ipairs({ "rsc12", "rsc13", "rsc14", "rsc15", "rsc16", "rsc17" }) do
  A.eq(all.rsc[name], 15, name .. " diagnostic idle")
end

local ui = require("command_ui")
local screen = ui.new()
local _, entered = ui.key(screen, "t", true, false)
A.eq(entered.type, "diagnostic_all", "T starts the idle spin")
A.eq(entered.rpm, 15, "T requests 15 rpm")
local _, left = ui.key(screen, "t", true, false)
A.eq(left.type, "diagnostic_exit", "T again leaves diagnostics")

local engine = require("engine_tick")
local state = engine.new_state()
local ship = {
  x = 0, y = 100, z = 0, vx = 0, vy = 0, vz = 0,
  forward_speed = 0, side_speed = 0,
  pitch = 0, roll = 0, heading = 0,
  pitch_rate = 0, roll_rate = 0, yaw_rate = 0, dt = 0.05,
}
local outputs
state, outputs = engine.tick(state, {
  ship = ship,
  command = { type = "diagnostic_all", rpm = 15 },
  ready = true,
  config = require("config").default(),
})
for _, name in ipairs({ "rsc12", "rsc13", "rsc14", "rsc15", "rsc16", "rsc17" }) do
  A.eq(outputs.rsc[name], 15, "tick " .. name)
end
A.eq(state.mode, "diagnostic", "idle spin is diagnostic")
state, outputs = engine.tick(state, {
  ship = ship,
  command = { type = "set_mode", mode = "semi" },
  ready = true,
  config = require("config").default(),
})
A.eq(state.diagnostic, false, "semi leaves the idle spin")
