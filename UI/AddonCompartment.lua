-- !RothDevLib/UI/AddonCompartment.lua
-- Blizzard Addon Compartment integration (automatic via TOC metadata).
-- Ported from RothDevLib/UI/AddonCompartment.lua (no changes needed).
--
-- These global functions are referenced by TOC fields:
--   ## AddonCompartmentFunc
--   ## AddonCompartmentFuncOnEnter
--   ## AddonCompartmentFuncOnLeave

local RDL = _G.RothDevLib
RDL.UI = RDL.UI or {}
local UI = RDL.UI

local function GetUnread()
  if UI and UI.GetUnreadCount then
    local ok, n = pcall(function()
      return UI:GetUnreadCount()
    end)
    if ok then
      return tonumber(n) or 0
    end
  end
  return 0
end

function RothDevLib_OnAddonCompartmentClick(addonName, buttonName, menuButtonFrame)
  if UI and UI.Toggle then
    UI:Toggle()
  end
end

function RothDevLib_OnAddonCompartmentEnter(addonName, menuButtonFrame)
  if not GameTooltip or not menuButtonFrame then return end
  GameTooltip:SetOwner(menuButtonFrame, "ANCHOR_RIGHT")
  GameTooltip:SetText("RothDevLib")

  local unread = GetUnread()
  if unread > 0 then
    GameTooltip:AddLine("New since last open: " .. tostring(unread), 1, 0.82, 0)
  end

  GameTooltip:AddLine("Left click: open/close", 0.8, 0.8, 0.8)
  GameTooltip:AddLine("/rdev export: copy report", 0.8, 0.8, 0.8)
  GameTooltip:Show()
end

function RothDevLib_OnAddonCompartmentLeave(addonName, menuButtonFrame)
  if GameTooltip then
    GameTooltip:Hide()
  end
end
