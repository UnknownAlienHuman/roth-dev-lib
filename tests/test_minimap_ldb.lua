local settings = { minimap = { hide = false, minimapPos = 225 } }
local timerCallback
local registerCount = 0
local showCount = 0
local internalButton

local function NewVisual()
  return setmetatable({}, { __index = function(t, key)
    local fn = function() end
    rawset(t, key, fn)
    return fn
  end })
end

local function NewButton()
  local button = { scripts = {}, shown = true, icon = NewVisual() }
  function button:CreateFontString() return NewVisual() end
  function button:HookScript(name, fn) self.scripts[name] = fn end
  function button:IsShown() return self.shown end
  return button
end

local LDB = {}
function LDB:NewDataObject(_, data) return data end

local LDBIcon = {}
function LDBIcon:Register()
  registerCount = registerCount + 1
  internalButton = NewButton()
  _G.LibDBIcon10_RothDevLib = internalButton
end
function LDBIcon:GetMinimapButton() return internalButton end
function LDBIcon:Show()
  showCount = showCount + 1
  if not internalButton then internalButton = NewButton() end
  internalButton.shown = true
  _G.LibDBIcon10_RothDevLib = internalButton
end
function LDBIcon:Hide()
  if internalButton then internalButton.shown = false end
end

local libraries = {
  ['LibDataBroker-1.1'] = LDB,
  ['LibDBIcon-1.0'] = LDBIcon,
}
_G.LibStub = function(name) return libraries[name] end
_G.C_Timer = { After = function(_, fn) timerCallback = fn end }
_G.IsShiftKeyDown = function() return false end
_G.RothDevLib = {
  DB = {
    GetSettings = function() return settings end,
    GetActiveGroupCount = function() return 1 end,
  },
  UI = {
    Toggle = function() end,
    OpenLog = function() end,
    OpenExportAll = function() end,
  },
  Capture = { ownsHandler = true },
  Log = function() end,
}

assert(loadfile('UI/MinimapButton.lua'))()
RothDevLib.UI:InitMinimapButton()
assert(registerCount == 1, registerCount)
assert(type(timerCallback) == 'function')

-- Lose the concrete button but keep the registration. Recovery must use the
-- library API, not call Register a second time.
internalButton = nil
_G.LibDBIcon10_RothDevLib = nil
timerCallback()
assert(registerCount == 1, registerCount)
assert(showCount >= 2, showCount) -- initial Show plus recovery Show
assert(internalButton ~= nil)
assert(RothDevLib.UI._ldbInited == true)
assert(RothDevLib.UI._ldbRegistered == true)
print('LDB minimap tests: ok')
