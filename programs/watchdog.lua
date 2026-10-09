local program = shell.getRunningProgram()
local dir = fs.getDir(program)
package.path = fs.combine(dir, "src") .. "/?.lua;" .. package.path

local config = require("config")
local mix = require("mix")
local runtime = require("runtime")
local link = require("link")
local watchdog = require("watchdog")

local cfg = config.default()
local wd = watchdog.new()
local devices = {}

local function wrap_devices()
  local found = {}
  for key, name in pairs(cfg.names) do
    if key ~= "wired_modem" and key ~= "ender_modem" then
      found[key] = peripheral.wrap(name)
    end
  end
  return found
end

local function apply(action)
  if action.write_zero then
    -- runtime attempts every device before reporting failures. Keep the
    -- watchdog alive and broadcasting its latch so later ticks can retry.
    local ok, failure = pcall(runtime.apply, mix.zero(), devices)
    if not ok then print("Watchdog stop failed: " .. tostring(failure)) end
  end
  if action.broadcast ~= nil then
    rednet.broadcast({ type = "watchdog", latched = action.broadcast })
  end
end

local function step(event)
  local action
  wd, action = watchdog.step(wd, event)
  apply(action)
end

local function handle_frame(msg)
  local now = os.clock()
  if msg.type == "arm" then
    step({ type = "arm", engine_id = msg.engine_id, now = now })
  elseif msg.type == "disarm" then
    step({ type = "disarm", now = now })
  elseif msg.type == "zero" then
    step({ type = "zero", now = now })
  elseif msg.type == "clear" then
    step({ type = "clear", now = now })
  end
end

local function rednet_loop()
  local timer = os.startTimer(0.2)
  while true do
    local event, sender, message = os.pullEvent()
    local now = os.clock()
    if event == "rednet_message" and type(message) == "table" then
      if message.type == "clear_emergency" then
        step({ type = "clear_emergency", now = now })
      elseif type(message.mode) == "string" then
        step({ type = "status", sender = sender, mode = message.mode, now = now })
      end
    elseif event == "timer" and sender == timer then
      step({ type = "tick", now = now })
      timer = os.startTimer(0.2)
    elseif event == "peripheral" or event == "peripheral_detach" then
      devices = wrap_devices()
    end
  end
end

local function socket_loop()
  local open = function(path, mode)
    return fs.open(path, mode)
  end
  local token = link.read_text(open, "debug.token")
  local url = link.read_text(open, "debug.url")
  if not link.should_dial(token) or url == nil then
    while true do
      os.pullEvent()
    end
  end
  while true do
    local ok = pcall(function()
      link.serve(url, token, "watchdog", handle_frame)
    end)
    if not ok then
      step({ type = "socket_drop", now = os.clock() })
    end
    sleep(5)
  end
end

devices = wrap_devices()
rednet.open(cfg.names.wired_modem)
parallel.waitForAll(rednet_loop, socket_loop)
