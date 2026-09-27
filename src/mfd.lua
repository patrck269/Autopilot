local M = {}

local ROWS = {
  { "Flight", "Navigation", "Engines" },
  { "Emergency", "Systems" },
}

function M.controls(w, h)
  local list = {}
  for row_index, pages in ipairs(ROWS) do
    local slot = math.floor(w / #pages)
    if slot < 1 then
      slot = 1
    end
    local y = h - (#ROWS - row_index)
    for i, page in ipairs(pages) do
      list[#list + 1] = {
        page = page,
        label = page,
        x = (i - 1) * slot + 1,
        y = y,
        w = slot,
      }
    end
  end
  return list
end

function M.hit(w, h, x, y)
  for _, control in ipairs(M.controls(w, h)) do
    if y == control.y and x >= control.x and x < control.x + control.w then
      return control.page
    end
  end
  return nil
end

return M
