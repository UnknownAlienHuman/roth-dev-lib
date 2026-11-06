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

function _G.scrubsecretvalues(a, b, c, d, e, f, g, h)
  local function scrub(v)
    if v == secret then return nil end
    return v
  end
  return scrub(a), scrub(b), scrub(c), scrub(d), scrub(e), scrub(f), scrub(g), scrub(h)
end

assert(loadfile('Util/SecretGuard.lua'))()
assert(loadfile('Util/Util.lua'))()

local logCount = 0
function RDL:Log()
  logCount = logCount + 1
end

RDL.Internal = {
  Call = function(_, _, _, fn, ...)
    return pcall(fn, ...)
  end,
}

assert(loadfile('Integration/Callbacks.lua'))()

assert(RDL:RegisterCallback(secret, 'key', function() end) == false)
assert(RDL:RegisterCallback('EVENT', secret, function() end) == false)
assert(RDL:RegisterCallback('EVENT', 'key', secret) == false)

local seen = {}
assert(RDL:RegisterCallback('EVENT', 'good', function(a, b)
  seen.a = a
  seen.b = b
end) == true)

RDL:Fire(secret, 'ignored')
assert(seen.b == nil)

RDL:Fire('EVENT', secret, 'ordinary')
assert(seen.a == nil)
assert(seen.b == 'ordinary')

assert(RDL:RegisterCallback('EVENT', 'bad', function()
  error('callback failure')
end) == true)
RDL:Fire('EVENT', 'x')
assert(logCount == 1)
assert(RDL._callbacks.EVENT.bad == nil)
assert(type(RDL._callbacks.EVENT.good) == 'function')

assert(RDL:UnregisterCallback('EVENT', 'good') == true)
assert(RDL._callbacks.EVENT == nil)
assert(RDL:UnregisterCallback('EVENT', 'missing') == false)
assert(RDL:UnregisterCallback(secret, 'missing') == false)

print('callback tests: ok')
