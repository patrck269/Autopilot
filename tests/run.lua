local pipe = io.popen('dir /b "tests\\test_*.lua"')
if pipe == nil then
  error("cannot list tests")
end
local failed = 0
for name in pipe:lines() do
  name = name:gsub("\r", "")
  local path = "tests/" .. name
  local ok, err = pcall(dofile, path)
  if not ok then
    io.stderr:write(path .. "\n" .. tostring(err) .. "\n")
    failed = failed + 1
  end
end
pipe:close()
if failed > 0 then
  os.exit(1)
end
print("ok")
