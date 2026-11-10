-- !RothDevLib/UI/AddonCompartment.lua
-- Blizzard Addon Compartment integration (registered through TOC metadata).

local RDL = _G.RothDevLib
RDL.UI = RDL.UI or {}
local UI = RDL.UI

local function GetUnread()
  if UI and type(UI.GetUnreadCount) == "function" then
    local ok, n = pcall(UI.GetUnreadCount, UI)
    if ok then
      return tonumber(n) or 0
    end
  end
  return 0
end

function RothDevLib_OnAddonCompartmentClick(_addonName, _buttonName)
  if not UI or type(UI.Toggle) ~= "function" then return end
  if RDL.Internal and type(RDL.Internal.Call) == "function" then
    RDL.Internal:Call(RDL.addonName, "UI:Toggle", UI.Toggle, UI)
  else
    pcall(UI.Toggle, UI)
  end
end

function RothDevLib_OnAddonCompartmentEnter(_addonName, menuButtonFrame)
  local tooltip = _G.GameTooltip
  if not tooltip or not menuButtonFrame then return end

  tooltip:SetOwner(menuButtonFrame, "ANCHOR_RIGHT")
  tooltip:SetText("RothDevLib")

  local unread = GetUnread()
  if unread > 0 then
    tooltip:AddLine("New since last open: " .. tostring(unread), 1, 0.82, 0)
  end

  tooltip:AddLine("Left click: open/close", 0.8, 0.8, 0.8)
  tooltip:AddLine("/rdev export: copy report", 0.8, 0.8, 0.8)
  tooltip:Show()
end

function RothDevLib_OnAddonCompartmentLeave(_addonName, menuButtonFrame)
  local tooltip = _G.GameTooltip
  if tooltip and tooltip.GetOwner and tooltip:GetOwner() == menuButtonFrame then
    tooltip:Hide()
  end
end
