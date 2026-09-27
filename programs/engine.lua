local program = shell.getRunningProgram()
local dir = fs.getDir(program)
package.path = fs.combine(dir, "src") .. "/?.lua;" .. package.path

local config = require("config")
local startup = require("startup")
local engine_tick = require("engine_tick")
local runtime = require("runtime")
local protocol = require("protocol")
local monitors = require("monitors")
local mfd = require("mfd")
local views = require("views")

local cfg = config.default()
local state = engine_tick.new_state()

local MODEM_SIDE = {
  wired_modem = "back",
  ender_modem = "right",
}

rednet.open("back")
rednet.open("right")

local function present_map()
  local found = {}
  for key, network_name in pairs(cfg.names) do
    local probe = MODEM_SIDE[key] or network_name
    if peripheral.isPresent(probe) then
      found[key] = true
    end
  end
  return found
end

local missing = startup.missing(present_map(), config.required_names(cfg))
local ready = #missing == 0

local function collect_ship()
  local pos = ship.getWorldspacePosition()
  local vel = ship.getVelocity()
  local pitch, yaw, roll = ship.getQuaternion():toEuler()
  local omega = ship.getAngularVelocity()
  return {
    x = pos.x, y = pos.y, z = pos.z,
    vx = vel.x, vy = vel.y, vz = vel.z,
    pitch = pitch, roll = roll, heading = yaw,
    pitch_rate = omega.x, roll_rate = omega.z, yaw_rate = omega.y,
    dt = 0.05,
  }
end

local function wrap_devices()
  local devices = {}
  for key, network_name in pairs(cfg.names) do
    if MODEM_SIDE[key] == nil then
      devices[key] = peripheral.wrap(network_name)
    end
  end
  return devices
end

local screens = {}
local page_names = {}
local function attach_monitors()
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
  local ordered = {}
  for _, item in ipairs(list) do
    ordered[#ordered + 1] = item.name
  end
  page_names = ordered
  return monitors.assign(list), ordered
end

local pages, ordered_names = attach_monitors()

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
    mon.setCursorPos(control.x, control.y)
    mon.write(label .. string.rep(" ", control.w - #label))
  end
end

local function shaft_rpm()
  local gauge = peripheral.wrap(cfg.names.speedometer)
  if gauge ~= nil and gauge.getSpeed ~= nil then
    return gauge.getSpeed()
  end
  return 0
end

local function draw_terminal(groups, su)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  term.setBackgroundColor(colors.gray)
  term.write("ENGINES")
  term.setBackgroundColor(colors.black)
  term.write("  SU " .. tostring(su))
  local row = 3
  for _, group in ipairs(groups) do
    term.setCursorPos(1, row)
    term.setBackgroundColor(colors.lightBlue)
    term.setTextColor(colors.white)
    term.write(group.type)
    row = row + 1
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    for _, item in ipairs(group.devices) do
      term.setCursorPos(1, row)
      term.write("  " .. item.name .. " RPM " .. tostring(item.rpm))
      row = row + 1
    end
  end
end

local function draw(status, outputs, sample)
  local groups = views.engines(outputs, shaft_rpm())
  draw_terminal(groups, status.su)
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
      mon.write(string.format("rot %0.3f  brg %0.2f", figure.rotation, figure.bearing))
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
      mon.write(string.format("brg %0.2f  drift %0.2f", figure.bearing, figure.drift))
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
      mon.write("SU " .. tostring(status.su))
    elseif page == "Emergency" then
      local diagram = views.emergency(outputs)
      local col = 1
      local row = 3
      for _, part in ipairs(diagram) do
        mon.setCursorPos(col, row)
        mon.setBackgroundColor(PALETTE[part.color])
        mon.setTextColor(colors.black)
        mon.write(" " .. part.label .. " ")
        col = col + #part.label + 3
        if col > w - 10 then
          col = 1
          row = row + 2
        end
      end
    else
      mon.setBackgroundColor(colors.black)
      mon.setCursorPos(1, 3)
      mon.write("missing " .. table.concat(missing, " "))
    end
    paint_tabs(mon, w, h, page)
  end
end

if not ready then
  print("missing " .. table.concat(missing, " "))
end

local tick_timer = os.startTimer(0.05)
local pending = nil
local last_outputs = runtime and nil

while true do
  local event, a, b, c = os.pullEvent()
  if event == "rednet_message" then
    pending = protocol.validate(b)
  elseif event == "monitor_touch" then
    local screen = screens[a]
    if screen ~= nil then
      local selected = mfd.hit(screen.w, screen.h, b, c)
      if selected ~= nil then
        pages[a] = selected
      end
    end
  elseif event == "timer" and a == tick_timer then
    local sample = collect_ship()
    local su = 0
    local stress = peripheral.wrap(cfg.names.stressometer)
    if stress ~= nil and stress.getStress ~= nil then
      su = stress.getStress()
    end
    local command = pending
    pending = nil
    local outputs
    local status
    state, outputs, status = engine_tick.tick(state, {
      ship = sample,
      command = command,
      su = su,
      ready = ready,
      stick_fresh = command ~= nil and command.type == "stick",
      config = cfg,
    })
    runtime.apply(outputs, wrap_devices())
    status.speed = status.horizontal_speed
    rednet.broadcast(status)
    draw(status, outputs, sample)
    last_outputs = outputs
    tick_timer = os.startTimer(0.05)
  end
end
