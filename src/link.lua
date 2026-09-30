local shell_mod = require("shell")

local M = {}

function M.should_dial(token)
  return shell_mod.should_dial(token)
end

function M.read_text(open, path)
  local handle = open(path, "r")
  if handle == nil then
    return nil
  end
  local text = handle.readAll()
  handle.close()
  if type(text) ~= "string" then
    return nil
  end
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then
    return nil
  end
  return text
end

function M.encode(value)
  return textutils.serializeJSON(value)
end

function M.decode(text)
  return textutils.unserializeJSON(text)
end

function M.turn(session, msg, on_message, pull, send, io)
  io = io or {}
  local function deliver(incoming)
    if type(incoming) ~= "table" then
      return
    end
    local reply = on_message(incoming)
    if type(reply) ~= "table" then
      return
    end
    local reboot = reply.reboot
    reply.reboot = nil
    if reboot then
      shell_mod.reboot(function()
        send(reply)
      end, io.sleep, io.reboot)
    else
      send(reply)
    end
  end

  local ok, err = pcall(function()
    deliver(msg)
    if type(session) == "table" and session.busy then
      while true do
        local nxt = pull()
        if nxt == nil then
          break
        end
        deliver(nxt)
      end
    end
  end)
  if type(session) == "table" and session.busy then
    shell_mod.release(session)
  end
  if not ok then
    error(err, 0)
  end
end

function M.serve(url, token, role, on_message, on_idle, session)
  local ws, err = http.websocket(url)
  if not ws then
    error(err or "websocket failed", 0)
  end
  ws.send(M.encode({
    type = "hello",
    id = os.getComputerID(),
    role = role,
    label = os.getComputerLabel(),
    token = token,
  }))
  local ready_raw = ws.receive(5)
  if ready_raw == nil then
    ws.close()
    error("no ready", 0)
  end
  local ready = M.decode(ready_raw)
  if type(ready) ~= "table" or ready.type ~= "ready" then
    ws.close()
    error("not ready", 0)
  end
  while true do
    local raw = ws.receive(0.5)
    if raw ~= nil then
      local msg = M.decode(raw)
      if type(msg) == "table" then
        M.turn(session, msg, on_message, function()
          local nxt = ws.receive(0)
          if nxt == nil then
            return nil
          end
          return M.decode(nxt)
        end, function(reply)
          ws.send(M.encode(reply))
        end, { sleep = sleep, reboot = os.reboot })
      end
    elseif on_idle ~= nil then
      local extra = on_idle()
      if extra ~= nil then
        ws.send(M.encode(extra))
      end
    end
  end
end

return M
