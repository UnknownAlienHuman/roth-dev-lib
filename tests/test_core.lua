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

local delayed = {}
_G.C_Timer = { After = function(_, fn) delayed[#delayed + 1] = fn end }

_G.RothDevLib = nil
assert(loadfile('Core/Core.lua'))('!RothDevLib')
local RDL = assert(_G.RothDevLib)
assert(loadfile('Util/SecretGuard.lua'))()
assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/BoundedCopy.lua'))()
assert(loadfile('Core/CallSafety.lua'))()

local entered, leaveTokens = {}, {}
RDL.Doctor = {
  Enter = function(_, addonName, funcName, ctx)
    local token = { addon = addonName, func = funcName, ctx = ctx }
    entered[#entered + 1] = token
    return token
  end,
  Leave = function(_, token)
    leaveTokens[#leaveTokens + 1] = token
    return true
  end,
}

local captured
RDL.Capture = {
  OnSuppressedError = function(_, message, stack, locals, addonName, funcName, extra)
    captured = { message = message, stack = stack, locals = locals,
      addon = addonName, func = funcName, extra = extra }
  end,
}

assert(pcall(RDL.SafeCall, RDL, secret, secret, secret) == true)
assert(RDL:WrapSafe('Addon', 'Func', secret) == nil)
assert(RDL:WrapUnsafe('Addon', 'Func', secret) == nil)

local result = table.pack(RDL:SafeCall('Addon', 'Func', function()
  return 1, nil, 3, 4, nil, 6, 7, 8
end))
assert(result.n == 8 and result[1] == 1 and result[2] == nil and result[8] == 8)
assert(leaveTokens[#leaveTokens] == entered[#entered])

local ctx = { n = 1, hidden = secret }
local wrapped = assert(RDL:WrapSafe('Addon', 'Wrapped', function(v) return v * 2 end, ctx))
ctx.n = 9
assert(wrapped(4) == 8)
assert(entered[#entered].ctx.n == 1)
assert(entered[#entered].ctx.hidden == '<inaccessible>')

local failing = assert(RDL:WrapSafeCtx(secret, secret, function()
  error(secret, 0)
end, function() return { hidden = secret } end))
assert(failing() == nil)
assert(captured.message == '<inaccessible>')
assert(captured.addon == '<inaccessible>')
assert(captured.func == '<inaccessible>')
assert(captured.stack == 'stack')

local unsafe = assert(RDL:WrapUnsafe('Addon', 'Unsafe', function()
  return 1, nil, 3, 4, nil, 6, 7, 8
end))
local unsafeResult = table.pack(unsafe())
assert(unsafeResult.n == 8 and unsafeResult[8] == 8)
local unsafeToken = entered[#entered]
assert(leaveTokens[#leaveTokens] == unsafeToken)
assert(#delayed >= 1)
delayed[#delayed]() -- idempotent token cleanup after successful return
assert(leaveTokens[#leaveTokens] == unsafeToken)

-- A profiling infrastructure failure must still release the exact Doctor token.
RDL.CPU = { Measure = function() error('profiler failed') end }
local beforeLeaves = #leaveTokens
assert(RDL:SafeCall('Addon', 'Infra', function() return true end) == nil)
assert(#leaveTokens == beforeLeaves + 1)
assert(leaveTokens[#leaveTokens] == entered[#entered])

local logged
RDL.Logger = { Log = function(_, level, tag, message, data)
  logged = { level = level, tag = tag, message = message, data = data }
end }
assert(RDL:Log(secret, secret, secret, { hidden = secret }) == true)
assert(logged.level == '<inaccessible>')
assert(logged.data.hidden == '<inaccessible>')

print('core public API tests: ok')
