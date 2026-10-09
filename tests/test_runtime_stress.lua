package.path = "src/?.lua;" .. package.path
local A = dofile("tests/assert.lua")
package.loaded.runtime = nil
local runtime = require("runtime")
local stress = require("stress")
local real_clock, now = os.clock, 0
os.clock = function() return now end
local actual, devices = {}, {}
for _, name in ipairs({"rsc6", "rsc7", "rsc8", "rsc9", "rsc10", "rsc11"}) do
  actual[name] = 0
  devices[name] = {
    getTargetSpeed = function() return actual[name] end,
    setTargetSpeed = function(rpm)
      actual[name] = rpm
      if stress.consumed({rsc=actual}) > stress.USABLE then
        error("actuator transition overstressed the shaft")
      end
    end,
  }
end
local function apply(rsc)
  return runtime.apply({rsc=rsc, relays={}}, devices, {budget=stress.USABLE})
end
local ok, failure = pcall(function()
  -- Old elevation occupies 416000 SU, while the new request would occupy
  -- 43200 SU. Runtime holds the old elevation but advances the forward unit.
  actual.rsc11 = 25950
  apply({rsc11=26000,rsc10=0})
  local applied = apply({rsc11=200,rsc10=10000})
  A.eq(applied.rsc.rsc11, 26000, "elevation hold is respected")
  A.eq(applied.rsc.rsc10, actual.rsc10, "returned output reflects applied target")
  if actual.rsc10 >= 10000 then error("forward increase must wait for held lift to free stress") end
  now = 2
  applied = apply({rsc11=200,rsc10=10000})
  A.eq(applied.rsc.rsc11, 25901, "elevation changes in bounded steps")
  -- Move a near-full allocation from forward propulsion to elevation. Every
  -- hardware write must remain safe, including the intermediate write order.
  now = 4
  actual.rsc11, actual.rsc10 = 19000, 31000
  applied = apply({rsc11=26000,rsc10=0})
  if stress.consumed(applied) > stress.USABLE then error("applied budget exceeded") end

  package.loaded.runtime = nil
  runtime = require("runtime")
  actual.rsc11, actual.rsc10 = 19000, 31000
  local normal_forward = devices.rsc10.setTargetSpeed
  devices.rsc10.setTargetSpeed = function() error("forward reduction failed") end
  local succeeded = pcall(apply, {rsc11=26000,rsc10=0})
  A.eq(succeeded, false, "failed reduction is reported")
  A.eq(actual.rsc11, 19000, "load cannot increase after a failed reduction")
  devices.rsc10.setTargetSpeed = normal_forward
  apply({rsc11=26000,rsc10=0})
  A.eq(actual.rsc10, 0, "failed reduction is retried")

  -- Reconcile measured stress against actual held targets, not the last request.
  local measured = stress.consumed({rsc=actual}) + 1000
  local room = stress.budget(measured,stress.CAPACITY,stress.consumed({rsc=actual}))
  applied = runtime.apply({rsc={rsc11=100,rsc10=10000},relays={}}, devices,
    {measured=measured,capacity=stress.CAPACITY})
  if stress.consumed(applied)>room then error("external shaft load not reserved") end

  applied = runtime.apply({rsc={rsc11=20000,rsc10=10000},relays={}}, devices,
    {measured=0,capacity=0})
  A.eq(stress.consumed(applied),0,"known zero shaft capacity permits no load")
  A.eq(actual.rsc11,0,"loss of all capacity stops held elevation immediately")
end)
os.clock = real_clock
if not ok then error(failure) end
