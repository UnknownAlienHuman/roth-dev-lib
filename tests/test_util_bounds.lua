_G.RothDevLib = {}
function _G.canaccessvalue() return true end
function _G.issecretvalue() return false end
function _G.canaccesstable() return true end
function _G.issecrettable() return false end

assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/BoundedCopy.lua'))()
local U = RothDevLib.Util

local hostile = setmetatable({ safe = 1 }, {
  __pairs = function() error('__pairs must not run') end,
  __index = function() error('__index must not run') end,
})
local copy = U:CopyDiagnosticValue(hostile)
assert(copy.safe == 1)
assert(U:SafeSerializeTable(hostile):find('safe=1', 1, true))

local root = {}
local cursor = root
for i = 1, 100 do
  cursor.next = { a = i, b = i, c = i }
  cursor = cursor.next
end
local bounded = U:CopyDiagnosticValue(root, {
  maxDepth = 12,
  maxEntries = 100,
  maxNodes = 12,
})
local function ContainsMarker(value, seen)
  if value == '<node-limit>' then return true end
  if type(value) ~= 'table' then return false end
  seen = seen or {}
  if seen[value] then return false end
  seen[value] = true
  for _, item in pairs(value) do
    if ContainsMarker(item, seen) then return true end
  end
  return false
end
assert(ContainsMarker(bounded))

print('utility traversal-bound tests: ok')
