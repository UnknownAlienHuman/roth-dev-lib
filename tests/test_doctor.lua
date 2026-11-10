_G.RothDevLib = { addonName = '!RothDevLib' }
_G.time = function() return 100 end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

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
assert(loadfile('Doctor/Doctor.lua'))()
local D = RothDevLib.Doctor
D:Init()

local first = D:Enter('A', 'one', { n = 1 })
local second = D:Enter('B', 'two', { n = 2 })
local third = D:Enter('C', 'three', { n = 3 })
assert(type(first) == 'table' and next(first) == nil)
assert(type(second) == 'table' and next(second) == nil)
assert(D.stack == nil) -- retained stack is private, not a mutable public field

local top = D:GetTop()
assert(top.addon == 'C' and top.func == 'three' and top.ctx.n == 3)
top.func = 'tampered'
top.ctx.n = 99
D.lastSnapshot.func = 'tampered-last'
D.lastSnapshot.ctx.n = 88
local freshTop = D:GetTop()
assert(freshTop.func == 'three' and freshTop.ctx.n == 3)

-- Remove an exact stale scope without popping newer scopes.
first.fake = true -- token mutation cannot change retained scope metadata
assert(D:Leave(first) == true)
local chain = D:GetSnapshotChain()
assert(#chain == 2)
assert(chain[1].addon == 'B' and chain[1].func == 'two')
assert(chain[2].addon == 'C' and chain[2].func == 'three')
assert(D:Leave(first) == false)
assert(pcall(D.Leave, D, secret) == true and D:Leave(secret) == false)
assert(D:Leave(third) == true and D:GetTop().func == 'two')
assert(D:Leave() == true and D:GetTop() == nil)

-- Contexts cross a bounded detached-value boundary before Doctor retains them.
local source = { nested = { n = 1 }, hidden = secret }
local token = D:Enter('Addon', 'detached', source)
source.nested.n = 99
local snapshot = D:GetTop()
assert(snapshot.ctx.nested.n == 1)
assert(snapshot.ctx.hidden == '<inaccessible>')
snapshot.ctx.nested.n = 77
chain = D:GetSnapshotChain()
chain[1].ctx.nested.n = 66
assert(D:GetTop().ctx.nested.n == 1)
assert(D:Leave(token) == true)

-- Secret identities/context are normalized before type/format/index operations.
local secretToken = D:Enter(secret, secret, secret)
snapshot = D:GetTop()
assert(snapshot.addon == '<inaccessible>')
assert(snapshot.func == '<inaccessible>')
assert(snapshot.ctx == '<inaccessible>')
assert(D:Leave(secretToken) == true)

-- A caller that forgets Leave cannot grow the correlation stack forever. Keep
-- the newest scopes because they are the useful context for the next failure.
local oldest, newest
for index = 1, 70 do
  local item = D:Enter('Addon', 'scope' .. index, { index = index })
  if index == 1 then oldest = item end
  newest = item
end
local stats = D:GetStats()
assert(stats.depth == stats.maximum and stats.maximum == 64)
assert(stats.dropped == 6 and stats.maxContextBytes == 64 * 1024)
chain = D:GetSnapshotChain()
assert(#chain == 64 and chain[1].func == 'scope7' and chain[64].func == 'scope70')
assert(chain[1].ctx.index == 7 and chain[64].ctx.index == 70)
assert(D:Leave(oldest) == false)
assert(D:Leave(newest) == true and D:GetTop().func == 'scope69')
assert(D:TryLeaveAll(1000) == 63)
assert(D:GetTop() == nil and D:GetStats().depth == 0)

local result = table.pack(D:Scope('A', 'returns', nil, function()
  return 1, nil, 3, 4, nil, 6, 7, 8
end))
assert(result.n == 9 and result[1] == true and result[9] == 8)
assert(D:GetTop() == nil)

local failed = table.pack(D:Scope('A', 'failure', nil, function() error('boom') end))
assert(failed[1] == false and type(failed[2]) == 'string' and failed[2]:find('boom', 1, true))
assert(D:GetTop() == nil)

local rejected = table.pack(D:Scope('A', 'secret-fn', nil, secret))
assert(rejected[1] == false and rejected[2] == 'Doctor.Scope: fn is not callable')
assert(D:GetTop() == nil)

print('doctor token cleanup tests: ok')
