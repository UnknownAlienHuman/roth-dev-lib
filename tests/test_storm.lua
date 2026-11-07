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

-- Direct hostile kinds degrade to one ordinary bounded identity.
assert(pcall(S.Allow, S, secret) == true)

-- Dynamic kinds cannot allocate one bucket each or bypass throttling forever.
now = 20
for index = 1, 200 do
  S:Allow('CUSTOM_KIND_' .. index .. string.rep('x', 100))
end
local stats = S:GetStats()
assert(stats.bucketCount == stats.maxBuckets and stats.maxBuckets == 64)
assert(stats.droppedKinds > 0)
local actualBuckets = 0
for kind in pairs(S._buckets) do
  actualBuckets = actualBuckets + 1
  assert(type(kind) == 'string' and #kind <= 64)
end
assert(actualBuckets == stats.bucketCount)

-- Overflow kinds share one token bucket, so rotating names still throttles.
now = 100
local allowed, denied = 0, 0
for index = 1, 100 do
  if S:Allow('OVERFLOW_' .. index) then allowed = allowed + 1 else denied = denied + 1 end
end
assert(allowed <= 60 and denied > 0)

-- Stats are detached snapshots; callers cannot mutate live buckets.
stats = S:GetStats()
stats.buckets['@other'].tokens = 999999
assert(S._buckets['@other'].tokens ~= 999999)

S:Reset()
stats = S:GetStats()
assert(stats.total == 0 and stats.throttled == 0)
assert(stats.bucketCount == 1 and stats.droppedKinds == 0)
assert(stats.buckets['@other'])

print('storm bounds tests: ok')
