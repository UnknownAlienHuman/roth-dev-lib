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
local function ContainsMarker(value, target, seen)
  if value == target then return true end
  if type(value) ~= 'table' then return false end
  seen = seen or {}
  if seen[value] then return false end
  seen[value] = true
  for _, item in pairs(value) do
    if ContainsMarker(item, target, seen) then return true end
  end
  return false
end
assert(ContainsMarker(bounded, '<node-limit>'))

local broad = {}
for index = 1, 100 do broad['key' .. index] = string.rep('x', 128) end
local byteBounded = U:CopyDiagnosticValue(broad, {
  maxDepth = 4,
  maxEntries = 100,
  maxNodes = 500,
  maxStringBytes = 256,
  maxTotalBytes = 1024,
})
assert(ContainsMarker(byteBounded, '<byte-limit>')
  or byteBounded.__rdl_truncated == 'byte-limit')
local serialized = U:SafeSerializeTable(byteBounded)
assert(#serialized < 4096)


-- Complete and incomplete secret escapes must never retain opaque payloads.
local complete = U:FilterSecretEscapes('before|Kopaque|kafter')
assert(complete == 'before<filtered>after')
local incomplete = U:FilterSecretEscapes('before|Kopaque-without-terminator')
assert(incomplete == 'before<filtered>')
local copiedEscape = U:CopyDiagnosticValue({
  complete = 'x|Ksecret|ky',
  incomplete = 'x|Ksecret-tail',
})
assert(copiedEscape.complete == 'x<filtered>y')
assert(copiedEscape.incomplete == 'x<filtered>')
assert(not copiedEscape.complete:find('|K', 1, true))
assert(not copiedEscape.incomplete:find('secret-tail', 1, true))

print('utility traversal-bound tests: ok')
