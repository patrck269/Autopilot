local windows = package.config:sub(1,1)=="\\"
local pipe = io.popen(windows and 'dir /b "tests\\test_*.lua"' or 'find tests -maxdepth 1 -name "test_*.lua" -printf "%f\n" | sort')
if pipe == nil then
  error("cannot list tests")
end
-- Modules keep actuator-hold memory. A later file must not inherit it.
local preloaded = {}
for name in pairs(package.loaded) do
  preloaded[name] = true
end
local function unload_tests()
  for name in pairs(package.loaded) do
    if not preloaded[name] then
      package.loaded[name] = nil
    end
  end
end
local failed = 0
for name in pipe:lines() do
  name = name:gsub("\r", "")
  local path = "tests/" .. name
  local ok, err = pcall(dofile, path)
  unload_tests()
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
