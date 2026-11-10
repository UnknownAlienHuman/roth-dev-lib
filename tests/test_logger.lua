_G.RothDevLib = {}
local RDL = RothDevLib
_G.date = function() return '12:34:56' end

local secret = setmetatable({}, {
  __tostring = function() error('secret tostring') end,
  __pairs = function() error('secret pairs') end,
  __index = function() error('secret index') end,
})
function _G.canaccessvalue(value) return value ~= secret end
function _G.issecretvalue(value) return value == secret end
function _G.canaccesstable(value) return value ~= secret end
function _G.issecrettable(value) return value == secret end

assert(loadfile('Util/SecretGuard.lua'))()
assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/BoundedCopy.lua'))()
assert(loadfile('Util/Logger.lua'))()
local L = RDL.Logger
L:Init()

-- Direct logger calls must not execute foreign tostring/pairs metamethods.
assert(pcall(L.Log, L, secret, secret, secret, { hidden = secret }) == true)
assert(#L.lines == 1)
assert(L.lines[1]:find('<inaccessible>', 1, true))

-- One giant payload remains one bounded line, not hundreds of kilobytes.
local huge = {}
for index = 1, 1000 do huge['key' .. index] = string.rep('x', 1024) end
assert(L:Log('INFO', 'HUGE', string.rep('m', 20000), huge) == true)
assert(#L.lines[2] <= L:GetStats().maxLineBytes + 16)

-- Both line count and total bytes are hard bounds. The newest records survive.
for index = 1, 500 do
  L:Log('INFO', 'BURST', 'line-' .. index .. string.rep('y', 9000), {
    index = index,
    payload = string.rep('z', 9000),
  })
end
local stats = L:GetStats()
assert(stats.lines <= stats.maxLines and stats.maxLines == 300)
assert(stats.bytes <= stats.maxBytes and stats.maxBytes == 2 * 1024 * 1024)
assert(stats.dropped > 0)
local actualBytes = 0
for _, line in ipairs(L.lines) do
  assert(type(line) == 'string')
  assert(#line <= stats.maxLineBytes + 16)
  actualBytes = actualBytes + #line
end
assert(actualBytes == stats.bytes)
assert(L.lines[#L.lines]:find('line%-500'))
assert(#L:GetText() <= stats.maxBytes + stats.lines)

-- Init sanitizes a pre-existing malformed buffer and clamps user mutation of
-- maxLines without retaining non-string foreign objects.
L.lines = { secret, string.rep('q', 20000), 'ok' }
L.maxLines = 999999
L:Init()
stats = L:GetStats()
assert(stats.maxLines == 1000 and stats.lines == 3)
for _, line in ipairs(L.lines) do assert(type(line) == 'string') end

L:Clear()
stats = L:GetStats()
assert(stats.lines == 0 and stats.bytes == 0 and stats.dropped == 0)

print('logger bounds tests: ok')
