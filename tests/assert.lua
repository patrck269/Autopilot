local M = {}

function M.eq(actual, expected, msg)
  if actual ~= expected then
    error(msg .. ": expected " .. tostring(expected) .. " got " .. tostring(actual), 2)
  end
end

function M.near(actual, expected, tol, msg)
  if math.abs(actual - expected) > tol then
    error(msg .. ": expected " .. tostring(expected) .. " got " .. tostring(actual), 2)
  end
end

return M
