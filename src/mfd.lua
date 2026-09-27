local M = {}

local ROWS = {
  { "Flight", "Navigation", "Engines" },
  { "Emergency", "Systems" },
}

local PAD = 1
local TALL = 2

function M.controls(w, h)
  local list = {}
  local rows = #ROWS
  for row_index, pages in ipairs(ROWS) do
    local height = TALL
    local y = h - (rows - row_index + 1) * height + 1
    local x = 1
    for _, page in ipairs(pages) do
      local width = #page + PAD * 2
      if x <= w and y >= 1 then
        list[#list + 1] = {
          page = page,
          label = page,
          x = x,
          y = y,
          w = width,
          h = height,
        }
      end
      x = x + width + 1
    end
  end
  return list
end

function M.hit(w, h, x, y)
  for _, control in ipairs(M.controls(w, h)) do
    local last_x = control.x + control.w - 1
    local last_y = control.y + control.h - 1
    if x >= control.x and x <= last_x and y >= control.y and y <= last_y and last_x <= w then
      return control.page
    end
  end
  return nil
end

return M
