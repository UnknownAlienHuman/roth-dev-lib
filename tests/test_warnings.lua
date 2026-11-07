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
function _G.debugstack() return 'warning stack' end
RDL.Log = function() end

assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/BoundedCopy.lua'))()
assert(loadfile('Util/SecretGuard.lua'))()

local built, stored
RDL.Capture.BuildEntry = function(kind, message, stack, locals, addon, funcName, extra)
  built = { kind = kind, message = message, stack = stack, addon = addon, funcName = funcName, extra = extra }
  return built
end
RDL.Capture.StoreEntry = function(entry) stored = entry; return 'stored' end
assert(loadfile('Capture/Warnings.lua'))()

local entry, status = RDL.Capture:OnLuaWarning('Deprecated', 'Interface/AddOns/Demo/Core.lua:42: warning', secret)
assert(entry == stored and status == 'stored')
assert(built.kind == 'LUA_WARNING')
assert(built.message == 'LUA_WARNING(Deprecated): Interface/AddOns/Demo/Core.lua:42: warning')
assert(built.addon == 'Demo')
assert(built.funcName == 'Core.lua:42')
assert(built.extra.raw.n == 3)
assert(built.extra.raw[3] == '<inaccessible>')
assert(built.extra.origin.line == 42)

RDL.Capture.StoreEntry = function() return 'failed' end
entry, status = RDL.Capture:OnLuaWarning(secret)
assert(entry == nil and status == 'failed')

print('warning intake tests: ok')
