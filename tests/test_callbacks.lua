_G.RothDevLib = {}
local RDL = RothDevLib

local secret = setmetatable({}, {
  __tostring = function() error('secret tostring') end,
  __index = function() error('secret index') end,
  __len = function() error('secret len') end,
})

function _G.canaccessvalue(v) return v ~= secret end
function _G.issecretvalue(v) return v == secret end
function _G.canaccesstable(v) return v ~= secret end
function _G.issecrettable(v) return v == secret end
function _G.canaccessallvalues(...)
  for i = 1, select('#', ...) do
    if select(i, ...) == secret then return false end
  end
  return true
end

assert(loadfile('Util/SecretGuard.lua'))()
assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/BoundedCopy.lua'))()

local logCount = 0
function RDL:Log() logCount = logCount + 1 end
RDL.Internal = {
  Call = function(_, _, _, fn, ...)
    return pcall(fn, ...)
  end,
}

assert(loadfile('Integration/Callbacks.lua'))()

assert(RDL:RegisterCallback(secret, 'key', function() end) == false)
assert(RDL:RegisterCallback('EVENT', secret, function() end) == false)
assert(RDL:RegisterCallback('EVENT', 'key', secret) == false)

local original = { n = 1, hidden = secret }
local observedSecond
local firstDispatch = true
assert(RDL:RegisterCallback('EVENT', 'a_mutator', function(payload)
  payload.n = 99
  payload.newField = true
  if firstDispatch then
    firstDispatch = false
    -- Registration during dispatch must wait for the next Fire.
    RDL:RegisterCallback('EVENT', 'z_late', function() end)
    -- Replace b before its turn; the old callback must be skipped.
    RDL:RegisterCallback('EVENT', 'b_replaced', function(value)
      observedSecond = value
    end)
  end
end))

local staleCalled = false
assert(RDL:RegisterCallback('EVENT', 'b_replaced', function()
  staleCalled = true
end))

assert(RDL:Fire('EVENT', original) == 1)
assert(staleCalled == false)
assert(observedSecond == nil)
assert(original.n == 1 and original.newField == nil)

-- The replacement and the callback added during dispatch run only next time.
local lateCalls = 0
RDL:RegisterCallback('EVENT', 'z_late', function() lateCalls = lateCalls + 1 end)
RDL:Fire('EVENT', original)
assert(lateCalls == 1)
assert(observedSecond.n == 1)
assert(observedSecond.hidden == '<inaccessible>')
assert(observedSecond.newField == nil)
assert(original.n == 1 and original.newField == nil)

assert(RDL:RegisterCallback('EVENT', 'bad', function()
  error('callback failure')
end) == true)
local beforeBad = RDL:GetCallbackRegistryStats().callbacks
RDL:Fire('EVENT', { n = 3 })
assert(logCount == 1)
assert(RDL._callbacks.EVENT.bad == nil)
assert(RDL:GetCallbackRegistryStats().callbacks == beforeBad - 1)

assert(RDL:UnregisterCallback('EVENT', 'a_mutator') == true)
assert(RDL:UnregisterCallback('EVENT', 'b_replaced') == true)
assert(RDL:UnregisterCallback('EVENT', 'z_late') == true)
assert(RDL._callbacks.EVENT == nil)
assert(RDL:UnregisterCallback('EVENT', 'missing') == false)
local stats = RDL:GetCallbackRegistryStats()
assert(stats.events == 0 and stats.callbacks == 0)

local noop = function() end

-- A single event cannot retain an unbounded set of dynamically generated keys.
for index = 1, 128 do
  assert(RDL:RegisterCallback('PER_EVENT', 'key' .. index, noop) == true)
end
assert(RDL:RegisterCallback('PER_EVENT', 'overflow', noop) == false)
stats = RDL:GetCallbackRegistryStats()
assert(stats.callbacks == 128 and stats.maxPerEvent == 128)
-- Replacing an existing key is allowed at the ceiling and does not change counts.
assert(RDL:RegisterCallback('PER_EVENT', 'key1', function() end) == true)
assert(RDL:GetCallbackRegistryStats().callbacks == 128)
for index = 1, 128 do
  assert(RDL:UnregisterCallback('PER_EVENT', 'key' .. index) == true)
end

-- Event namespaces themselves are bounded.
for index = 1, 128 do
  assert(RDL:RegisterCallback('EVENT_' .. index, 'key', noop) == true)
end
assert(RDL:RegisterCallback('EVENT_129', 'key', noop) == false)
stats = RDL:GetCallbackRegistryStats()
assert(stats.events == stats.maxEvents and stats.maxEvents == 128)
for index = 1, 128 do
  assert(RDL:UnregisterCallback('EVENT_' .. index, 'key') == true)
end

-- The total callback count remains bounded across multiple events.
for eventIndex = 1, 4 do
  local eventName = 'TOTAL_' .. eventIndex
  for keyIndex = 1, 128 do
    assert(RDL:RegisterCallback(eventName, 'key' .. keyIndex, noop) == true)
  end
end
assert(RDL:RegisterCallback('TOTAL_5', 'key', noop) == false)
stats = RDL:GetCallbackRegistryStats()
assert(stats.callbacks == stats.maxCallbacks and stats.maxCallbacks == 512)
assert(stats.events == 4 and stats.dropped >= 3)
assert(RDL:RegisterCallback('TOTAL_1', 'key1', function() end) == true)
assert(RDL:GetCallbackRegistryStats().callbacks == 512)

print('callback tests: ok')
