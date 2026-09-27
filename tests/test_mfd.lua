package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local mfd = require("mfd")

local names = { "a", "b", "c", "d" }
A.eq(mfd.hit(40, 30, 1, 29, names), nil, "above the row")
A.eq(mfd.hit(40, 30, 1, 30, names), "a", "first")
A.eq(mfd.hit(40, 30, 11, 30, names), "b", "second")
A.eq(mfd.hit(40, 30, 21, 30, names), "c", "third")
A.eq(mfd.hit(40, 30, 31, 30, names), "d", "fourth")
