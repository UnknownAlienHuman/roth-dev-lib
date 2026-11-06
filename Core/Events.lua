-- !RothDevLib/Core/Events.lua
-- Lifecycle dispatcher. SavedVariables are available at file load, but the
-- player/session DB begins only at PLAYER_LOGIN.

local RDL = _G.RothDevLib
if not RDL then return end

local frame = CreateFrame("Frame", "RothDevLibEventFrame")
RDL._eventFrame = frame

local function SafeText(value)
  local util = RDL.Util
  if util and type(util.SafeToString) == "function" then
    local ok, text = pcall(util.SafeToString, util, value)
    if ok and type(text) == "string" then return text end
  end
  return type(value) == "string" and value or "<?>"
end

local function SafeRegisterEvent(event)
  local ok, err = pcall(frame.RegisterEvent, frame, event)
  if ok then return end
  RDL._eventRegErrors = RDL._eventRegErrors or {}
  RDL._eventRegErrors[#RDL._eventRegErrors + 1] = {
    ts = type(_G.time) == "function" and _G.time() or 0,
    event = SafeText(event),
    err = SafeText(err),
  }
end

local function ICall(name, fn, ...)
  if type(fn) ~= "function" then return false, "unavailable" end
  if RDL.Internal and type(RDL.Internal.Call) == "function" then
    return RDL.Internal:Call(RDL.addonName, name, fn, ...)
  end
  return pcall(fn, ...)
end

SafeRegisterEvent("ADDON_LOADED")
SafeRegisterEvent("PLAYER_LOGIN")
SafeRegisterEvent("PLAYER_LOGOUT")
SafeRegisterEvent("LUA_WARNING")
SafeRegisterEvent("ADDON_ACTION_BLOCKED")
SafeRegisterEvent("ADDON_ACTION_FORBIDDEN")
SafeRegisterEvent("MACRO_ACTION_BLOCKED")
SafeRegisterEvent("MACRO_ACTION_FORBIDDEN")
SafeRegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
SafeRegisterEvent("PLAYER_REGEN_ENABLED")

local function InitAll()
  if RDL._initialized or RDL._initializing then return end
  RDL._initializing = true

  -- This is the first boundary that may construct player/session state.
  if RDL.DB and RDL.DB.MarkPlayerReady then
    ICall("DB:MarkPlayerReady", RDL.DB.MarkPlayerReady, RDL.DB)
  end
  if RDL.DB and RDL.DB.Init then ICall("DB:Init", RDL.DB.Init, RDL.DB) end

  if RDL.Logger and RDL.Logger.Init then ICall("Logger:Init", RDL.Logger.Init, RDL.Logger) end
  if RDL.Doctor and RDL.Doctor.Init then ICall("Doctor:Init", RDL.Doctor.Init, RDL.Doctor) end
  if RDL.Validation and RDL.Validation.Init then
    ICall("Validation:Init", RDL.Validation.Init, RDL.Validation)
  end
  if RDL.Bus and RDL.Bus.Init then ICall("Bus:Init", RDL.Bus.Init, RDL.Bus) end

  if RDL.Mem and RDL.Mem.StartWatcher then
    ICall("Mem:StartWatcher", RDL.Mem.StartWatcher, RDL.Mem)
  end
  if RDL.Capture and RDL.Capture.Init then
    ICall("Capture:Init", RDL.Capture.Init, RDL.Capture)
  end
  if RDL.Capture and RDL.Capture.FlushBootQueue then
    ICall("Capture:FlushBootQueue", RDL.Capture.FlushBootQueue, RDL.Capture)
  end
  if RDL.Suppress and RDL.Suppress.SuppressAll then
    ICall("Suppress:SuppressAll", RDL.Suppress.SuppressAll, RDL.Suppress)
  end

  if RDL.UI and RDL.UI.Init then ICall("UI:Init", RDL.UI.Init, RDL.UI) end
  if RDL.UI and RDL.UI.UpdateTitle then
    ICall("UI:UpdateTitle", RDL.UI.UpdateTitle, RDL.UI)
  end

  if RDL.UI and RDL.UI.InitMinimapButton then
    local timers = _G.C_Timer
    if type(timers) == "table" and type(timers.After) == "function" then
      pcall(timers.After, 0.25, function()
        ICall("UI:InitMinimapButton", RDL.UI.InitMinimapButton, RDL.UI)
      end)
    else
      ICall("UI:InitMinimapButton", RDL.UI.InitMinimapButton, RDL.UI)
    end
  end

  RDL._initialized = true
  RDL._initializing = false
  if type(RDL.Log) == "function" then
    RDL:Log("INFO", "BOOT", "RothDevLib initialized", { version = RDL.version })
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == RDL.addonName then
      -- File loading is complete, but player/session state is still deferred.
      if RDL.Logger and RDL.Logger.Init then
        ICall("Logger:Init", RDL.Logger.Init, RDL.Logger)
      end
      if RDL.Validation and RDL.Validation.Init then
        ICall("Validation:Init", RDL.Validation.Init, RDL.Validation)
      end
      if RDL.Capture and RDL.Capture.EarlyInit then
        ICall("Capture:EarlyInit", RDL.Capture.EarlyInit, RDL.Capture)
      end
      if RDL.SelfCheckEarly then
        ICall("RDL:SelfCheckEarly", RDL.SelfCheckEarly, RDL, "ADDON_LOADED")
      end
    elseif name == "Blizzard_DebugTools" or name == "Blizzard_ScriptErrors"
        or name == "Blizzard_ScriptErrorsFrame" then
      if RDL.Suppress and RDL.Suppress.SuppressAll then
        ICall("Suppress:SuppressAll", RDL.Suppress.SuppressAll, RDL.Suppress)
      end
    end
    return
  end

  if event == "PLAYER_LOGIN" then
    InitAll()
    if RDL.SelfCheckEarly then
      ICall("RDL:SelfCheckEarly", RDL.SelfCheckEarly, RDL, "PLAYER_LOGIN")
    end
    if RDL.Validation and RDL.Validation.MaybeContinueReloadLoop then
      ICall("Validation:MaybeContinueReloadLoop",
        RDL.Validation.MaybeContinueReloadLoop, RDL.Validation)
    end
    return
  end

  if event == "PLAYER_LOGOUT" then
    if RDL.Capture and RDL.Capture.BugGrabber
        and RDL.Capture.BugGrabber.Disable then
      ICall("BugGrabber:Disable", RDL.Capture.BugGrabber.Disable,
        RDL.Capture.BugGrabber)
    end
    if RDL.Mem and RDL.Mem.StopWatcher then
      ICall("Mem:StopWatcher", RDL.Mem.StopWatcher, RDL.Mem)
    end
    if RDL.DB and RDL.DB.OnShutdown then
      ICall("DB:OnShutdown", RDL.DB.OnShutdown, RDL.DB)
    end
    return
  end

  local capture = RDL.Capture
  if not capture then return end

  if event == "LUA_WARNING" then
    ICall("Capture:OnLuaWarning", capture.OnLuaWarning, capture, ...)
  elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN"
      or event == "MACRO_ACTION_BLOCKED" or event == "MACRO_ACTION_FORBIDDEN" then
    ICall("Capture:OnTaintEvent", capture.OnTaintEvent, capture, event, ...)
  elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
    ICall("Capture:OnRestrictionStateChanged",
      capture.OnRestrictionStateChanged, capture, event, ...)
  elseif event == "PLAYER_REGEN_ENABLED" then
    ICall("Capture:OnLeaveCombat", capture.OnLeaveCombat, capture)
  end
end)
