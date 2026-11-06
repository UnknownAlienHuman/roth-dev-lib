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
function _G.time() return 123 end
function _G.debugstack() return 'stack' end

_G.RothDevLib = nil
assert(loadfile('Core/Core.lua'))('!RothDevLib')
local RDL = assert(_G.RothDevLib)
assert(RDL.version == '1.0.0-alpha.20.0')

assert(loadfile('Util/SecretGuard.lua'))()
assert(loadfile('Util/Util.lua'))()

local entered, left = {}, 0
RDL.Doctor = {
  Enter = function(_, addonName, funcName, ctx)
    entered[#entered + 1] = { addon = addonName, func = funcName, ctx = ctx }
  end,
  Leave = function() left = left + 1 end,
}

local captured
RDL.Capture = {
  OnSuppressedError = function(_, message, stack, locals, addonName, funcName, extra)
    captured = {
      message = message,
      stack = stack,
      locals = locals,
      addon = addonName,
      func = funcName,
      extra = extra,
    }
  end,
}

assert(pcall(RDL.SafeCall, RDL, secret, secret, secret) == true)
assert(RDL:WrapSafe('Addon', 'Func', secret) == nil)
assert(RDL:WrapUnsafe('Addon', 'Func', secret) == nil)

local a, b = RDL:SafeCall('Addon', 'Func', function(x)
  return x, nil
end, 7)
assert(a == 7 and b == nil)
assert(entered[#entered].addon == 'Addon')
assert(entered[#entered].func == 'Func')
assert(entered[#entered].ctx.note == 'SafeCall')
assert(left == 1)

local ctx = { n = 1, hidden = secret }
local wrapped = assert(RDL:WrapSafe('Addon', 'Wrapped', function(v) return v * 2 end, ctx))
ctx.n = 9
assert(wrapped(4) == 8)
assert(entered[#entered].ctx.n == 1)
assert(entered[#entered].ctx.hidden == '<inaccessible>')

local failing = assert(RDL:WrapSafeCtx(secret, secret, function()
  error(secret, 0)
end, function()
  return { hidden = secret }
end))
assert(failing() == nil)
assert(captured.message == '<inaccessible>')
assert(captured.addon == '<inaccessible>')
assert(captured.func == '<inaccessible>')
assert(captured.stack == 'stack')

local logged
RDL.Logger = {
  Log = function(_, level, tag, message, data)
    logged = { level = level, tag = tag, message = message, data = data }
  end,
}
assert(RDL:Log(secret, secret, secret, { hidden = secret }) == true)
assert(logged.level == '<inaccessible>')
assert(logged.tag == '<inaccessible>')
assert(logged.message == '<inaccessible>')
assert(logged.data.hidden == '<inaccessible>')

assert(RDL._apiFingerprint.SafeCall == RDL.SafeCall)
assert(RDL._apiFingerprint.WrapSafeCtx == RDL.WrapSafeCtx)

print('core public API tests: ok')
