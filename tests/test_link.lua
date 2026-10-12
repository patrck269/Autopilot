package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local link = require("link")

A.eq(link.bridge_down("Could not connect"), true, "down bridge stays quiet")
A.eq(link.bridge_down("Connection refused"), true, "refused bridge stays quiet")
A.eq(link.bridge_down("not ready"), false, "handshake failure is still reported")

print("link dial warnings passed")
