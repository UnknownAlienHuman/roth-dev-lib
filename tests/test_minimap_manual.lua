local cursorX, cursorY = 200, 100
local settings = { minimap = { hide = false, minimapPos = 225 } }
local timerCallback
local tooltipOwner

local function NewVisual()
  return setmetatable({}, { __index = function(t, key)
    local fn = function() end
    rawset(t, key, fn)
    return fn
  end })
end

local function NewButton()
  local button = { scripts = {}, shown = true }
  function button:SetSize() end
  function button:SetFrameStrata() end
  function button:SetFrameLevel() end
  function button:SetHighlightTexture() end
  function button:CreateTexture() return NewVisual() end
  function button:CreateFontString() return NewVisual() end
  function button:RegisterForClicks() end
  function button:RegisterForDrag() end
  function button:SetMovable() end
  function button:SetScript(name, fn) self.scripts[name] = fn end
  function button:HookScript(name, fn) self.scripts['hook:' .. name] = fn end
  function button:ClearAllPoints() end
  function button:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
  function button:Show() self.shown = true end
  function button:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
  function button:IsShown() return self.shown end
  return button
end

_G.Minimap = { GetCenter = function() return 100, 100 end }
_G.UIParent = { GetEffectiveScale = function() return 1 end }
_G.GetCursorPosition = function() return cursorX, cursorY end
_G.CreateFrame = function() return NewButton() end
_G.IsShiftKeyDown = function() return false end
_G.C_Timer = { After = function(_, fn) timerCallback = fn end }
_G.GameTooltip = {
  SetOwner = function(_, owner) tooltipOwner = owner end,
  GetOwner = function() return tooltipOwner end,
  AddLine = function() end,
  Show = function() end,
  Hide = function() tooltipOwner = nil end,
}
_G.RothDevLibDB = { settings = settings }
_G.RothDevLib = {
  DB = {
    GetSettings = function() return settings end,
    GetActiveGroupCount = function() return 3 end,
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
local button = RothDevLib.UI.minimapButton
assert(button and type(button.scripts.OnDragStart) == 'function')

button.scripts.OnDragStart(button)
assert(type(button.scripts.OnUpdate) == 'function')
button.scripts.OnUpdate(button)
assert(math.abs(settings.minimap.minimapPos - 0) < 0.001, settings.minimap.minimapPos)

cursorX, cursorY = 100, 200
button.scripts.OnUpdate(button)
assert(math.abs(settings.minimap.minimapPos - 90) < 0.001, settings.minimap.minimapPos)

button.scripts.OnDragStop(button)
assert(button.scripts.OnUpdate == nil)
button.scripts.OnDragStart(button)
button:Hide()
assert(button.scripts.OnUpdate == nil)
assert(type(timerCallback) == 'function')
timerCallback()
print('manual minimap tests: ok')
