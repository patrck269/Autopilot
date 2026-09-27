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
    pitch_rate = omega.x, roll_rate = omega.z,
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

local function draw(status, outputs)
  for name, screen in pairs(screens) do
    local mon = screen.mon
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    mon.clear()
    mon.setCursorPos(1, 1)
    local page = pages[name] or "Systems"
    mon.write(page)
    mon.setCursorPos(1, 2)
    if not ready then
      mon.write("missing " .. table.concat(missing, " "))
    elseif page == "Flight" then
      mon.write("mode " .. tostring(status.mode))
      mon.setCursorPos(1, 3)
      mon.write("alt " .. tostring(status.altitude))
      mon.setCursorPos(1, 4)
      mon.write("vs " .. tostring(status.vertical_speed))
      mon.setCursorPos(1, 5)
      mon.write("hs " .. tostring(status.horizontal_speed))
      mon.setCursorPos(1, 6)
      mon.write("hdg " .. tostring(status.heading))
    elseif page == "Engines" then
      local rpm = 0
      local gauge = peripheral.wrap(cfg.names.speedometer)
      if gauge ~= nil and gauge.getSpeed ~= nil then
        rpm = gauge.getSpeed()
      end
      mon.write("rpm " .. tostring(rpm))
      mon.setCursorPos(1, 3)
      mon.write("su " .. tostring(status.su))
      mon.setCursorPos(1, 4)
      mon.write("x " .. tostring(outputs.rsc.rsc10))
      mon.setCursorPos(1, 5)
      mon.write("elev " .. tostring(outputs.rsc.rsc11))
    elseif page == "Navigation" then
      mon.write("wp " .. tostring(state.waypoint_x) .. " " .. tostring(state.waypoint_z))
      mon.setCursorPos(1, 3)
      mon.write(state.profile)
    elseif page == "Emergency" then
      mon.write("outage " .. tostring(status.outage))
      mon.setCursorPos(1, 3)
      mon.write("latch " .. tostring(state.emergency))
    else
      mon.write("missing " .. table.concat(missing, " "))
    end
    mon.setCursorPos(1, screen.h)
    local slot = math.floor(screen.w / 4)
    if slot >= 1 then
      for i = 1, 4 do
        mon.setCursorPos((i - 1) * slot + 1, screen.h)
        mon.write(tostring(i))
      end
    end
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
      local target = mfd.hit(screen.w, screen.h, b, c, ordered_names)
      if target ~= nil then
        pages = monitors.swap(pages, a, target)
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
    draw(status, outputs)
    last_outputs = outputs
    tick_timer = os.startTimer(0.05)
  end
end
