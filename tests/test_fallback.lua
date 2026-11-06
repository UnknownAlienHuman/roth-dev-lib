local secret = setmetatable({}, {
  __tostring = function() error('secret tostring') end,
  __index = function() error('secret index') end,
})
function _G.canaccessvalue(v) return v ~= secret end
function _G.issecretvalue(v) return v == secret end
function _G.canaccesstable(v) return v ~= secret end
function _G.issecrettable(v) return v == secret end
function _G.canaccessallvalues(...) return true end

local callback, registrations = nil, 0
function _G.AddLuaErrorHandler(fn)
  registrations = registrations + 1
  callback = fn
end
_G.C_AddOns = { IsAddOnLoaded = function() return false end }
_G.RothDevLib = { Capture = {} }
local RDL = RothDevLib
RDL.DB = { GetSettings = function() return { fallbackHookScriptErrors = true, importBugGrabber = true } end }
RDL.Log = function() end
assert(loadfile('Util/Util.lua'))()

local built
RDL.Capture.BuildEntry = function(...)
  built = { ... }
  return { addon = 'Demo', func = 'Test' }
end
RDL.Capture.StoreEntry = function() return 'stored' end
local enabled = 0
RDL.Capture.BugGrabber = {
  IsPresent = function() return true end,
  Enable = function() enabled = enabled + 1 end,
}
assert(loadfile('Capture/Safety.lua'))()

RDL.Capture.ownsHandler = false
RDL.Capture:InstallFallbackHooks()
assert(type(callback) == 'function')
assert(registrations == 1)
assert(enabled == 1)
assert(pcall(callback, secret, secret, { hidden = secret }))
assert(built[1] == 'LUA_ERROR')
assert(built[2] == '<inaccessible>')
assert(built[3] == '<inaccessible>')
assert(built[4].hidden == '<inaccessible>')
assert(built[7].source == 'AddLuaErrorHandler')

built = nil
RDL.Capture.ownsHandler = true
assert(pcall(callback, secret, secret, secret))
assert(built == nil)
RDL.Capture:InstallFallbackHooks()
assert(registrations == 1)

print('fallback capture tests: ok')
