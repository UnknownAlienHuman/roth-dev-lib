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
RDL:Fire('EVENT', { n = 3 })
assert(logCount == 1)
assert(RDL._callbacks.EVENT.bad == nil)

assert(RDL:UnregisterCallback('EVENT', 'a_mutator') == true)
assert(RDL:UnregisterCallback('EVENT', 'b_replaced') == true)
assert(RDL:UnregisterCallback('EVENT', 'z_late') == true)
assert(RDL._callbacks.EVENT == nil)
assert(RDL:UnregisterCallback('EVENT', 'missing') == false)

print('callback tests: ok')
