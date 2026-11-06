_G.RothDevLib = {}
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end end
_G.issecretvalue = function(v) return type(v) == "table" and rawget(v, "__secret") == true end
_G.canaccessvalue = function(v) return not _G.issecretvalue(v) end
_G.canaccessallvalues = function(...)
  for i = 1, select('#', ...) do
    if not _G.canaccessvalue(select(i, ...)) then return false end
  end
  return true
end
_G.canaccesstable = function(v) return type(v) == "table" and not _G.issecretvalue(v) end
_G.issecrettable = _G.issecretvalue
assert(loadfile('Util/SecretGuard.lua'))()
assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/BoundedCopy.lua'))()
assert(loadfile('Util/JSON.lua'))()
local J = RothDevLib.JSON

local array = {}
for i = 1, 250 do array[i] = i end
local out = J:Encode(array)
assert(out:sub(1, 1) == '[' and out:find('"<truncated>"', 1, true), out)

local duplicateKeys = { [1] = 'number', ['1'] = 'string' }
out = J:Encode(duplicateKeys)
assert(out:find('"1":"string"', 1, true), out)
assert(out:find('"[number]1":"number"', 1, true), out)

local huge = {}
for i = 1, 100 do huge[i] = string.rep('x', 1000) end
out = J:Encode(huge, { maxOutputBytes = 4096 })
assert(out == '{"error":"json_output_limit"}', out)

local scan = {}
for i = 1, 25 do scan[i] = i end
out = J:Encode(scan, { maxScanEntries = 10 })
assert(out == '"<table-scan-limit>"', out)

-- Foreign metamethods must not execute. Raw fields remain encodable.
local hostile = setmetatable({ safe = 1 }, {
  __pairs = function() error('__pairs must not run') end,
  __index = function() error('__index must not run') end,
  __len = function() error('__len must not run') end,
})
out = J:Encode(hostile)
assert(out == '{"safe":1}', out)

-- Options are foreign input too; read them with rawget rather than __index.
local hostileOptions = setmetatable({ maxStringBytes = 256 }, {
  __index = function() error('option __index must not run') end,
  __pairs = function() error('option __pairs must not run') end,
})
out = J:Encode(string.rep('x', 300), hostileOptions)
assert(out:find('<truncated>', 1, true), out)

-- The node budget bounds broad trees independently of output bytes.
local broad = {}
for i = 1, 100 do broad[i] = { value = i } end
out = J:Encode(broad, { maxNodes = 10, maxArrayLen = 200 })
assert(out:find('<node-limit>', 1, true), out)

print('json edge tests: ok')
