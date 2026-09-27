package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local mfd = require("mfd")

local controls = mfd.controls(80, 20)
A.eq(#controls, 5, "five pages")
for _, control in ipairs(controls) do
  A.eq(control.label, control.page, "full word label")
  A.eq(mfd.hit(80, 20, control.x, control.y), control.page, "first character " .. control.page)
  A.eq(mfd.hit(80, 20, control.x + control.w - 1, control.y), control.page, "last character " .. control.page)
  A.eq(mfd.hit(80, 20, control.x + control.w, control.y), nil, "one cell outside " .. control.page)
end
