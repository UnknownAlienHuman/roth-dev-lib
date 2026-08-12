-- !RothDevLib/UI/Menu.lua
-- Wrapper for Blizzard_Menu dropdown/menu system (11.0+).
-- Goal: keep UI modules free of version checks and reduce risk of UIDropDownMenu taint.
--
-- Primary public helpers:
--   * Menu:EnsureLoaded()
--   * Menu:SupportsWowStyleDropdown()
--   * Menu:CreateFilterDropdown(parent, name, width, defaultText[, template])
--   * Menu:SafeGenerate(dropdown)

local RDL = _G.RothDevLib
if not RDL then return end

RDL.UI = RDL.UI or {}
local UI = RDL.UI

local Menu = {}
UI.Menu = Menu

local function SafeCall(fn, ...)
  local ok, err = pcall(fn, ...)
  return ok, err
end

function Menu:EnsureLoaded()
  if self._ensureAttempted then
    return (MenuUtil and MenuUtil.CreateContextMenu) and true or false
  end
  self._ensureAttempted = true

  -- Blizzard_Menu is load-on-demand on some builds.
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    if type(UIParentLoadAddOn) == "function" then
      SafeCall(UIParentLoadAddOn, "Blizzard_Menu")
    end
  end

  return (MenuUtil and MenuUtil.CreateContextMenu) and true or false
end

function Menu:SupportsWowStyleDropdown()
  if self._supportsWowStyle ~= nil then return self._supportsWowStyle end
  self:EnsureLoaded()

  if type(CreateFrame) ~= "function" then
    self._supportsWowStyle = false
    return false
  end

  local ok, dd = SafeCall(CreateFrame, "DropdownButton", nil, UIParent, "WowStyle1FilterDropdownTemplate")
  if ok and dd then
    dd:Hide()
    self._supportsWowStyle = true
  else
    self._supportsWowStyle = false
  end

  return self._supportsWowStyle
end

function Menu:CreateFilterDropdown(parent, name, width, defaultText, template)
  if not self:SupportsWowStyleDropdown() then return nil end
  template = template or "WowStyle1FilterDropdownTemplate"

  local ok, dd = SafeCall(CreateFrame, "DropdownButton", name, parent, template)
  if not (ok and dd) then return nil end

  if width and dd.SetWidth then
    SafeCall(dd.SetWidth, dd, tonumber(width) or width)
  end

  if defaultText then
    local t = tostring(defaultText)
    if dd.SetDefaultText then
      SafeCall(dd.SetDefaultText, dd, t)
    elseif dd.SetText then
      SafeCall(dd.SetText, dd, t)
    elseif dd.Text and dd.Text.SetText then
      SafeCall(dd.Text.SetText, dd.Text, t)
    elseif dd.ButtonText and dd.ButtonText.SetText then
      SafeCall(dd.ButtonText.SetText, dd.ButtonText, t)
    end
  end

  return dd
end

function Menu:SafeGenerate(dropdown)
  if not dropdown then return end
  if type(dropdown.GenerateMenu) == "function" then
    SafeCall(dropdown.GenerateMenu, dropdown)
  end
end
