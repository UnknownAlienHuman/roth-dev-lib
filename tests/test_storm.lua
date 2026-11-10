local now = 10
_G.GetTime = function() return now end
_G.time = function() return math.floor(now) end

local secret = setmetatable({}, {
  __tostring = function() error('secret tostring') end,
})
function _G.canaccessvalue(value) return value ~= secret end
function _G.issecretvalue(value) return value == secret end
function _G.canaccesstable(value) return value ~= secret end
function _G.issecrettable(value) return value == secret end

_G.RothDevLib = {
  DB = {
    GetSettings = function()
      return { stormErrorsPerSec = 2, stormWarningsPerSec = 3 }
    end,
  },
}
local RDL = RothDevLib
assert(loadfile('Util/SecretGuard.lua'))()
assert(loadfile('Util/Util.lua'))()
assert(loadfile('Capture/Storm.lua'))()
local S = RDL.Storm

-- Error buckets start with a two-second burst budget, then throttle.
for _ = 1, 4 do assert(S:Allow('LUA_ERROR') == true) end
assert(S:Allow('LUA_ERROR') == false)
now = now + 0.5
assert(S:Allow('LUA_ERROR') == true)

-- A backward clock jump cannot create or subtract tokens incorrectly.
now = 1
assert(pcall(S.Allow, S, 'LUA_ERROR') == true)

-- Direct hostile kinds degrade to the shared ordinary overflow identity.
assert(pcall(S.Allow, S, secret) == true)

-- Every arbitrary public label shares one bucket immediately. Rotating names
-- therefore cannot multiply the integration burst budget before saturation.
now = 20
local allowed, denied = 0, 0
for index = 1, 200 do
  if S:Allow('CUSTOM_KIND_' .. index .. string.rep('x', 100)) then
    allowed = allowed + 1
  else
    denied = denied + 1
  end
end
assert(allowed <= 60 and denied > 0)

local stats = S:GetStats()
assert(stats.bucketCount == 2) -- LUA_ERROR plus @other
assert(stats.maxBuckets == 10 and stats.droppedKinds >= 200)
local actualBuckets = 0
for kind in pairs(S._buckets) do
  actualBuckets = actualBuckets + 1
  assert(type(kind) == 'string' and #kind <= 64)
end
assert(actualBuckets == stats.bucketCount)
assert(S._buckets['@other'])

-- A fixed semantic kind may own one independent bucket, but aliases do not.
now = 100
for _ = 1, 6 do assert(S:Allow('LUA_WARNING') == true) end
assert(S:Allow('LUA_WARNING') == false)
stats = S:GetStats()
assert(stats.bucketCount == 3)

-- Stats are detached snapshots; callers cannot mutate live buckets.
stats.buckets['@other'].tokens = 999999
assert(S._buckets['@other'].tokens ~= 999999)

S:Reset()
stats = S:GetStats()
assert(stats.total == 0 and stats.throttled == 0)
assert(stats.bucketCount == 1 and stats.droppedKinds == 0)
assert(stats.buckets['@other'])

print('storm bounds tests: ok')
