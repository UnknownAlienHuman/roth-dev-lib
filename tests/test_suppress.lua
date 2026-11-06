local settings = { hideTaintPopups = true, hideBlizzardScriptErrors = true }
local hooks = {}
local hiddenPopups = {}
local unregisterCalls = 0
local originalShow = function() end
local loadWatcher

_G.hooksecurefunc = function(name, fn)
  assert(name == 'StaticPopup_Show')
  hooks[name] = fn
end
_G.StaticPopup_Show = function() end
_G.StaticPopup_Hide = function(which) hiddenPopups[#hiddenPopups + 1] = which end
_G.UIParent = { UnregisterEvent = function() unregisterCalls = unregisterCalls + 1 end }
_G.CreateFrame = function()
  loadWatcher = { scripts = {} }
  function loadWatcher:RegisterEvent(event) self.event = event end
  function loadWatcher:SetScript(name, fn) self.scripts[name] = fn end
  return loadWatcher
end

local frame = {
  shown = true,
  Show = originalShow,
  scripts = {},
  HookScript = function(self, name, fn) self.scripts[name] = fn end,
  IsShown = function(self) return self.shown end,
  Hide = function(self) self.shown = false end,
  UnregisterEvent = function() unregisterCalls = unregisterCalls + 1 end,
}
_G.ScriptErrorsFrame = frame
_G.RothDevLib = {
  addonName = '!RothDevLib',
  DB = { GetSettings = function() return settings end },
  Internal = { Call = function(_, _, _, fn) fn(); return true end },
  Log = function() end,
}

assert(loadfile('Capture/Suppress.lua'))()
RothDevLib.Suppress:SuppressAll()
assert(type(hooks.StaticPopup_Show) == 'function')
assert(frame.Show == originalShow)
assert(unregisterCalls == 0)
assert(frame.shown == false)
assert(type(frame.scripts.OnShow) == 'function')
assert(loadWatcher and loadWatcher.event == 'ADDON_LOADED')

hiddenPopups = {}
hooks.StaticPopup_Show('ADDON_ACTION_BLOCKED')
hooks.StaticPopup_Show('OTHER_DIALOG')
assert(#hiddenPopups == 1 and hiddenPopups[1] == 'ADDON_ACTION_BLOCKED')

settings.hideTaintPopups = false
hooks.StaticPopup_Show('ADDON_ACTION_FORBIDDEN')
assert(#hiddenPopups == 1)

local secretPopup = {}
RothDevLib.SecretGuard = { CanAccess = function(_, value) return value ~= secretPopup end }
assert(pcall(hooks.StaticPopup_Show, secretPopup) == true)
assert(#hiddenPopups == 1)

settings.hideBlizzardScriptErrors = false
frame.shown = true
frame.scripts.OnShow(frame)
assert(frame.shown == true)
settings.hideBlizzardScriptErrors = true
frame.scripts.OnShow(frame)
assert(frame.shown == false)

RothDevLib.Suppress:SuppressAll()
assert(unregisterCalls == 0)

local laterFrame = {
  shown = false,
  scripts = {},
  HookScript = function(self, name, fn) self.scripts[name] = fn end,
  IsShown = function(self) return self.shown end,
  Hide = function(self) self.shown = false end,
}
_G.ScriptErrorsFrame = laterFrame
loadWatcher.scripts.OnEvent(loadWatcher, 'ADDON_LOADED', 'Blizzard_ScriptErrorsFrame')
assert(type(laterFrame.scripts.OnShow) == 'function')

print('suppression tests: ok')
