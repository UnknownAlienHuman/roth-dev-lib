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

-- The global output limit applies while children are emitted, not only after a
-- large subtree/parts array has already been assembled.
local huge = {}
for i = 1, 100 do huge[i] = string.rep('x', 1000) end
out = J:Encode(huge, { maxOutputBytes = 4096 })
assert(out == '{"error":"json_output_limit"}', out)

-- Object identities are bounded independently of value strings and output.
local hugeKey = {}
hugeKey[string.rep('k', 10000)] = 'value'
out = J:Encode(hugeKey, { maxKeyBytes = 64, maxOutputBytes = 4096 })
assert(#out < 256 and out:find('<truncated>', 1, true), out)

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


-- Distinct long object keys must remain distinct after the final key-byte cap.
local collidingKeys = {}
for index = 1, 6 do
  collidingKeys[string.rep('x', 100) .. tostring(index)] = index
end
local collidingJSON = J:Encode(collidingKeys, {
  maxKeyBytes = 64,
  maxOutputBytes = 8192,
})
local emittedKeys, emittedCount = {}, 0
for key in collidingJSON:gmatch('"([^"]+)":') do
  emittedCount = emittedCount + 1
  assert(#key <= 64)
  assert(emittedKeys[key] == nil, 'duplicate emitted JSON key: ' .. key)
  emittedKeys[key] = true
end
assert(emittedCount == 6)

-- Encoding must not depend on Lua table insertion/hash order after key
-- truncation. The same source mapping produces byte-identical output.
local orderedKeys = {}
for index = 1, 50 do
  orderedKeys[index] = string.rep('q', 100) .. string.format('%03d', index)
end
local forward, reverse = {}, {}
for index = 1, #orderedKeys do forward[orderedKeys[index]] = index end
for index = #orderedKeys, 1, -1 do reverse[orderedKeys[index]] = index end
local forwardJSON = J:Encode(forward, { maxKeyBytes = 64, maxOutputBytes = 65536 })
local reverseJSON = J:Encode(reverse, { maxKeyBytes = 64, maxOutputBytes = 65536 })
assert(forwardJSON == reverseJSON)

-- Unsupported object-key identities are skipped with a stable marker instead
-- of leaking addresses or assigning values by hash iteration order.
local unsupportedKey = {}
local mixedKeys = { ordinary = 1, [unsupportedKey] = 2 }
local mixedJSON = J:Encode(mixedKeys, { maxOutputBytes = 4096 })
assert(mixedJSON:find('"ordinary":1', 1, true))
assert(mixedJSON:find('"__truncated":"unsupported-key"', 1, true))

print('json edge tests: ok')
