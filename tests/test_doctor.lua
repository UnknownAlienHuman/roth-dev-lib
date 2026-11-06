_G.RothDevLib = { addonName = '!RothDevLib' }
_G.time = function() return 100 end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

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

local result = table.pack(D:Scope('A', 'returns', nil, function()
  return 1, nil, 3, 4, nil, 6, 7, 8
end))
assert(result.n == 9 and result[1] == true and result[9] == 8)
assert(D:GetTop() == nil)

print('doctor token cleanup tests: ok')
