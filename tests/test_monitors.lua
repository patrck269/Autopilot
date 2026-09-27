package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local monitors = require("monitors")

local pages = monitors.assign({
  { name = "m_small_b", w = 28, h = 30 },
  { name = "m_large_b", w = 42, h = 30 },
  { name = "m_large_a", w = 42, h = 30 },
  { name = "m_small_a", w = 28, h = 30 },
})
A.eq(pages.m_large_a, "Flight", "tie breaks by name")
A.eq(pages.m_large_b, "Navigation", "second large")
A.eq(pages.m_small_a, "Engines", "third")
A.eq(pages.m_small_b, "Emergency", "fourth")

local swapped = monitors.swap(pages, "m_large_a", "m_small_a")
A.eq(swapped.m_large_a, "Engines", "moved away")
A.eq(swapped.m_small_a, "Flight", "moved here")
A.eq(swapped.m_large_b, "Navigation", "untouched")
