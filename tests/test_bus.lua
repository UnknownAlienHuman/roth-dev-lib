_G.RothDevLib = { DB = { GetSettings = function() return { maxBreadcrumbsPerAddon = 4, metricMinInterval = 0 } end } }
_G.time = function() return 100 end
_G.GetTime = function() return 10 end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local secret = {}
function _G.canaccessvalue(value) return value ~= secret end
function _G.issecretvalue(value) return value == secret end
function _G.canaccesstable(value) return value ~= secret end
function _G.issecrettable(value) return value == secret end
function _G.canaccessallvalues(...) return true end

assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/SecretGuard.lua'))()
assert(loadfile('Integration/Bus.lua'))()

local B = RothDevLib.Bus
B:Init()
assert(B:RegisterAddon(secret) == nil)
local a = B:RegisterAddon('Test', { maxBreadcrumbs = 10 })
assert(a and a.max == 10)
for i = 1, 12 do B:Breadcrumb('Test', 'event', 'm' .. i, { n = i }) end
assert(a.size == 10)
local snap = B:GetBreadcrumbSnapshot('Test', 20)
assert(#snap == 10 and snap[1].msg == 'm12' and snap[10].msg == 'm3')
a = B:RegisterAddon('Test', { maxBreadcrumbs = 5 })
assert(a.max == 10) -- minimum clamp
for i = 13, 15 do B:Breadcrumb('Test', 'event', 'm' .. i) end
snap = B:GetBreadcrumbSnapshot('Test', 3)
assert(#snap == 3 and snap[1].msg == 'm15')
assert(B:Metric('Test', 'fps', 60, 'hz', { metricMinInterval = 0 }) == true)
assert(B:GetAddonStats('Test').size == 10)
local throttled = B:RegisterAddon('Throttle', { maxBreadcrumbs = 20 })
assert(B:Metric('Throttle', 'fps', 60, 'hz', { minInterval = 100 }) == true)
local head = throttled.head
assert(B:Metric('Throttle', 'fps', 61, 'hz', { minInterval = 100 }) == false)
assert(throttled.head == head)

-- Dynamic metric names are public diagnostic input and must not create an
-- unbounded throttle registry.
for index = 1, 2100 do
  B:Metric('Test', 'dynamic-' .. index, index, 'n', { minInterval = 0 })
end
local registry = B:GetRegistryStats()
assert(registry.metrics == registry.maxMetrics and registry.maxMetrics == 2048)
assert(registry.droppedMetrics > 0)
local metricCount = 0
for _ in pairs(B._metrics) do metricCount = metricCount + 1 end
assert(metricCount == registry.maxMetrics)

-- Spoofed addon identities are bounded too; real installed-addon counts are far
-- below this ceiling, while an integration bug cannot grow the registry forever.
for index = 1, 600 do B:RegisterAddon('DynamicAddon' .. index) end
registry = B:GetRegistryStats()
assert(registry.addons == registry.maxAddons and registry.maxAddons == 512)
assert(registry.droppedAddons > 0)
assert(B:RegisterAddon('OverflowAddon') == nil)
assert(B:Metric('OverflowAddon', 'x', 1, 'n', { minInterval = 0 }) == false)

B:ResetAll()
registry = B:GetRegistryStats()
assert(registry.metrics == 0 and registry.droppedMetrics == 0)
assert(registry.addons == 512)

print('bus tests: ok')
