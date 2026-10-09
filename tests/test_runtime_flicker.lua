package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
local real_clock, now = os.clock, 0
os.clock = function() return now end
local ok, failure = pcall(function()
  for _, scenario in ipairs({"slowdown", "slowdown-budget", "ramp", "reverse", "zero", "budget"}) do
    package.loaded.runtime = nil
    local runtime = require("runtime")
    local actual, score, peak, writes = 5000, 0, 0, 0
    now = 0
    local device = {
      getTargetSpeed = function() return actual end,
      setTargetSpeed = function(rpm)
        if rpm == actual then return end
        -- Installed Create 6.0.8: removeSource stops the powered controller;
        -- attachKinetics restarts it. Each transition adds five points.
        if actual ~= 0 then score = score + 5 end
        if rpm ~= 0 then score = score + 5 end
        peak = math.max(peak, score)
        if score > 128 then error(scenario .. " destroys controller: " .. score) end
        actual = rpm
        writes = writes + 1
      end,
    }
    local devices = {rsc11=device}
    for _, name in ipairs({"rsc6","rsc7","rsc8","rsc9","rsc10"}) do
      devices[name] = {getTargetSpeed=function() return 0 end, setTargetSpeed=function() end}
    end
    local function apply(wanted, options)
      return runtime.apply({rsc={rsc11=wanted,rsc6=0,rsc7=0,rsc8=0,rsc9=0,rsc10=0},relays={}}, devices, options)
    end
    for i = 1, 2000 do
      now = i * 0.05
      score = math.max(0, score - 1)
      if scenario == "slowdown" or scenario == "slowdown-budget" then
        apply(math.max(430, 5000 - i * 20), scenario == "slowdown-budget" and {budget=100000} or nil)
        if actual == 0 then error("ordinary slowdown cut elevation") end
      elseif scenario == "ramp" then
        apply(math.min(20000, i * 20))
      elseif scenario == "reverse" then
        apply(i % 2 == 0 and 5000 or -5000)
      elseif scenario == "zero" then
        apply(i % 2 == 0 and 0 or 5000)
        if i % 2 == 0 then A.eq(actual, 0, "emergency stop is immediate") end
      else
        apply(5000, {budget=i % 2 == 0 and 0 or 100000})
        if i % 2 == 0 then A.eq(actual, 0, "capacity loss is immediate") end
      end
    end
    if writes < 2 then error(scenario .. " did not exercise target changes") end
    if scenario == "slowdown" or scenario == "slowdown-budget" then A.eq(actual,430,"slowdown reaches hover") end
    -- Calls without another game tick must not refill the flicker allowance.
    for i = 1, 1000 do
      apply(0)
      apply(5000)
    end
    apply(0)
    A.eq(actual,0,"zero remains available after exhausting allowance")
    now = now + 10
    score = 0
    for i = 1, 100 do
      now = now + 0.05
      score = math.max(0,score-1)
      apply(430)
    end
    A.eq(actual,430,"controller resumes after flicker decays")
    print(scenario .. " peak flicker " .. peak)
  end
end)
os.clock = real_clock
if not ok then error(failure) end
