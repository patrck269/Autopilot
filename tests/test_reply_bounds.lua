package.path="src/?.lua;"..package.path
local A=dofile("tests/assert.lua")
local link=require("link")
local shell=require("shell")
local saved=textutils
local function json(value)
  local kind=type(value)
  if kind=="string" then
    local s=value:gsub('[%z\1-\31\\"]',function(c)
      if c=='"' or c=="\\" then return "\\"..c end
      return string.format("\\u%04x",string.byte(c))
    end)
    return '"'..s..'"'
  end
  if kind=="number" or kind=="boolean" then return tostring(value) end
  if kind=="nil" then return "null" end
  local parts={}
  for key,item in pairs(value) do parts[#parts+1]=json(tostring(key))..":"..json(item) end
  return "{"..table.concat(parts,",").."}"
end
textutils={serializeJSON=json}
local huge={type="result",id="1",ok=true,content=string.rep('"',100000),output=string.rep("\n",100000)}
local encoded=link.encode(huge)
if #encoded>link.FRAME_LIMIT then error("encoded frame exceeds wire limit") end
if not encoded:find('"truncated":true',1,true) then error("missing truncation flag") end
local small={type="result",id="1",ok=true,content="complete"}
A.eq(link.encode(small),json(small),"small response preserved")
local session=shell.new_session({}, {}, {})
local result=shell.eval(session,'return string.rep("x",100000),nil,{1,2,3}',function() return 0 end)
A.eq(result.truncated,true,"value export reports truncation")
A.eq(result.values[2],"nil","nil return position preserved")
A.eq(result.values[3][1],1,"arrays retain numeric indices")
shell.release(session)
result=shell.eval(session,'for i=1,10000 do print(string.rep("x",100)) end',function() return 0 end)
if #result.output>8192 then error("captured print is unbounded") end
A.eq(result.truncated,true,"print reports truncation")
textutils=saved
print("encoded frame and captured output bounds passed")
