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
  local gauge = peripheral.wrap(cfg.names.speedometer)
  if gauge ~= nil and gauge.getSpeed ~= nil then
    return gauge.getSpeed()
  end
  return 0
end

local function draw_terminal(groups, stress)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  term.setBackgroundColor(colors.gray)
  term.write("ENGINES")
  term.setBackgroundColor(colors.black)
  term.write("  SU consumed " .. tostring(stress.consumed))
  term.write("  SU remaining " .. tostring(stress.remaining))
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

local function draw(status, outputs, sample, stress)
  local groups = views.engines(outputs, shaft_rpm())
  draw_terminal(groups, stress)
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

if not ready then
  print("missing " .. table.concat(missing, " "))
end

local tick_timer = os.startTimer(0.05)
local pending = nil
local last_outputs = runtime and nil

while true do
  local event, a, b, c = os.pullEvent()
  if event == "rednet_message" then
    pending = protocol.keep(pending, b)
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
    local consumed = 0
    local capacity = 0
    local stress_gauge = peripheral.wrap(cfg.names.stressometer)
    if stress_gauge ~= nil and stress_gauge.getStress ~= nil then
      consumed = stress_gauge.getStress()
    end
    if stress_gauge ~= nil and stress_gauge.getStressCapacity ~= nil then
      capacity = stress_gauge.getStressCapacity()
    end
    local elevation_rpm = nil
    local elevation = peripheral.wrap(cfg.names.rsc11)
    if elevation ~= nil and elevation.getTargetSpeed ~= nil then
      elevation_rpm = elevation.getTargetSpeed()
    end
    local command = pending
    pending = nil
    local outputs
    local status
    state, outputs, status = engine_tick.tick(state, {
      ship = sample,
      command = command,
      su = consumed,
      su_capacity = capacity,
      ready = ready,
      stick_fresh = command ~= nil and command.type == "stick",
      config = cfg,
      current_elevation_rpm = elevation_rpm,
    })
    local stress = views.stress(consumed, capacity, outputs)
    status.su = stress.consumed
    status.su_remaining = stress.remaining
    status.su_x_axis_propellers = stress.x_axis_propellers
    status.su_z_axis_propellers = stress.z_axis_propellers
    status.su_rcs = stress.rcs
    runtime.apply(outputs, wrap_devices())
    status.speed = status.horizontal_speed
    rednet.broadcast(status)
    draw(status, outputs, sample, stress)
    last_outputs = outputs
    tick_timer = os.startTimer(0.05)
  end
end
