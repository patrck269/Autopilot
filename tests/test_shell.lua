package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local shell = require("shell")
local engine_tick = require("engine_tick")
local config = require("config")

A.eq(shell.should_dial(nil), false, "missing token does not dial")
A.eq(shell.should_dial(""), false, "empty token does not dial")
A.eq(shell.should_dial("secret"), true, "a token dials")
local link = require("link")
local function opener(contents)
  return function(path)
    local text = contents[path]
    if text == nil then
      return nil
    end
    return {
      readAll = function()
        return text
      end,
      close = function() end,
    }
  end
end
A.eq(link.read_text(opener({}), "debug.token"), nil, "absent token file does not dial")
A.eq(link.read_text(opener({ ["debug.token"] = "  \n" }), "debug.token"), nil, "blank token file does not dial")
A.eq(shell.should_dial(link.read_text(opener({}), "debug.token")), false, "the engine dial check sees a missing token")
print("pass: missing token does not dial")

local function still_clock()
  return 0
end

local session = shell.new_session({ mode = "idle", emergency = false }, {}, {})
local first = shell.eval(session, 'print("hi") return 7, "x"', still_clock)
A.eq(first.ok, true, "eval runs")
A.eq(first.values[1], 7, "first return value")
A.eq(first.values[2], "x", "second return value")
A.eq(first.output, "hi", "printed output")
A.eq(session.busy, false, "eval clears the busy flag")
print("pass: eval returns values")
print("pass: eval captures print")

session.busy = true
local second = shell.eval(session, "return 1", still_clock)
A.eq(second.ok, false, "a second eval is rejected")
A.eq(second.error, "busy", "the rejection is busy")
A.eq(session.busy, true, "a rejected eval leaves the running one busy")
session.busy = false
print("pass: second eval is busy")

local slow_state = { emergency = false }
local slow = shell.new_session(slow_state, {}, {})
local calls = 0
local function slow_clock()
  calls = calls + 1
  if calls == 1 then
    return 0
  end
  return 3
end
local slowed = shell.eval(slow, "return 1", slow_clock)
A.eq(slowed.ok, true, "a slow eval still returns")
A.eq(slow.latched, true, "three seconds sets the latch")
A.eq(slow_state.emergency, true, "three seconds sets emergency before the caller continues")
print("pass: three second eval sets the emergency latch")

local quick_state = { emergency = false }
local quick = shell.new_session(quick_state, {}, {})
local quick_calls = 0
local function quick_clock()
  quick_calls = quick_calls + 1
  if quick_calls == 1 then
    return 0
  end
  return 2
end
shell.eval(quick, "return 1", quick_clock)
A.eq(quick.latched, false, "an eval under three seconds does not latch")
A.eq(quick_state.emergency, false, "an eval under three seconds leaves emergency alone")

local files = {}
local ops = {}
local fake_fs = {
  open = function(path, mode)
    ops[#ops + 1] = mode .. " " .. path
    return {
      write = function(text)
        files[path] = text
      end,
      readAll = function()
        return files[path]
      end,
      close = function() end,
    }
  end,
  exists = function(path)
    return files[path] ~= nil
  end,
  delete = function(path)
    ops[#ops + 1] = "delete " .. path
    files[path] = nil
  end,
  move = function(src, dest)
    ops[#ops + 1] = "move " .. src .. " " .. dest
    files[dest] = files[src]
    files[src] = nil
  end,
}
files["note.txt"] = "old"
local written = shell.write_file(fake_fs, "note.txt", "new")
A.eq(written.ok, true, "write replaces a file")
A.eq(files["note.txt"], "new", "the new contents are what was written")
A.eq(ops[1], "w note.txt.tmp", "write goes to a temp file first")
A.eq(ops[2], "delete note.txt", "the previous file is removed after the temp is closed")
A.eq(ops[3], "move note.txt.tmp note.txt", "the temp file becomes the destination")
local read_back = shell.read_file(fake_fs, "note.txt")
A.eq(read_back.ok, true, "read finds the file")
A.eq(read_back.content, "new", "read returns the replaced contents")
local missing = shell.read_file(fake_fs, "absent.txt")
A.eq(missing.ok, false, "a missing file is an error")

local order = {}
shell.reboot(function()
  order[#order + 1] = "send"
end, function(seconds)
  order[#order + 1] = "sleep " .. tostring(seconds)
end, function()
  order[#order + 1] = "reboot"
end)
A.eq(order[1], "send", "reboot answers first")
A.eq(order[2], "sleep 0.5", "reboot waits half a second")
A.eq(order[3], "reboot", "reboot runs after the answer")

local cfg = config.default()
local ship = {
  y = 100, x = 0, z = 0, vx = 0, vy = 0, vz = 0,
  pitch = 0, roll = 0, heading = 0, pitch_rate = 0, roll_rate = 0, dt = 0.05,
}
local flight = engine_tick.new_state()
local flight_session = shell.new_session(flight, cfg, {})
shell.apply_latch(flight_session, flight, nil)
local _, flying = engine_tick.tick(flight, {
  ship = ship,
  command = { type = "stick", x = 1, y = 0, z = 0 },
  su = 12,
  ready = true,
  stick_fresh = true,
  config = cfg,
})
A.eq(flight.emergency, false, "an unlatched ship is not forced into emergency")
A.eq(flying.rsc.rsc10, cfg.hover_step, "an unlatched ship still takes a stick command")

flight_session.latched = true
shell.apply_latch(flight_session, flight, nil)
A.eq(flight.emergency, true, "a latch forces emergency before the tick")
local _, held = engine_tick.tick(flight, {
  ship = ship,
  command = { type = "stick", x = 1, y = 0, z = 0 },
  su = 12,
  ready = true,
  stick_fresh = true,
  config = cfg,
})
A.eq(held.rsc.rsc10, 0, "a latched tick zeros the x controller")
A.eq(held.rsc.rsc11, 0, "a latched tick zeros elevation")

shell.apply_latch(flight_session, flight, { type = "clear_emergency" })
A.eq(flight_session.latched, false, "clear emergency drops the engine latch before the tick")
A.eq(flight.emergency, false, "clear emergency drops the emergency flag")

local noted = shell.new_session({ emergency = false }, {}, {})
A.eq(shell.note_watchdog(noted, { type = "watchdog", latched = true }), true, "watchdog messages are consumed")
A.eq(noted.latched, true, "a watchdog latch sets the session")
A.eq(noted.state.emergency, true, "a watchdog latch sets emergency")
A.eq(shell.note_watchdog(noted, { type = "stick", x = 0, y = 0, z = 0 }), false, "flight commands stay on the flight path")

local engine_src = io.open("programs/engine.lua", "rb"):read("a")
assert(string.find(engine_src, "apply_latch", 1, true), "the flight loop applies the latch")
assert(string.find(engine_src, "note_watchdog", 1, true), "the flight loop honors watchdog messages")
assert(string.find(engine_src, "parallel.waitForAll", 1, true), "the shell runs beside the flight loop")
