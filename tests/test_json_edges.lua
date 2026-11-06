_G.RothDevLib = {}
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end end
_G.issecretvalue = function(v) return type(v) == "table" and rawget(v, "__secret") == true end
_G.canaccessvalue = function(v) return not _G.issecretvalue(v) end
_G.canaccessallvalues = function(...) for i=1,select('#', ...) do if not _G.canaccessvalue(select(i,...)) then return false end end return true end
_G.canaccesstable = function(v) return type(v) == "table" and not _G.issecretvalue(v) end
_G.issecrettable = _G.issecretvalue
assert(loadfile('Util/SecretGuard.lua'))()
assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/JSON.lua'))()
local J = RothDevLib.JSON

local a = {}
for i=1,250 do a[i]=i end
local out = J:Encode(a)
assert(out:sub(1,1)=='[' and out:find('"<truncated>"',1,true), out)

local dup = { [1] = 'number', ['1'] = 'string' }
out = J:Encode(dup)
assert(out:find('"1":"string"',1,true), out)
assert(out:find('"[number]1":"number"',1,true), out)

local huge = {}
for i=1,100 do huge[i] = string.rep('x', 1000) end
out = J:Encode(huge, { maxOutputBytes = 4096 })
assert(out == '{"error":"json_output_limit"}', out)

local scan = {}
for i=1,25 do scan[i]=i end
out = J:Encode(scan, {maxScanEntries=10})
assert(out == '"<table-scan-limit>"', out)

local secretError = { __secret = true }
local hostile = setmetatable({}, {
  __pairs = function() error(secretError, 0) end,
})
out = J:Encode(hostile)
assert(out == '{"error":"json_encode_failed"}', out)

print('json edge tests: ok')
