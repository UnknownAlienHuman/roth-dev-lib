-- !RothDevLib/Capture/Suppress.lua
-- Non-invasive suppression of Blizzard error/taint presentation.

local RDL = _G.RothDevLib
local Suppress = {}
RDL.Suppress = Suppress

local TAINT_POPUPS = {
  ADDON_ACTION_BLOCKED = true,
  ADDON_ACTION_FORBIDDEN = true,
}

local hookedScriptErrorFrames = setmetatable({}, { __mode = "k" })
local SCRIPT_ERROR_ADDONS = {
  Blizzard_DebugTools = true,
  Blizzard_ScriptErrors = true,
  Blizzard_ScriptErrorsFrame = true,
}

local function OrdinaryString(value)
  local guard = RDL.SecretGuard
  if guard and type(guard.CanAccess) == "function" then
    local ok, accessible = pcall(guard.CanAccess, guard, value)
    if not ok or not accessible then return nil end
  elseif type(_G.canaccessvalue) == "function" then
    local ok, accessible = pcall(_G.canaccessvalue, value)
    if not ok or not accessible then return nil end
  end

  if value == nil or type(value) ~= "string" then return nil end
  return value
end

local function SafeError(value)
  local util = RDL.Util
  if util and type(util.SafeToString) == "function" then
    local ok, text = pcall(util.SafeToString, util, value)
    if ok and type(text) == "string" then return text end
  end
  return "<error>"
end

local function GetSettings()
  if not (RDL.DB and type(RDL.DB.GetSettings) == "function") then return nil end
  local ok, settings = pcall(RDL.DB.GetSettings, RDL.DB)
  if ok and type(settings) == "table" then return settings end
  return nil
end

local function ShouldHideTaintPopup(which)
  which = OrdinaryString(which)
  if not which then return false end
  local settings = GetSettings()
  return settings and settings.hideTaintPopups == true and TAINT_POPUPS[which] == true
end

local function ShouldHideScriptErrors()
  local settings = GetSettings()
  return settings and settings.hideBlizzardScriptErrors == true
end

local function HideTaintPopup(which)
  which = OrdinaryString(which)
  if not which or not ShouldHideTaintPopup(which) then return end
  local hide = _G.StaticPopup_Hide
  if type(hide) == "function" then pcall(hide, which) end
end

function Suppress:SuppressBlizzardPopups()
  if not self._staticPopupHooked and type(_G.hooksecurefunc) == "function"
     and type(_G.StaticPopup_Show) == "function" then
    local ok = pcall(_G.hooksecurefunc, "StaticPopup_Show", function(which)
      HideTaintPopup(which)
    end)
    self._staticPopupHooked = ok == true
  end

  if ShouldHideTaintPopup("ADDON_ACTION_BLOCKED") then
    HideTaintPopup("ADDON_ACTION_BLOCKED")
    HideTaintPopup("ADDON_ACTION_FORBIDDEN")
  end
end

function Suppress:SuppressScriptErrorsFrame()
  local frame = _G.ScriptErrorsFrame
  if not frame then return end

  if not hookedScriptErrorFrames[frame] and type(frame.HookScript) == "function" then
    local ok = pcall(frame.HookScript, frame, "OnShow", function(owner)
      if ShouldHideScriptErrors() and type(owner.Hide) == "function" then
        pcall(owner.Hide, owner)
      end
    end)
    if ok then hookedScriptErrorFrames[frame] = true end
  end

  local shown = false
  if type(frame.IsShown) == "function" then
    local ok, value = pcall(frame.IsShown, frame)
    shown = ok and value == true
  end
  if ShouldHideScriptErrors() and shown and type(frame.Hide) == "function" then
    pcall(frame.Hide, frame)
  end
end

function Suppress:EnsureLoadWatcher()
  if self._loadWatcher or type(_G.CreateFrame) ~= "function" then return end

  local ok, watcher = pcall(_G.CreateFrame, "Frame")
  if not ok or not watcher or type(watcher.RegisterEvent) ~= "function"
     or type(watcher.SetScript) ~= "function" then
    return
  end

  self._loadWatcher = watcher
  watcher:RegisterEvent("ADDON_LOADED")
  watcher:SetScript("OnEvent", function(_, _, addonName)
    addonName = OrdinaryString(addonName)
    if addonName and SCRIPT_ERROR_ADDONS[addonName] then
      Suppress:SuppressScriptErrorsFrame()
    end
  end)
end

function Suppress:SuppressDefaultLuaWarning()
  -- Presentation only: Blizzard keeps ownership of LUA_WARNING and its frames.
  self:SuppressScriptErrorsFrame()
end

local function Run(name, fn)
  if RDL.Internal and type(RDL.Internal.Call) == "function" then
    RDL.Internal:Call(RDL.addonName, name, fn)
    return
  end

  local ok, err = pcall(fn)
  if not ok and RDL.Log then
    RDL:Log("ERROR", "SUPPRESS", name .. " failed", { error = SafeError(err) })
  end
end

function Suppress:SuppressAll()
  Run("SuppressBlizzardPopups", function() self:SuppressBlizzardPopups() end)
  Run("SuppressLoadWatcher", function() self:EnsureLoadWatcher() end)
  Run("SuppressScriptErrorsFrame", function() self:SuppressScriptErrorsFrame() end)
end
