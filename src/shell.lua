local numeric = require("numeric")
local M = {}

local OUTPUT_LIMIT = 8192

function M.should_dial(token)
  return type(token) == "string" and token ~= ""
end

function M.new_session(state, cfg, devices)
  return {
    state = state,
    cfg = cfg,
    devices = devices,
    ship = nil,
    su = nil,
    latched = false,
    busy = false,
    engine_tick = nil,
    runtime = nil,
    config = nil,
    protocol = nil,
  }
end

function M.apply_latch(session, state, command)
  if command ~= nil and command.type == "clear_emergency" then
    session.latched = false
    state.emergency = false
    return
  end
  if session.latched then
    state.emergency = true
  end
end

function M.note_watchdog(session, message)
  if type(message) ~= "table" or message.type ~= "watchdog" then
    return false
  end
  if type(message.latched) ~= "boolean" then return false end
  session.latched = message.latched
  if session.state ~= nil then
    session.state.emergency = session.latched
  end
  return true
end

local function export_value(value, depth, context)
  context=context or {left=1024,seen={}}
  context.left=context.left-1
  if context.left<0 then context.truncated=true;return "[truncated]" end
  local kind=type(value)
  if kind=="number" and not numeric.finite(value) then return tostring(value) end
  if kind=="boolean" or kind=="number" then return value end
  if kind=="string" then
    if #value>65536 then context.truncated=true end
    return value:sub(1,65536)
  end
  if kind~="table" then return tostring(value) end
  if context.seen[value] then return "[cycle]" end
  if depth>=8 then context.truncated=true;return "[depth limit]" end
  context.seen[value]=true
  local out,count={},0
  local array=true
  for key in pairs(value) do if type(key)~="number" or key<1 or key%1~=0 then array=false end end
  for key,item in pairs(value) do
    count=count+1
    if count>128 or context.left<=0 then context.truncated=true;out.truncated=true;break end
    if type(key)=="string" or type(key)=="number" then
      out[array and key or tostring(key)]=export_value(item,depth+1,context)
    end
  end
  context.seen[value]=nil
  return out
end

local function make_env(session, lines)
  local env = {
    state = session.state,
    cfg = session.cfg,
    devices = session.devices,
    engine_tick = session.engine_tick,
    runtime = session.runtime,
    config = session.config,
    protocol = session.protocol,
    package = package,
    session = session,
    print = function(...)
      local count = select("#", ...)
      local parts = {}
      for i = 1, count do
        parts[i] = tostring(select(i, ...))
      end
      local line = table.concat(parts, "\t")
      local remaining = OUTPUT_LIMIT - (lines.bytes or 0)
      if #line>remaining then lines.truncated=true end
      if remaining > 0 then
        line = string.sub(line,1,remaining)
        lines[#lines+1] = line
        lines.bytes = (lines.bytes or 0) + #line + 1
      end
    end,
  }
  return setmetatable(env, { __index = _G })
end

local function load_chunk(code, env)
  return load(code, "=eval", "t", env)
end

function M.eval(session, code, clock)
  if type(code) ~= "string" then return {ok=false,error="bad code",values={},output=""} end
  if session.busy then
    return { ok = false, error = "busy", values = {}, output = "" }
  end
  session.busy = true
  local started = clock()
  local lines = {}
  local env = make_env(session, lines)
  local chunk, load_err = load_chunk(code, env)
  local result
  if chunk == nil then
    result = { ok = false, error = load_err, values = {}, output = "" }
  else
    local returned = { n = 0 }
    local function collect(...)
      returned.n = select("#", ...)
      for i = 1, returned.n do
        returned[i] = select(i, ...)
      end
    end
    local ok, err = xpcall(function()
      collect(chunk())
    end, function(caught)
      return tostring(caught)
    end)
    local values = {}
    local context={left=1024,seen={}}
    if ok then
      for i = 1, returned.n do
        values[i] = returned[i] == nil and "nil" or export_value(returned[i], 0, context)
      end
      result = { ok = true, values = values, output = "", truncated = context.truncated or nil }
    else
      result = { ok = false, error = err, values = {}, output = "" }
    end
  end
  local text = table.concat(lines, "\n")
  if #text > OUTPUT_LIMIT then
    text = string.sub(text, 1, OUTPUT_LIMIT)
  end
  result.output = text
  if lines.truncated then result.truncated=true end
  local elapsed = clock() - started
  if elapsed >= 3 then
    session.latched = true
    if session.state ~= nil then
      session.state.emergency = true
    end
  end
  return result
end

function M.release(session)
  if type(session) == "table" then
    session.busy = false
  end
end

function M.ingest(session, pending, message, keep, forward)
  if M.note_watchdog(session, message) then
    return pending
  end
  if type(message) == "table" and message.type == "emergency" then
    session.latched = true
    if session.state then session.state.emergency = true end
  end
  local command = keep(pending, message)
  if type(message) == "table" and message.type == "clear_emergency"
      and type(command) == "table" then
    local accepted = command.type=="clear_emergency" or command[#command] and command[#command].type=="clear_emergency"
    if accepted and forward then forward({type="clear_emergency"}) end
  end
  return command
end

function M.repeat_wired(message, transmit, wired_side, sender_id)
  if type(message) ~= "table" or message.type ~= "clear_emergency" then
    return false
  end
  if type(wired_side) ~= "string" or wired_side == "" or type(sender_id) ~= "number" then
    return false
  end
  local channel = 65535
  transmit(wired_side, channel, sender_id % 65500, {
    nMessageID = math.random(1, 2147483647),
    nRecipient = channel,
    nSender = sender_id,
    message = message,
  })
  return true
end

function M.write_file(fs, path, content)
  if type(path) ~= "string" or path == "" or type(content) ~= "string" then
    return { ok = false, error = "bad path" }
  end
  local tmp = path .. ".tmp"
  if fs.exists(tmp) then return {ok=false,error="temporary file exists; recover previous write first"} end
  local handle = fs.open(tmp, "w")
  if handle == nil then
    return { ok = false, error = "open failed" }
  end
  handle.write(content or "")
  handle.close()
  local backup = path .. ".ship-shell-backup"
  if fs.exists(backup) then return {ok=false,error="backup exists; recover previous write first"} end
  local existed=fs.exists(path)
  if existed then fs.move(path,backup) end
  local ok,err=pcall(fs.move,tmp,path)
  if not ok then
    if existed then fs.move(backup,path) end
    return {ok=false,error=tostring(err)}
  end
  if existed then fs.delete(backup) end
  return { ok = true, values = {}, output = "" }
end

function M.read_file(fs, path)
  if type(path) ~= "string" or path == "" or not fs.exists(path) then
    return { ok = false, error = "missing", values = {}, output = "" }
  end
  local handle = fs.open(path, "r")
  if handle == nil then
    return { ok = false, error = "open failed", values = {}, output = "" }
  end
  local body = handle.read and handle.read(96*1024+1) or handle.readAll()
  handle.close()
  local truncated=type(body)=="string" and #body>96*1024
  if truncated then body=body:sub(1,96*1024) end
  return { ok = true, content = body or "", values = {}, output = "", truncated=truncated or nil }
end

function M.reboot(send, sleep, reboot)
  send()
  sleep(0.5)
  reboot()
end

local function handle(session, msg, io)
  if type(msg) ~= "table" then
    return nil
  end
  if msg.type == "eval" then
    local result = M.eval(session, msg.code or "", io.clock)
    result.type = "result"
    result.id = msg.id
    return result
  end
  if msg.type == "write" then
    local result = M.write_file(io.fs, msg.path, msg.content)
    result.type = "result"
    result.id = msg.id
    return result
  end
  if msg.type == "read" then
    local result = M.read_file(io.fs, msg.path)
    result.type = "result"
    result.id = msg.id
    return result
  end
  if msg.type == "reboot" then
    return { type = "result", id = msg.id, ok = true, values = {}, output = "", reboot = true }
  end
  if msg.type == "zero" then
    session.latched = true
    if session.state ~= nil then
      session.state.emergency = true
    end
    return nil
  end
  if msg.type == "clear" then
    session.latched = false
    if session.state ~= nil then
      session.state.emergency = false
    end
    return nil
  end
  return nil
end

function M.handle(session,msg,io)
  local ok,result = pcall(handle,session,msg,io)
  if ok then return result end
  return {type="result",id=type(msg)=="table" and msg.id or nil,ok=false,error=tostring(result),values={},output=""}
end

function M.status(session)
  local state = session.state or {}
  local ship = session.ship or {}
  local vx = ship.vx or 0
  local vz = ship.vz or 0
  return {
    type = "status",
    mode = state.mode,
    job = state.job,
    phase = state.phase,
    emergency = state.emergency,
    diagnostic = state.diagnostic,
    altitude = state.altitude,
    hover_rpm = state.hover_rpm,
    x_rpm = state.x_rpm,
    y = ship.y,
    vertical_speed = ship.vy,
    horizontal_speed = math.sqrt(vx * vx + vz * vz),
    heading = ship.heading,
    su = session.su,
    devices = session.cfg and session.cfg.names,
    diag_elevation = state.diag_elevation,
  }
end

return M
