_G.RothDevLib = nil
_G.C_Timer = {
  After = function() end,
  NewTicker = function() end,
  NewTimer = function() end,
}
_G.time = function() return 123 end

assert(loadfile('Core/Core.lua'))('!RothDevLib')
local RDL = assert(_G.RothDevLib)
assert(RDL.addonName == '!RothDevLib')
assert(RDL.name == 'RothDevLib')
assert(RDL.SafeCall == nil and RDL.WrapSafe == nil and RDL.WrapUnsafe == nil)
assert(RDL._apiFingerprint._init == true)
assert(RDL._timerFingerprint.After == C_Timer.After)

local alerts = {}
RDL.Capture = {
  OnIntegrationEvent = function(_, kind, addon, code)
    alerts[#alerts + 1] = { kind = kind, addon = addon, code = code }
  end,
}
RDL.SafeCall = function() end
RDL._apiFingerprint.SafeCall = RDL.SafeCall
RDL:SelfCheckEarly('test')
assert(#alerts == 0)

RDL.SafeCall = function() end
RDL:SelfCheckEarly('test')
assert(#alerts == 1 and alerts[1].code == 'API_OVERRIDDEN')

print('core bootstrap tests: ok')
