_G.RothDevLib = { Capture = {} }
local RDL = RothDevLib
local secret = setmetatable({}, {
  __tostring = function() error('secret tostring') end,
  __index = function() error('secret index') end,
})
function _G.canaccessvalue(v) return v ~= secret end
function _G.issecretvalue(v) return v == secret end
function _G.canaccesstable(v) return v ~= secret end
function _G.issecrettable(v) return v == secret end
function _G.canaccessallvalues(...) return true end
function _G.debugstack() return 'stack' end
function _G.InCombatLockdown() return secret end
_G.Enum = {
  AddOnRestrictionType = { Combat = 1, Encounter = 2, ChallengeMode = 3, PvPMatch = 4, Map = 5 },
  AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
}
_G.C_RestrictedActions = {
  GetAddOnRestrictionState = function() return secret end,
  IsAddOnRestrictionActive = function() return secret end,
}
RDL.Log = function() end

assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/BoundedCopy.lua'))()
assert(loadfile('Util/SecretGuard.lua'))()

local built, stored
RDL.Capture.BuildEntry = function(kind, msg, stack, locals, addon, funcName, extra)
  built = { kind = kind, msg = msg, addon = addon, extra = extra }
  return built
end
RDL.Capture.StoreEntry = function(entry) stored = entry; return 'stored' end

assert(loadfile('Capture/Taint.lua'))()

RDL.Capture:OnTaintEvent(secret, secret, secret)
assert(stored == built)
assert(built.kind == 'TAINT_FORBIDDEN')
assert(built.addon == '<inaccessible>')
assert(built.msg:find('addon=<inaccessible>', 1, true))
assert(built.extra.event == '<inaccessible>')
assert(built.extra.restriction.inCombat == '<inaccessible>')
assert(built.extra.restriction.restrictions.Combat.state == '<inaccessible>')
assert(built.extra.restriction.restrictions.Combat.active == '<inaccessible>')

RDL.Capture:OnTaintEvent('MACRO_ACTION_BLOCKED', secret)
assert(built.kind == 'TAINT_BLOCKED')
assert(built.addon == 'BlizzardMacro')
assert(built.extra.source == 'macro')

RDL.Capture:OnRestrictionStateChanged('ADDON_RESTRICTION_STATE_CHANGED', secret, secret)
assert(built.kind == 'TAINT_STATE')
assert(built.extra.restrictionType == '<inaccessible>')
assert(built.extra.state == '<inaccessible>')

RDL.Capture.StoreEntry = function() return 'throttled' end
local entry, status = RDL.Capture:OnTaintEvent('ADDON_ACTION_BLOCKED', 'Test', 'Fn')
assert(entry == nil and status == 'throttled')

print('taint intake tests: ok')
