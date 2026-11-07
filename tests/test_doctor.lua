_G.RothDevLib = { addonName = '!RothDevLib' }
_G.time = function() return 100 end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local secret = setmetatable({}, {
  __tostring = function() error('secret tostring') end,
  __pairs = function() error('secret pairs') end,
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
assert(D:GetTop() == third)

-- Remove an exact stale scope without popping newer scopes.
assert(D:Leave(first) == true)
assert(D:GetTop() == third)
assert(#D.stack == 2 and D.stack[1] == second and D.stack[2] == third)
assert(D:Leave(first) == false)
assert(D:Leave(third) == true and D:GetTop() == second)
assert(D:Leave() == true and D:GetTop() == nil)

-- Contexts cross a bounded detached-value boundary before Doctor retains them.
local source = { nested = { n = 1 }, hidden = secret }
local token = D:Enter('Addon', 'detached', source)
source.nested.n = 99
assert(token.ctx.nested.n == 1)
assert(token.ctx.hidden == '<inaccessible>')
local chain = D:GetSnapshotChain()
chain[1].ctx.nested.n = 77
assert(D.stack[1].ctx.nested.n == 1)
D:Reset()

-- A caller that forgets Leave cannot grow the correlation stack forever. Keep
-- the newest scopes because they are the useful context for the next failure.
local oldest
for index = 1, 70 do
  local item = D:Enter('Addon', 'scope' .. index, { index = index })
  if index == 1 then oldest = item end
end
local stats = D:GetStats()
assert(stats.depth == stats.maximum and stats.maximum == 64)
assert(stats.dropped == 6)
assert(D.stack[1].func == 'scope7')
assert(D:GetTop().func == 'scope70')
assert(D:Leave(oldest) == false)
chain = D:GetSnapshotChain()
assert(#chain == 64 and chain[1].ctx.index == 7 and chain[64].ctx.index == 70)
D:Reset()

local result = table.pack(D:Scope('A', 'returns', nil, function()
  return 1, nil, 3, 4, nil, 6, 7, 8
end))
assert(result.n == 9 and result[1] == true and result[9] == 8)
assert(D:GetTop() == nil)

print('doctor token cleanup tests: ok')
