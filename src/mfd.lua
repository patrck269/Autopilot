local M = {}

local ROWS = {
  { "Flight", "Navigation", "Engines" },
  { "Emergency", "Systems" },
}

function M.controls(w, h)
  local list = {}
  for row_index, pages in ipairs(ROWS) do
    local y = h - (#ROWS - row_index)
    local x = 1
    for _, page in ipairs(pages) do
      if x <= w then
        list[#list + 1] = {
          page = page,
          label = page,
          x = x,
          y = y,
          w = #page,
        }
      end
      x = x + #page + 1
    end
  end
  return list
end

function M.hit(w, h, x, y)
  for _, control in ipairs(M.controls(w, h)) do
    local last = control.x + control.w - 1
    if y == control.y and x >= control.x and x <= last and last <= w then
      return control.page
    end
  end
  return nil
end

return M
