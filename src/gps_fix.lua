local M = {}

function M.horizontal(x, y, z)
  if x == nil then
    return nil
  end
  return x, z
end

return M
