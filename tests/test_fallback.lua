local secret = setmetatable({}, {
  __tostring = function() error('secret tostring') end,
  __index = function() error('secret index') end,
})
function _G.canaccessvalue(v) return v ~= secret end
function _G.issecretvalue(v) return v == secret end
function _G.canaccesstable(v) return v ~= secret end
function _G.issecrettable(v) return v == secret end
function _G.canaccessallvalues(...) return true end

local registrations = 0
function _G.AddLuaErrorHandler()
  registrations = registrations + 1
  error('ordinary addons must not register secure ScriptErrors handlers')
end
_G.C_AddOns = { IsAddOnLoaded = function() return false end }
_G.RothDevLib = { Capture = {} }
local RDL = RothDevLib
RDL.DB = { GetSettings = function()
  return { fallbackHookScriptErrors = true, importBugGrabber = true }
end }
RDL.Log = function() end
assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/BoundedCopy.lua'))()

local enabled, disabled = 0, 0
RDL.Capture.BugGrabber = {
  IsPresent = function() return true end,
  Enable = function() enabled = enabled + 1; return true end,
  Disable = function() disabled = disabled + 1 end,
}
assert(loadfile('Capture/Safety.lua'))()

RDL.Capture.ownsHandler = false
RDL.Capture:InstallFallbackHooks()
assert(registrations == 0)
assert(enabled == 1)
assert(RDL.Capture._fallback.kind == 'buggrabber')
assert(RDL.Capture._fallback.blizzardLuaHandlerHooked == false)

RDL.Capture.ownsHandler = true
RDL.Capture:InstallFallbackHooks()
assert(disabled == 1)
assert(RDL.Capture._fallback.kind == 'owned')
assert(registrations == 0)

print('fallback capture policy tests: ok')
