package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local monitors = require("monitors")

local pages = monitors.assign({
  { name = "monitor_1", w = 80, h = 40 },
  { name = "monitor_2", w = 80, h = 40 },
  { name = "monitor_3", w = 80, h = 40 },
  { name = "monitor_4", w = 20, h = 10 },
  { name = "monitor_5", w = 20, h = 10 },
  { name = "monitor_6", w = 20, h = 10 },
  { name = "monitor_7", w = 20, h = 10 },
})
A.eq(pages.monitor_4, "Flight", "command monitor 4")
A.eq(pages.monitor_5, "Navigation", "command monitor 5")
A.eq(pages.monitor_6, "Engines", "command monitor 6")
A.eq(pages.monitor_7, "Emergency", "command monitor 7")
A.eq(pages.monitor_1, nil, "monitor 1 is not a command page")
A.eq(pages.monitor_2, nil, "monitor 2 is not a command page")
A.eq(pages.monitor_3, nil, "monitor 3 is not a command page")
print("command pages bound only to monitor_4 monitor_5 monitor_6 monitor_7")

local names = monitors.names()
A.eq(#names, 4, "four command monitors")
A.eq(names[1], "monitor_4", "first command monitor")
A.eq(names[4], "monitor_7", "last command monitor")

local swapped = monitors.swap(pages, "monitor_4", "monitor_6")
A.eq(swapped.monitor_4, "Engines", "moved away")
A.eq(swapped.monitor_6, "Flight", "moved here")
A.eq(swapped.monitor_5, "Navigation", "untouched")
