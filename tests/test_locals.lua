local secret = setmetatable({}, {
  __index = function() error('secret index') end,
  __pairs = function() error('secret pairs') end,
  __tostring = function() error('secret tostring') end,
})
function _G.canaccessvalue(value) return value ~= secret end
function _G.issecretvalue(value) return value == secret end
function _G.canaccesstable(value) return value ~= secret end
function _G.issecrettable(value) return value == secret end

local settings = {
  captureLocals = true,
  maxLocalsSize = 8192,
  localsProbeMax = 4,
  localsProbesPerSec = 30,
  localsProbeCache = true,
}
_G.RothDevLib = { DB = { GetSettings = function() return settings end } }
_G.time = function() return 100 end
_G.GetTime = function() return 10 end

local currentFrame = 'Interface/AddOns/Test/Core.lua:7: in function <Core.lua:1>'
local localsCalls = 0
_G.debuglocals = function(level)
  localsCalls = localsCalls + 1
  return 'alpha = 1\nbeta = 2\ngamma = 3\nlevel = ' .. tostring(level)
end
_G.debugstack = function()
  return currentFrame
end

assert(loadfile('Util/SecretGuard.lua'))()
assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/BoundedCopy.lua'))()
assert(loadfile('Capture/Locals.lua'))()
local L = RothDevLib.Locals

local locals, meta = L:CaptureBest({
  addon = 'Test',
  stack = currentFrame,
  baseLevel = 2,
})
assert(type(locals) == 'string' and meta.level == 2 and meta.score >= 60)
assert(L:GetCacheStats().keys == 1)
local callsAfterFirst = localsCalls
locals, meta = L:CaptureBest({
  addon = 'Test',
  stack = currentFrame,
  baseLevel = 2,
})
assert(meta.cacheHit == true and localsCalls == callsAfterFirst + 1)

-- Addon identities containing Lua pattern characters are matched literally.
currentFrame = 'Interface\\AddOns\\Demo+()\\Core.lua:9: in function <Core.lua:1>'
local ok, specialLocals, specialMeta = pcall(L.CaptureBest, L, {
  addon = 'Demo+()',
  stack = currentFrame,
  baseLevel = 2,
})
assert(ok and type(specialLocals) == 'string' and specialMeta.score >= 60)

-- Options are foreign input: raw field reads must not invoke __index/__pairs.
currentFrame = 'Interface/AddOns/Test/Core.lua:7: in function <Core.lua:1>'
local hostileOpts = setmetatable({
  addon = 'Test',
  stack = currentFrame,
  baseLevel = 2,
  cacheKey = 'hostile-options',
}, {
  __index = function() error('__index must not run') end,
  __pairs = function() error('__pairs must not run') end,
})
assert(pcall(L.CaptureBest, L, hostileOpts) == true)
assert(pcall(L.CaptureBest, L, secret) == true)

-- Dynamic stack origins/cache keys cannot grow retained calibration state forever.
for index = 1, 600 do
  local result, info = L:CaptureBest({
    addon = 'Test',
    stack = currentFrame,
    baseLevel = 2,
    cacheKey = 'dynamic-' .. index .. string.rep('x', 500),
  })
  assert(type(result) == 'string' and info.level == 2)
end
local stats = L:GetCacheStats()
assert(stats.keys == stats.maximum and stats.maximum == 512)
assert(stats.dropped > 0)
local actual = 0
for key in pairs(L._cache) do
  actual = actual + 1
  assert(#key <= 384)
end
assert(actual == stats.maximum)

-- Inaccessible debug payloads degrade to no frame instead of throwing.
currentFrame = secret
assert(pcall(L.CaptureBest, L, { addon = 'Test', baseLevel = 2 }) == true)

L:ResetCache()
stats = L:GetCacheStats()
assert(stats.keys == 0 and stats.dropped == 0 and next(L._cache) == nil)

print('locals capture bounds tests: ok')
