local M = {}
function M.finite(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
function M.clamp(v, lo, hi)
  if not M.finite(v) then return 0 end
  return math.max(lo, math.min(hi, v))
end
function M.wrap(v)
  if not M.finite(v) then return 0 end
  -- Keep an angle that is already inside the closed interval. Exact pi is a
  -- half turn; the modulo form folds it to -pi.
  if v >= -math.pi and v <= math.pi then
    return v
  end
  return (v + math.pi) % (2 * math.pi) - math.pi
end
function M.atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  if x > 0 then return math.atan(y / x) end
  if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
  if y > 0 then return math.pi / 2 end
  if y < 0 then return -math.pi / 2 end
  return 0
end
return M
