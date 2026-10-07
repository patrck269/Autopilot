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
A.eq(session.busy, true, "eval stays busy until its result is released")
shell.release(session)
A.eq(session.busy, false, "release clears the busy flag")
print("pass: eval returns values")
print("pass: eval captures print")

_G.shell = shell
local captured = {}
_G.captured = captured
_G.clock = still_clock
local outer = shell.eval(session, [[
  local via_eval = shell.eval(session, "return 9", clock)
  captured.eval_ok = via_eval.ok
  captured.eval_error = via_eval.error
  local via_handle = shell.handle(session, { type = "eval", id = "inner", code = "return 8" }, { clock = clock })
  captured.handle_ok = via_handle.ok
  captured.handle_error = via_handle.error
  return 4
]], still_clock)
A.eq(outer.ok, true, "the running eval still returns")
A.eq(outer.values[1], 4, "the running eval returns its value")
A.eq(captured.eval_ok, false, "a nested eval is rejected")
A.eq(captured.eval_error, "busy", "a nested eval is busy")
A.eq(captured.handle_ok, false, "a nested handle is rejected")
A.eq(captured.handle_error, "busy", "a nested handle is busy")
local queued = shell.eval(session, "return 3", still_clock)
A.eq(queued.ok, false, "an eval is rejected until the running one is released")
A.eq(queued.error, "busy", "the queued eval is busy")
shell.release(session)
A.eq(session.busy, false, "release clears the busy flag after the nested eval")
_G.shell = nil
_G.clock = nil
_G.captured = nil
print("pass: second eval is busy")

local sent = {}
local second_ran = false
_G.mark_second = function()
  second_ran = true
end
local queued_eval = { { type = "eval", id = "2", code = "mark_second() return 2" } }
local turn_session = shell.new_session({ emergency = false }, {}, {})
link.turn(turn_session, { type = "eval", id = "1", code = "return 1" }, function(msg)
  return shell.handle(turn_session, msg, { clock = still_clock })
end, function()
  if #queued_eval == 0 then
    return nil
  end
  return table.remove(queued_eval, 1)
end, function(reply)
  sent[#sent + 1] = reply
end, { sleep = function() end, reboot = function() end })
A.eq(second_ran, false, "a buffered second eval does not run")
A.eq(sent[1].values[1], 1, "the first eval returns")
A.eq(sent[2].ok, false, "the buffered eval is rejected")
A.eq(sent[2].error, "busy", "the buffered eval is busy")
A.eq(turn_session.busy, false, "the turn releases the session")
_G.mark_second = nil
print("pass: a second eval before release is busy")

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
A.eq(ops[2], "move note.txt note.txt.ship-shell-backup", "the previous file is backed up before it is replaced")
A.eq(ops[3], "move note.txt.tmp note.txt", "the temp file becomes the destination")
A.eq(ops[4], "delete note.txt.ship-shell-backup", "the backup is removed after the replace commits")
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

local watchdog = require("watchdog")
local protocol = require("protocol")
local wired_side = config.default().names.wired_modem
local ender = {}
local wired_packets = {}
local function pocket_broadcast(message)
  ender[#ender + 1] = message
end
local function transmit(side, channel, reply, payload)
  wired_packets[#wired_packets + 1] = {
    side = side,
    channel = channel,
    reply = reply,
    payload = payload,
  }
end
pocket_broadcast({ type = "clear_emergency" })
A.eq(#wired_packets, 0, "a pocket clear starts on the ender network only")
local clear_session = shell.new_session({ emergency = true }, {}, {})
clear_session.latched = true
local wd = watchdog.new()
local action
wd, action = watchdog.step(wd, { type = "arm", engine_id = 12, now = 0 })
wd, action = watchdog.step(wd, { type = "zero", now = 0 })
A.eq(wd.latched, true, "the watchdog is holding zero before the pocket clear")
local pending = shell.ingest(clear_session, nil, ender[1], protocol.keep, function(message)
  shell.repeat_wired(message, transmit, wired_side, 12)
end)
A.eq(pending.type, "clear_emergency", "the engine keeps the pocket clear")
A.eq(#wired_packets, 1, "the engine repeats the clear on the wired modem")
A.eq(wired_packets[1].side, wired_side, "the repeat is addressed to the wired modem")
A.eq(wired_packets[1].channel, 65535, "the repeat uses the rednet broadcast channel")
A.eq(wired_packets[1].reply, 12 % 65500, "the reply channel is the engine id in rednet's id range")
local wrapped = wired_packets[1].payload
A.eq(type(wrapped.nMessageID), "number", "the wired packet has a rednet message id")
A.eq(wrapped.nMessageID, wrapped.nMessageID, "the rednet message id is not NaN")
A.eq(wrapped.nRecipient, 65535, "the wired packet is addressed as a rednet broadcast")
A.eq(wrapped.nSender, 12, "the wired packet names the engine as the sender")
local heard = wrapped.message
A.eq(heard.type, "clear_emergency", "the wired packet carries the pocket clear")
wd, action = watchdog.step(wd, { type = heard.type, now = 1 })
A.eq(wd.latched, false, "a pocket clear keeps the watchdog unlatched")
A.eq(action.write_zero, false, "clearing stops the zero write")
A.eq(action.broadcast, false, "the watchdog announces the latch is gone")
shell.note_watchdog(clear_session, { type = "watchdog", latched = action.broadcast })
shell.apply_latch(clear_session, clear_session.state, pending)
wd, action = watchdog.step(wd, { type = "tick", now = 2 })
A.eq(wd.latched, false, "the next watchdog tick stays unlatched")
A.eq(action.write_zero, false, "the next tick does not force zero")
A.eq(action.broadcast, nil, "the next tick does not turn the latch back on")
A.eq(clear_session.latched, false, "the engine stays unlatched")
A.eq(clear_session.state.emergency, false, "the engine emergency stays off")
local echoes = 0
shell.ingest(clear_session, nil, { type = "watchdog", latched = true }, protocol.keep, function()
  echoes = echoes + 1
end)
A.eq(echoes, 0, "a watchdog latch is not repeated onto the wired modem")
print("pass: pocket clear keeps the watchdog unlatched")

local flight_src = io.open("programs/command.lua", "rb"):read("a")
assert(string.find(flight_src, "apply_latch", 1, true), "the flight loop applies the latch")
assert(string.find(flight_src, "repeat_wired", 1, true), "the flight loop repeats a clear on the wired modem")
assert(string.find(flight_src, "cfg.names.wired_modem", 1, true), "the repeat uses the wired modem name")
assert(string.find(flight_src, 'peripheral.call(side, "transmit", channel, reply, payload)', 1, true), "the repeat transmits on the wired modem only")
assert(string.find(flight_src, "on_idle, session", 1, true), "the shell keeps the session busy until the result is sent")
assert(string.find(flight_src, "parallel.waitForAll", 1, true), "the shell runs beside the flight loop")
local retired = io.open("programs/engine.lua", "rb"):read("a")
assert(string.find(retired, "engine_tick.tick", 1, true) == nil, "the engine-room program no longer ticks")
assert(string.find(retired, "runtime.apply", 1, true) == nil, "the engine-room program no longer applies thrust")
assert(string.find(retired, "rednet.broadcast", 1, true) == nil, "the engine-room program no longer broadcasts the heartbeat")
assert(string.find(retired, "link.serve", 1, true) == nil, "the engine-room program no longer dials")
assert(string.find(retired, "link_mod.serve", 1, true) == nil, "the engine-room program no longer dials")
