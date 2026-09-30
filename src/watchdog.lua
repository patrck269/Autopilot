local M = {}

local SILENCE = 3
local PERIOD = 0.2

function M.new()
  return {
    armed = false,
    latched = false,
    engine_id = nil,
    last_status_at = 0,
    last_zero_at = nil,
    link_up = true,
    disarm_after_latch = false,
  }
end

local function clone(state)
  return {
    armed = state.armed,
    latched = state.latched,
    engine_id = state.engine_id,
    last_status_at = state.last_status_at,
    last_zero_at = state.last_zero_at,
    link_up = state.link_up,
    disarm_after_latch = state.disarm_after_latch,
  }
end

local function latch(state, action, now)
  if not state.latched then
    action.broadcast = true
  end
  state.latched = true
  action.write_zero = true
  state.last_zero_at = now
end

function M.step(state, event)
  local next_state = clone(state)
  local action = { write_zero = false, broadcast = nil }
  local now = event.now

  if event.type == "arm" then
    next_state.armed = true
    next_state.engine_id = event.engine_id
    next_state.last_status_at = now
    next_state.link_up = true
    next_state.disarm_after_latch = false
  elseif event.type == "disarm" then
    if next_state.latched then
      next_state.disarm_after_latch = true
    else
      next_state.armed = false
    end
  elseif event.type == "socket_drop" then
    next_state.link_up = false
  elseif event.type == "status" then
    if event.sender == next_state.engine_id and type(event.mode) == "string" then
      if not next_state.latched then
        next_state.last_status_at = now
        if not next_state.link_up then
          next_state.armed = false
        end
      end
    end
  elseif event.type == "zero" then
    latch(next_state, action, now)
  elseif event.type == "tick" then
    if next_state.armed and not next_state.latched and now - next_state.last_status_at >= SILENCE then
      latch(next_state, action, now)
    elseif next_state.latched then
      local due = next_state.last_zero_at == nil or now - next_state.last_zero_at >= PERIOD
      if due then
        action.write_zero = true
        action.broadcast = true
        next_state.last_zero_at = now
      end
    end
  elseif event.type == "clear" or event.type == "clear_emergency" then
    local was = next_state.latched
    next_state.latched = false
    if now ~= nil then
      next_state.last_status_at = now
    end
    if was then
      action.broadcast = false
    end
    if next_state.disarm_after_latch then
      next_state.armed = false
      next_state.disarm_after_latch = false
    end
  else
    error("unknown watchdog event " .. tostring(event.type))
  end

  return next_state, action
end

return M
