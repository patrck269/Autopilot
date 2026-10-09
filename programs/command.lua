local program = shell.getRunningProgram()
local dir = fs.getDir(program)
package.path = fs.combine(dir, "src") .. "/?.lua;" .. package.path

local command_ui = require("command_ui")
local command_status = require("command_status")
local views = require("views")
local config = require("config")
local startup = require("startup")
local engine_tick = require("engine_tick")
local runtime = require("runtime")
local protocol = require("protocol")
local monitors = require("monitors")
local mfd = require("mfd")
local shell_mod = require("shell")
local link_mod = require("link")
local frame = require("frame")
local mix = require("mix")
local stress_mod = require("stress")

local cfg = config.default()
local state = engine_tick.new_state()
local ui = command_ui.new()

local MODEM_SIDE = {
  wired_modem = "back",
}

local function wireless_modem_names()
  local names = {}
  if peripheral.getNames == nil then
    return names
  end
  local listed = peripheral.getNames()
  for i = 1, #listed do
    local name = listed[i]
    if peripheral.getType(name) == "modem" then
      local modem = peripheral.wrap(name)
      if modem ~= nil and modem.isWireless() then
        names[#names + 1] = name
      end
    end
  end
  return names
end

local function open_ender_modems()
  local names = wireless_modem_names()
  for i = 1, #names do
    local name = names[i]
    rednet.open(name)
  end
  return names
end

rednet.open("back")
open_ender_modems()

local function present_map()
  local found = {}
  local wireless = open_ender_modems()
  for key, network_name in pairs(cfg.names) do
    if key == "ender_modem" then
      if #wireless > 0 or peripheral.isPresent(network_name) then
        found[key] = true
      end
    else
      local probe = MODEM_SIDE[key] or network_name
      if peripheral.isPresent(probe) then
        found[key] = true
      end
    end
  end
  return found
end

local missing = startup.missing(present_map(), config.required_names(cfg))
local ready = #missing == 0

local last_sample_at = os.clock()
local function collect_ship()
  local now = os.clock()
  local dt = math.max(0.001, math.min(now - last_sample_at, 0.25))
  last_sample_at = now
  local pos = ship.getWorldspacePosition()
  local vel = ship.getVelocity()
  local quat = ship.getQuaternion()
  local omega = ship.getAngularVelocity()
  local ok, sample = pcall(frame.sample, pos, vel, quat, omega, dt, cfg.frame)
  if ok then
    return sample
  end
  local pitch, yaw, roll = quat:toEuler()
  return {
    x = pos.x, y = pos.y, z = pos.z,
    vx = vel.x, vy = vel.y, vz = vel.z,
    pitch = pitch, roll = roll, heading = yaw,
    pitch_rate = omega.x, roll_rate = omega.z, yaw_rate = omega.y,
    dt = dt,
  }
end

local function wrap_devices()
  local devices = {}
  for key, network_name in pairs(cfg.names) do
    if key ~= "wired_modem" and key ~= "ender_modem" then
      devices[key] = peripheral.wrap(network_name)
    end
  end
  return devices
end

local devices = wrap_devices()
local session = shell_mod.new_session(state, cfg, devices)
session.engine_tick = engine_tick
session.runtime = runtime
session.config = config
session.protocol = protocol
local stress_gauge = devices.stressometer
local elevation_device = devices.rsc11
local speed_gauge = devices.speedometer

local screens = {}
local function attach_monitors()
  screens = {}
  local found = { peripheral.find("monitor") }
  local list = {}
  for _, mon in ipairs(found) do
    mon.setTextScale(0.5)
    local w, h = mon.getSize()
    local name = peripheral.getName(mon)
    list[#list + 1] = { name = name, w = w, h = h }
    screens[name] = { mon = mon, w = w, h = h }
  end
  table.sort(list, function(a, b)
    return a.name < b.name
  end)
  return monitors.assign(list)
end

local pages = attach_monitors()

local function refresh_peripherals()
  open_ender_modems()
  devices = wrap_devices()
  session.devices = devices
  stress_gauge = devices.stressometer
  elevation_device = devices.rsc11
  speed_gauge = devices.speedometer
  missing = startup.missing(present_map(), config.required_names(cfg))
  ready = #missing == 0
  local assigned = attach_monitors()
  for name, page in pairs(assigned) do
    if pages[name] == nil then
      pages[name] = page
    end
  end
  for name in pairs(pages) do
    if screens[name] == nil then
      pages[name] = nil
    end
  end
end

local PALETTE = {
  green = colors.green,
  gray = colors.gray,
  red = colors.red,
  black = colors.black,
  white = colors.white,
}

local function paint_tabs(mon, w, h, page)
  for _, control in ipairs(mfd.controls(w, h)) do
    local bg = colors.blue
    if control.page == page then
      bg = colors.lime
    end
    mon.setBackgroundColor(bg)
    mon.setTextColor(colors.black)
    local label = control.label
    if #label > control.w then
      label = string.sub(label, 1, control.w)
    end
    local pad = control.w - #label
    local left = math.floor(pad / 2)
    local line = string.rep(" ", left) .. label .. string.rep(" ", pad - left)
    local tall = control.h or 1
    for dy = 0, tall - 1 do
      mon.setCursorPos(control.x, control.y + dy)
      if dy == 0 then
        mon.write(line)
      else
        mon.write(string.rep(" ", control.w))
      end
    end
  end
end

local function shaft_rpm()
  if speed_gauge ~= nil and speed_gauge.getSpeed ~= nil then
    return speed_gauge.getSpeed()
  end
  return 0
end

local function draw_monitors(outputs, sample, stress)
  local groups = views.engines(outputs, shaft_rpm())
  for name, screen in pairs(screens) do
    local mon = screen.mon
    local w, h = screen.w, screen.h
    local page = pages[name] or "Systems"
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    for row = 1, h - 2 do
      mon.setBackgroundColor(colors.black)
      mon.setCursorPos(1, row)
      mon.write(string.rep(" ", w))
    end
    mon.setCursorPos(1, 1)
    mon.setBackgroundColor(colors.lightBlue)
    mon.setTextColor(colors.white)
    mon.write(page)
    if not ready then
      mon.setBackgroundColor(colors.red)
      mon.setCursorPos(1, 3)
      mon.write("missing " .. table.concat(missing, " "))
    elseif page == "Flight" then
      local figure = views.flight(sample, outputs)
      mon.setBackgroundColor(colors.black)
      mon.setTextColor(colors.white)
      mon.setCursorPos(1, 3)
      mon.write(string.format("X %0.2f  Y %0.2f  Z %0.2f", figure.vx, figure.vy, figure.vz))
      mon.setCursorPos(1, 4)
      mon.write(string.format("rotation %0.3f  Bearing %0.2f", figure.rotation, figure.bearing))
      local col = 1
      local row = 6
      for _, thruster in ipairs(figure.thrusters) do
        mon.setCursorPos(col, row)
        mon.setBackgroundColor(PALETTE[thruster.color])
        mon.setTextColor(colors.black)
        mon.write(" " .. thruster.label .. " ")
        col = col + #thruster.label + 3
        if col > w - 8 then
          col = 1
          row = row + 2
        end
      end
    elseif page == "Navigation" then
      local figure = views.navigation({
        x = sample.x, y = sample.y, z = sample.z,
        vx = sample.vx, vy = sample.vy, vz = sample.vz,
        heading = sample.heading,
        mode = state.mode,
        waypoint_x = state.waypoint_x,
        waypoint_z = state.waypoint_z,
      })
      mon.setBackgroundColor(colors.black)
      mon.setTextColor(colors.lime)
      mon.setCursorPos(1, 3)
      mon.write(figure.compass)
      mon.setTextColor(colors.white)
      mon.setCursorPos(1, 5)
      mon.write(string.format("alt %0.1f  spd %0.2f", figure.altitude, figure.overall))
      mon.setCursorPos(1, 6)
      mon.write(string.format("Bearing %0.2f  drift %0.2f", figure.bearing, figure.drift))
      mon.setCursorPos(1, 7)
      local eta = "n/a"
      if figure.eta ~= nil then
        eta = string.format("%0.1fs", figure.eta)
      end
      mon.write("eta " .. eta)
    elseif page == "Engines" then
      local row = 3
      for _, group in ipairs(groups) do
        mon.setCursorPos(1, row)
        mon.setBackgroundColor(colors.gray)
        mon.setTextColor(colors.white)
        mon.write(group.type)
        row = row + 1
        mon.setBackgroundColor(colors.black)
        for _, item in ipairs(group.devices) do
          mon.setCursorPos(1, row)
          mon.write(item.name .. " " .. tostring(item.rpm))
          row = row + 1
        end
      end
      mon.setCursorPos(1, row)
      mon.setBackgroundColor(colors.brown)
      mon.write("SU consumed " .. tostring(stress.consumed))
      row = row + 1
      mon.setCursorPos(1, row)
      mon.write("SU remaining " .. tostring(stress.remaining))
      row = row + 1
      mon.setCursorPos(1, row)
      mon.setBackgroundColor(colors.black)
      mon.write("X axis propellers " .. string.format("%0.1f", stress.x_axis_propellers))
      row = row + 1
      mon.setCursorPos(1, row)
      mon.write("Z axis propellers " .. string.format("%0.1f", stress.z_axis_propellers))
      row = row + 1
      mon.setCursorPos(1, row)
      mon.write("RCS " .. string.format("%0.1f", stress.rcs))
    elseif page == "Emergency" then
      local diagram = views.emergency(outputs)
      local top = 3
      local bottom = math.max(top + 2, h - 3)
      local left = 1
      local right = math.max(left + 8, w - 8)
      for _, part in ipairs(diagram) do
        local px = left + math.floor(part.x * (right - left))
        local py = top + math.floor(part.y * (bottom - top))
        if px > w - #part.label then
          px = w - #part.label
        end
        if px < 1 then
          px = 1
        end
        mon.setCursorPos(px, py)
        mon.setBackgroundColor(PALETTE[part.color])
        mon.setTextColor(colors.black)
        mon.write(part.label)
      end
    else
      mon.setBackgroundColor(colors.black)
      mon.setTextColor(colors.lime)
      mon.setCursorPos(1, 3)
      if ready then
        mon.write("All peripherals present")
      end
    end
    paint_tabs(mon, w, h, page)
  end
end

local function fill(x, y, w, h, bg)
  term.setBackgroundColor(bg)
  for row = 0, h - 1 do
    term.setCursorPos(x, y + row)
    term.write((" "):rep(w))
  end
end

local function text(x, y, value, fg, bg, maxW)
  if maxW ~= nil and #value > maxW then
    value = string.sub(value, 1, maxW)
  end
  term.setCursorPos(x, y)
  term.setTextColor(fg)
  term.setBackgroundColor(bg)
  term.write(value)
end

local function describe(message)
  if message == nil then
    if ui.field ~= nil then
      return "Typing " .. ui.field .. ": " .. ui.buffer
    end
    return "Ready"
  end
  if message.type == "stick" then
    local parts = {}
    if message.x > 0 then parts[#parts + 1] = "forward" end
    if message.x < 0 then parts[#parts + 1] = "back" end
    if message.y > 0 then parts[#parts + 1] = "right" end
    if message.y < 0 then parts[#parts + 1] = "left" end
    if message.z > 0 then parts[#parts + 1] = "up" end
    if message.z < 0 then parts[#parts + 1] = "down" end
    if #parts == 0 then
      return "Stick released"
    end
    return "Stick " .. table.concat(parts, " ")
  end
  if message.type == "set_mode" then
    return "Mode " .. message.mode
  end
  if message.type == "set_profile" then
    return "Profile " .. message.profile
  end
  if message.type == "set_altitude" then
    return "Altitude " .. tostring(message.y)
  end
  if message.type == "set_bearing" then
    return "Bearing " .. string.format("%0.1f", views.wrap_bearing(message.bearing))
  end
  if message.type == "set_speed" then
    return "Speed " .. tostring(message.speed)
  end
  if message.type == "set_waypoint" then
    return "Waypoint " .. tostring(message.x) .. ", " .. tostring(message.z)
  end
  if message.type == "emergency" then
    return "Emergency stop"
  end
  if message.type == "clear_emergency" then
    return "Emergency cleared"
  end
  if message.type == "cancel_jobs" then
    return "Cancel jobs"
  end
  return message.type
end

local function draw_guide(status_line, guide)
  local width, height = term.getSize()
  term.setBackgroundColor(colors.black)
  term.clear()

  fill(1, 1, width, 1, colors.lightBlue)
  text(2, 1, "SHIP COMMAND", colors.white, colors.lightBlue)
  if guide ~= nil then
    fill(1, 2, width, 1, colors.green)
    local altitude = guide.altitude
    if ui.entered_altitude ~= nil then
      altitude = ui.entered_altitude
    end
    local live = "mode " .. tostring(guide.mode)
      .. " alt " .. tostring(altitude)
      .. " spd " .. tostring(guide.speed)
      .. " SU consumed " .. tostring(guide.su)
    if guide.su_remaining ~= nil then
      live = live .. " SU remaining " .. tostring(guide.su_remaining)
    end
    text(2, 2, live, colors.black, colors.green, width - 2)
  end

  local leftW = math.floor(width * 0.55)
  local rightX = leftW + 2
  local rightW = width - rightX
  local leftText = leftW - 2
  local rightText = rightW - 2
  fill(1, 3, leftW, 6, colors.gray)
  text(2, 3, "STICK", colors.white, colors.gray, leftText)
  text(2, 4, "Left / Right  back / forward", colors.black, colors.gray, leftText)
  text(2, 5, "A / D         left / right", colors.black, colors.gray, leftText)
  text(2, 6, "Space / Up    up", colors.black, colors.gray, leftText)
  text(2, 7, "Shift / Down  down", colors.black, colors.gray, leftText)

  fill(rightX, 3, rightW, 6, colors.blue)
  text(rightX + 1, 3, "MODES", colors.white, colors.blue, rightText)
  text(rightX + 1, 4, "M  Manual", colors.yellow, colors.blue, rightText)
  text(rightX + 1, 5, "S  Semi-automatic", colors.lime, colors.blue, rightText)
  text(rightX + 1, 6, "U  Automatic", colors.orange, colors.blue, rightText)
  text(rightX + 1, 7, "W  Cruise / warp", colors.white, colors.blue, rightText)
  text(rightX + 1, 8, "K  Cancel jobs", colors.white, colors.blue, rightText)

  fill(1, 10, leftW, 6, colors.lightGray)
  text(2, 10, "ENTER A NUMBER", colors.black, colors.lightGray, leftText)
  local function entry(row, label, fieldName)
    local active = ui.field == fieldName
    local bg = colors.lightGray
    local fg = colors.black
    local value = label
    if active then
      bg = colors.white
      fg = colors.black
      value = label .. " " .. ui.buffer .. "_"
    end
    fill(2, row, leftText, 1, bg)
    text(2, row, value, fg, bg, leftText)
  end
  entry(11, "Y Altitude", "y")
  entry(12, "B Bearing", "bearing")
  entry(13, "V Speed", "speed")
  entry(14, "X Waypoint", "x")
  entry(15, "Z Waypoint", "z")

  fill(rightX, 10, rightW, 6, colors.red)
  text(rightX + 1, 10, "SAFETY", colors.white, colors.red, rightText)
  text(rightX + 1, 12, "E  Emergency stop", colors.white, colors.red, rightText)
  text(rightX + 1, 13, "C  Clear emergency", colors.white, colors.red, rightText)

  fill(1, height, width, 1, colors.black)
  local line = status_line
  if #line > width - 1 then
    line = string.sub(line, 1, width - 1)
  end
  text(2, height, line, colors.white, colors.black)
end

local tick_timer = os.startTimer(0.05)
local repeat_timer = os.startTimer(0.1)
local pending = {}
local last_stick_at = -math.huge
local status_line = "Ready"
local guide = nil
if not ready then
  status_line = "missing " .. table.concat(missing, " ")
end

local function queue(message)
  if message == nil then
    return
  end
  if type(message) == "table" and message.type == "status" then
    return
  end
  if message.type == "stick" then
    last_stick_at = os.clock()
  end
  pending = shell_mod.ingest(session, pending, message, protocol.enqueue, function(command)
    shell_mod.repeat_wired(command, function(side, channel, reply, payload)
      peripheral.call(side, "transmit", channel, reply, payload)
    end, cfg.names.wired_modem, os.getComputerID())
  end)
end

local last_outputs = nil
local last_sample = nil
local last_stress = nil
local paint_timer = nil
local painted_guide = nil
local painted_monitors = nil

local function guide_picture()
  local alt = ""
  local mode = ""
  local spd = ""
  local su = ""
  if guide ~= nil then
    alt = string.format("%.1f", tonumber(guide.altitude) or 0)
    mode = tostring(guide.mode)
    spd = string.format("%.1f", tonumber(guide.speed) or 0)
    su = string.format("%.0f", tonumber(guide.su) or 0)
  end
  return table.concat({
    status_line,
    tostring(ui.field),
    ui.buffer or "",
    tostring(ui.entered_altitude),
    mode,
    alt,
    spd,
    su,
    ready and "1" or "0",
  }, "|")
end

local function monitor_picture(outputs, sample, stress)
  if outputs == nil or sample == nil then
    return ""
  end
  local rpm11 = 0
  local rpm10 = 0
  if outputs.rsc ~= nil then
    rpm11 = math.floor((outputs.rsc.rsc11 or 0) >= 0 and (outputs.rsc.rsc11 or 0) or -(outputs.rsc.rsc11 or 0))
    if (outputs.rsc.rsc11 or 0) < 0 then
      rpm11 = -rpm11
    end
    rpm10 = math.floor((outputs.rsc.rsc10 or 0) >= 0 and (outputs.rsc.rsc10 or 0) or -(outputs.rsc.rsc10 or 0))
    if (outputs.rsc.rsc10 or 0) < 0 then
      rpm10 = -rpm10
    end
  end
  local su = 0
  if stress ~= nil and stress.consumed ~= nil then
    su = math.floor(stress.consumed >= 0 and stress.consumed or -stress.consumed)
    if stress.consumed < 0 then
      su = -su
    end
  end
  local page_names = {}
  for name, page in pairs(pages) do
    page_names[#page_names + 1] = name .. "=" .. tostring(page)
  end
  table.sort(page_names)
  return table.concat({
    string.format("%.1f", sample.y or 0),
    string.format("%.1f", sample.vy or 0),
    string.format("%.1f", sample.vx or 0),
    string.format("%.1f", sample.vz or 0),
    string.format("%.2f", sample.heading or 0),
    tostring(rpm11),
    tostring(rpm10),
    tostring(su),
    tostring(state.mode),
    ready and "1" or "0",
    table.concat(missing, ","),
    table.concat(page_names, ","),
    outputs.relays ~= nil and outputs.relays.relay6 and "1" or "0",
  }, "|")
end

local function request_paint()
  if paint_timer == nil then
    paint_timer = os.startTimer(0)
  end
end

local function paint_if_changed()
  local guide_now = guide_picture()
  if guide_now ~= painted_guide then
    draw_guide(status_line, guide)
    painted_guide = guide_now
  end
  local monitors_now = monitor_picture(last_outputs, last_sample, last_stress)
  if monitors_now ~= "" and monitors_now ~= painted_monitors then
    draw_monitors(last_outputs, last_sample, last_stress)
    painted_monitors = monitors_now
  end
end

local function note_keys(message)
  queue(message)
  if message ~= nil then
    status_line = describe(message)
  elseif ui.field ~= nil then
    status_line = describe(nil)
  end
  request_paint()
end

draw_guide(status_line, guide)
painted_guide = guide_picture()

local function flight_loop()
  while true do
    local event, a, b, c = os.pullEvent()
    if event == "rednet_message" then
      queue(b)
      local applied = command_status.apply(b)
      if applied ~= nil then
        guide = applied
        request_paint()
      end
    elseif event == "key" then
      local name = keys.getName(a)
      local message
      ui, message = command_ui.key(ui, name, true, b)
      note_keys(message)
    elseif event == "key_up" then
      local name = keys.getName(a)
      local message
      ui, message = command_ui.key(ui, name, false)
      note_keys(message)
    elseif event == "term_resize" then
      painted_guide = nil
      request_paint()
    elseif event == "peripheral" or event == "peripheral_detach" then
      refresh_peripherals()
      if not ready then
        status_line = "missing " .. table.concat(missing, " ")
      end
      painted_guide = nil
      painted_monitors = nil
      request_paint()
    elseif event == "monitor_touch" then
      local screen = screens[a]
      if screen ~= nil then
        local selected = mfd.hit(screen.w, screen.h, b, c)
        if selected ~= nil then
          local other = nil
          for name, page in pairs(pages) do
            if name ~= a and page == selected then
              other = name
              break
            end
          end
          if other ~= nil then
            pages = monitors.swap(pages, a, other)
          else
            pages[a] = selected
          end
          request_paint()
        end
      end
    elseif event == "timer" and a == repeat_timer then
      local repeated = command_ui.repeat_stick(ui)
      if repeated ~= nil then
        last_stick_at = os.clock()
        queue(repeated)
      end
      repeat_timer = os.startTimer(0.1)
    elseif event == "timer" and a == tick_timer then
      local sample = collect_ship()
      local consumed = 0
      local capacity = nil
      if stress_gauge ~= nil and stress_gauge.getStress ~= nil then
        consumed = stress_gauge.getStress()
      end
      if stress_gauge ~= nil and stress_gauge.getStressCapacity ~= nil then
        capacity = stress_gauge.getStressCapacity()
      end
      local elevation_rpm = nil
      if elevation_device ~= nil and elevation_device.getTargetSpeed ~= nil then
        elevation_rpm = elevation_device.getTargetSpeed()
      end
      session.ship = sample
      session.su = consumed
      session.cfg = cfg
      session.devices = devices
      session.state = state
      local commands = pending
      pending = {}
      for i = 1, #commands do
        shell_mod.apply_latch(session, state, commands[i])
      end
      shell_mod.apply_latch(session, state, nil)
      local outputs
      local status
      state, outputs, status = engine_tick.tick(state, {
        ship = sample,
        commands = commands,
        su = consumed,
        su_capacity = capacity,
        ready = ready,
        stick_fresh = os.clock() - last_stick_at <= (cfg.stick_timeout or 0.35),
        config = cfg,
        current_elevation_rpm = elevation_rpm,
      })
      session.state = state
      outputs = runtime.apply(outputs, devices, {measured=consumed, capacity=capacity})
      state.modeled_su = stress_mod.consumed(outputs)
      local stress = views.stress(consumed, capacity or 0, outputs)
      status.su = stress.consumed
      status.su_remaining = stress.remaining
      status.su_x_axis_propellers = stress.x_axis_propellers
      status.su_z_axis_propellers = stress.z_axis_propellers
      status.su_rcs = stress.rcs
      status.speed = status.horizontal_speed
      status.type = "status"
      rednet.broadcast(status)
      last_outputs = outputs
      last_sample = sample
      last_stress = stress
      local applied = command_status.apply(status)
      if applied ~= nil then
        guide = applied
      end
      request_paint()
      tick_timer = os.startTimer(0.05)
    elseif event == "timer" and a == paint_timer then
      paint_timer = nil
      paint_if_changed()
    end
  end
end

local function shell_loop()
  local open = function(path, mode)
    return fs.open(path, mode)
  end
  local token = link_mod.read_text(open, "debug.token")
  local url = link_mod.read_text(open, "debug.url")
  if not shell_mod.should_dial(token) or url == nil then
    return
  end
  local next_status = 0
  local function on_message(msg)
    return shell_mod.handle(session, msg, { fs = fs, clock = os.clock })
  end
  local function on_idle()
    if session.busy then
      return nil
    end
    local now = os.clock()
    if now < next_status then
      return nil
    end
    next_status = now + 1
    return shell_mod.status(session)
  end
  while true do
    local ok, err = pcall(function()
      link_mod.serve(url, token, "engine", on_message, on_idle, session)
    end)
    if not ok then
      print(err)
    end
    sleep(5)
  end
end

local ok, failure = pcall(parallel.waitForAll, flight_loop, shell_loop)
session.latched = true
state.emergency = true
pcall(runtime.apply, mix.zero(), devices)
if not ok then
  error(failure, 0)
end
