-- !RothDevLib/Capture/Suppress.lua
-- Suppression of Blizzard error/taint UI popups.
-- Extracted from monolithic Capture.lua.

local RDL = _G.RothDevLib
local Suppress = {}
RDL.Suppress = Suppress

local function SuppressStaticPopup(which)
  local dlg = _G.StaticPopupDialogs and _G.StaticPopupDialogs[which]
  if not dlg or dlg._RDLWrapped then return end
  local prev = dlg.OnShow
  dlg.OnShow = function(self, ...)
    local settings = RDL.DB and RDL.DB:GetSettings()
    if settings and settings.hideTaintPopups then
      self:Hide()
      return
    end
    if prev then
      return prev(self, ...)
    end
  end
  dlg._RDLWrapped = true
end

function Suppress:SuppressBlizzardPopups()
  SuppressStaticPopup("ADDON_ACTION_BLOCKED")
  SuppressStaticPopup("ADDON_ACTION_FORBIDDEN")
end

function Suppress:SuppressScriptErrorsFrame()
  local settings = RDL.DB and RDL.DB:GetSettings()
  if not (settings and settings.hideBlizzardScriptErrors) then return end
  local f = _G.ScriptErrorsFrame
  if not f then return end
  f:Hide()
  if not f._RDLWrapped then
    f._RDL_OrigShow = f.Show
    f.Show = function(self, ...) self:Hide() end
    f:HookScript("OnShow", function(self) self:Hide() end)
    f._RDLWrapped = true
  end
end

function Suppress:SuppressDefaultLuaWarning()
  local settings = RDL.DB and RDL.DB:GetSettings()
  if not (settings and settings.hideBlizzardScriptErrors) then return end

  pcall(function()
    if UIParent and UIParent.UnregisterEvent then
      UIParent:UnregisterEvent("LUA_WARNING")
    end
    if ScriptErrorsFrame and ScriptErrorsFrame.UnregisterEvent then
      ScriptErrorsFrame:UnregisterEvent("LUA_WARNING")
    end
  end)
end

-- Convenience: suppress everything in one call.
function Suppress:SuppressAll()
  pcall(function() self:SuppressBlizzardPopups() end)
  pcall(function() self:SuppressScriptErrorsFrame() end)
  pcall(function() self:SuppressDefaultLuaWarning() end)
end
