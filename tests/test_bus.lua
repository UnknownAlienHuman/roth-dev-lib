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
B:Metric('Test', 'fps', 60, 'hz', { metricMinInterval = 0 })
assert(B:GetAddonStats('Test').size == 10)
local throttled = B:RegisterAddon('Throttle', { maxBreadcrumbs = 20 })
B:Metric('Throttle', 'fps', 60, 'hz', { minInterval = 100 })
local head = throttled.head
B:Metric('Throttle', 'fps', 61, 'hz', { minInterval = 100 })
assert(throttled.head == head)
print('bus tests: ok')
