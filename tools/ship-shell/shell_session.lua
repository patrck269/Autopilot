-- Computer side of the bridge file test. Speaks a length-prefixed request
-- protocol on stdin and applies each message with the shipped shell.
-- The directory in arg[2] is only the filesystem edge: replace order stays
-- in shell.write_file, and reboot order stays in shell.reboot.

local src = arg[1]
local root = arg[2]
if type(src) ~= "string" or type(root) ~= "string" then
  io.stderr:write("shell_session.lua needs a source directory and a file directory\n")
  os.exit(1)
end

package.path = src .. "/?.lua;" .. package.path
local shell = require("shell")
local link = require("link")

io.stdout:setvbuf("no")
io.stdin:setvbuf("no")

local ops = {}

local function physical(path)
  if type(path) ~= "string" or path == "" or path:find("[/\\]") or path:find("..", 1, true) then
    error("bad path", 0)
  end
  return root .. "/" .. path
end

local fs = {
  open = function(path, mode)
    ops[#ops + 1] = mode .. " " .. path
    local raw = io.open(physical(path), mode == "w" and "wb" or "rb")
    if raw == nil then
      return nil
    end
    return {
      write = function(text)
        raw:write(text)
      end,
      readAll = function()
        return raw:read("*a")
      end,
      close = function()
        raw:close()
      end,
    }
  end,
  exists = function(path)
    local raw = io.open(physical(path), "rb")
    if raw == nil then
      return false
    end
    raw:close()
    return true
  end,
  delete = function(path)
    ops[#ops + 1] = "delete " .. path
    local ok, err = os.remove(physical(path))
    if not ok then
      error(err, 0)
    end
  end,
  move = function(from_path, to_path)
    ops[#ops + 1] = "move " .. from_path .. " " .. to_path
    local ok, err = os.rename(physical(from_path), physical(to_path))
    if not ok then
      error(err, 0)
    end
  end,
}

local session = shell.new_session(nil, nil, nil)

local function respond(ok_flag, id, err, content, has_content, reboot_flag, order, op_list)
  io.write(ok_flag and "1\n" or "0\n")
  io.write(id or "", "\n")
  io.write(err or "", "\n")
  io.write(has_content and "1\n" or "0\n")
  local text = content or ""
  io.write(tostring(#text), "\n")
  io.write(text)
  io.write(reboot_flag and "1\n" or "0\n")
  io.write(order or "", "\n")
  io.write(op_list or "", "\n")
  io.flush()
end

local function read_line()
  local line = io.read("*l")
  if line == nil then
    os.exit(0)
  end
  return line
end

io.write("ready\n")
io.flush()

local function write_turn_reply(reply)
  io.write(tostring(reply.id or ""), "\n")
  io.write(reply.ok and "1\n" or "0\n")
  io.write(reply.error or "", "\n")
  local values = reply.values or {}
  io.write(tostring(#values), "\n")
  for i = 1, #values do
    local value = values[i]
    if type(value) == "number" then
      io.write("n\n", tostring(value), "\n")
    elseif type(value) == "boolean" then
      io.write("b\n", tostring(value), "\n")
    else
      io.write("s\n", tostring(value), "\n")
    end
  end
  local text = reply.output or ""
  io.write(tostring(#text), "\n")
  io.write(text)
end

while true do
  local op = read_line()
  if op == "turn" then
    local count = tonumber(read_line()) or 0
    local messages = {}
    for _ = 1, count do
      local kind = read_line()
      local id = read_line()
      local n = tonumber(read_line()) or 0
      local code = ""
      if n > 0 then
        code = io.read(n)
        if code == nil then
          os.exit(0)
        end
      end
      messages[#messages + 1] = { type = kind, id = id, code = code }
    end
    local sent = {}
    local index = 2
    local ran, err = pcall(function()
      link.turn(session, messages[1], function(msg)
        return shell.handle(session, msg, {
          fs = fs,
          clock = function()
            return 0
          end,
        })
      end, function()
        local nxt = messages[index]
        index = index + 1
        return nxt
      end, function(reply)
        sent[#sent + 1] = reply
      end, { sleep = function() end, reboot = function() end })
    end)
    if not ran then
      io.write("err\n")
      io.write(tostring(err), "\n")
      io.flush()
    else
      io.write("ok\n")
      io.write(tostring(#sent), "\n")
      for i = 1, #sent do
        write_turn_reply(sent[i])
      end
      io.flush()
    end
  else
  local id = read_line()
  local path = read_line()
  local n = tonumber(read_line()) or 0
  local body = ""
  if n > 0 then
    body = io.read(n)
    if body == nil then
      os.exit(0)
    end
  end
  ops = {}
  local ran, err = pcall(function()
    local msg = { type = op, id = id, path = path, content = body, code = body }
    local reply = shell.handle(session, msg, {
      fs = fs,
      clock = function()
        return 0
      end,
    })
    if type(reply) ~= "table" then
      respond(false, id, "no reply", nil, false, false, "", table.concat(ops, "|"))
      return
    end
    local reboot_flag = reply.reboot == true
    reply.reboot = nil
    local order = {}
    if reboot_flag then
      shell.reboot(function()
        order[#order + 1] = "send"
      end, function(seconds)
        order[#order + 1] = "sleep " .. tostring(seconds)
      end, function()
        order[#order + 1] = "reboot"
      end)
    end
    respond(
      reply.ok == true,
      reply.id,
      reply.error,
      reply.content,
      reply.content ~= nil,
      reboot_flag,
      table.concat(order, ","),
      table.concat(ops, "|")
    )
  end)
  if not ran then
    respond(false, id, tostring(err), nil, false, false, "", table.concat(ops, "|"))
  end
  end
end
