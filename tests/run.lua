local windows = package.config:sub(1,1)=="\\"
local pipe = io.popen(windows and 'dir /b "tests\\test_*.lua"' or 'find tests -maxdepth 1 -name "test_*.lua" -printf "%f\n" | sort')
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
