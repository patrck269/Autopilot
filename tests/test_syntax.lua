for _,directory in ipairs({"programs","install"}) do
  for _,name in ipairs({"engine","command","pocket","watchdog"}) do
    local path=directory.."/"..name..".lua"
    local chunk,err=loadfile(path)
    assert(chunk,err)
  end
end
