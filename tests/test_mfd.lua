package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local mfd = require("mfd")

local controls = mfd.controls(39, 20)
local labels = {}
for _, control in ipairs(controls) do
  labels[#labels + 1] = control.label
  A.eq(control.label, control.page, "label is the page name")
end
A.eq(labels[1], "Flight", "flight label")
A.eq(labels[2], "Navigation", "navigation label")
A.eq(labels[3], "Engines", "engines label")
A.eq(labels[4], "Emergency", "emergency label")
A.eq(labels[5], "Systems", "systems label")

A.eq(mfd.hit(39, 20, 1, 19), "Flight", "touch flight tab")
A.eq(mfd.hit(39, 20, 14, 19), "Navigation", "touch navigation tab")
A.eq(mfd.hit(39, 20, 27, 19), "Engines", "touch engines tab")
A.eq(mfd.hit(39, 20, 1, 20), "Emergency", "touch emergency tab")
A.eq(mfd.hit(39, 20, 20, 20), "Systems", "touch systems tab")
A.eq(mfd.hit(39, 20, 20, 10), nil, "touch off the tabs")
