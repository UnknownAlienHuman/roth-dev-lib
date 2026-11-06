-- !RothDevLib/UI/Menu.lua
-- Narrow wrapper around Blizzard_Menu dropdown APIs used by the UI.

local RDL = _G.RothDevLib
if not RDL then return end

RDL.UI = RDL.UI or {}
local UI = RDL.UI

local Menu = {}
UI.Menu = Menu

local function SafeCall(fn, ...)
  if type(fn) ~= "function" then return false, nil end
  return pcall(fn, ...)
end

local function HasMenuAPI()
  return type(_G.MenuUtil) == "table"
    and type(MenuUtil.CreateContextMenu) == "function"
end

function Menu:EnsureLoaded()
  if HasMenuAPI() then return true end

  if not self._loadAttempted then
    self._loadAttempted = true
    local addons = _G.C_AddOns
    if type(addons) == "table" and type(addons.LoadAddOn) == "function" then
      SafeCall(addons.LoadAddOn, "Blizzard_Menu")
    end
  end

  return HasMenuAPI()
end

function Menu:SupportsWowStyleDropdown()
  if self._supportsWowStyle ~= nil then return self._supportsWowStyle end
  if not self:EnsureLoaded() or type(_G.CreateFrame) ~= "function" then
    self._supportsWowStyle = false
    return false
  end

  local ok, probe = SafeCall(CreateFrame, "DropdownButton", nil, UIParent, "WowStyle1FilterDropdownTemplate")
  if ok and probe then
    probe:Hide()
    self._supportsWowStyle = true
  else
    self._supportsWowStyle = false
  end

  return self._supportsWowStyle
end

local function SetDefaultText(dropdown, value)
  local U = RDL.Util
  local ordinary = value
  if U and U.Scrub then
    local ok, scrubbed = pcall(U.Scrub, U, value)
    if ok then ordinary = scrubbed else ordinary = "<unavailable>" end
  end
  if ordinary == nil then return end

  local text = "<unavailable>"
  if U and U.SafeToString then
    local ok, rendered = pcall(U.SafeToString, U, ordinary)
    if ok and type(rendered) == "string" then text = rendered end
  elseif type(ordinary) == "string" then
    text = ordinary
  end

  if dropdown.SetDefaultText then
    SafeCall(dropdown.SetDefaultText, dropdown, text)
  elseif dropdown.SetText then
    SafeCall(dropdown.SetText, dropdown, text)
  elseif dropdown.Text and dropdown.Text.SetText then
    SafeCall(dropdown.Text.SetText, dropdown.Text, text)
  elseif dropdown.ButtonText and dropdown.ButtonText.SetText then
    SafeCall(dropdown.ButtonText.SetText, dropdown.ButtonText, text)
  end
end

function Menu:CreateFilterDropdown(parent, name, width, defaultText, template)
  if not self:SupportsWowStyleDropdown() then return nil end
  template = template or "WowStyle1FilterDropdownTemplate"

  local ok, dropdown = SafeCall(CreateFrame, "DropdownButton", name, parent, template)
  if not ok or not dropdown then return nil end

  if dropdown.SetWidth then
    local widthValue = width
    local U = RDL.Util
    if U and U.Scrub then
      local ok, scrubbed = pcall(U.Scrub, U, width)
      if ok then widthValue = scrubbed else widthValue = nil end
    end
    local numericWidth = tonumber(widthValue)
    if numericWidth then SafeCall(dropdown.SetWidth, dropdown, numericWidth) end
  end

  SetDefaultText(dropdown, defaultText)
  return dropdown
end

function Menu:SafeGenerate(dropdown)
  if dropdown and type(dropdown.GenerateMenu) == "function" then
    SafeCall(dropdown.GenerateMenu, dropdown)
  end
end
