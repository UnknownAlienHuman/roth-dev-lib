-- !RothDevLib/Core/Events.lua
-- Lifecycle dispatcher. SavedVariables are available at file load, but the
-- player/session DB begins only at PLAYER_LOGIN.

local RDL = _G.RothDevLib
if not RDL then return end

local frame = CreateFrame("Frame", "RothDevLibEventFrame")
RDL._eventFrame = frame

local MAX_EVENT_ERRORS = 24
local MAX_INIT_WARNINGS = 24

local function SafeText(value, maximum)
  local util = RDL.Util
  local text
  if util and type(util.SafeToString) == "function" then
    local ok, rendered = pcall(util.SafeToString, util, value)
    if ok and type(rendered) == "string" then text = rendered end
  elseif type(value) == "string" then
    text = value
  end
  if type(text) ~= "string" then text = "<?>" end
  maximum = tonumber(maximum) or 2048
  if maximum < 1 then maximum = 1 end
  if #text > maximum then text = text:sub(1, maximum) .. "<truncated>" end
  return text
end

local function PushBounded(list, value, maximum)
  list[#list + 1] = value
  while #list > maximum do table.remove(list, 1) end
end

local function SafeRegisterEvent(event)
  local ok, err = pcall(frame.RegisterEvent, frame, event)
  if ok then return true end
  RDL._eventRegErrors = type(RDL._eventRegErrors) == "table" and RDL._eventRegErrors or {}
  PushBounded(RDL._eventRegErrors, {
    ts = type(_G.time) == "function" and _G.time() or 0,
    event = SafeText(event, 128),
    err = SafeText(err, 2048),
  }, MAX_EVENT_ERRORS)
  return false
end

local function ICall(name, fn, ...)
  if type(fn) ~= "function" then return false, "unavailable" end
  if RDL.Internal and type(RDL.Internal.Call) == "function" then
    return RDL.Internal:Call(RDL.addonName, name, fn, ...)
  end
  return pcall(fn, ...)
end

local function RecordInitWarning(stage, detail)
  RDL._initWarnings = type(RDL._initWarnings) == "table" and RDL._initWarnings or {}
  PushBounded(RDL._initWarnings, {
    ts = type(_G.time) == "function" and _G.time() or 0,
    stage = SafeText(stage, 128),
    detail = SafeText(detail, 2048),
  }, MAX_INIT_WARNINGS)
end

local function OptionalCall(stage, fn, ...)
  if type(fn) ~= "function" then return false, "unavailable" end
  local ok, result = ICall(stage, fn, ...)
  if not ok then RecordInitWarning(stage, result) end
  return ok, result
end

SafeRegisterEvent("ADDON_LOADED")
SafeRegisterEvent("PLAYER_LOGIN")
SafeRegisterEvent("PLAYER_LOGOUT")
SafeRegisterEvent("ADDONS_UNLOADING")
SafeRegisterEvent("SAVED_VARIABLES_TOO_LARGE")
SafeRegisterEvent("LUA_WARNING")
SafeRegisterEvent("ADDON_ACTION_BLOCKED")
SafeRegisterEvent("ADDON_ACTION_FORBIDDEN")
SafeRegisterEvent("MACRO_ACTION_BLOCKED")
SafeRegisterEvent("MACRO_ACTION_FORBIDDEN")
SafeRegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
SafeRegisterEvent("PLAYER_REGEN_ENABLED")
SafeRegisterEvent("SCREENSHOT_SUCCEEDED")
SafeRegisterEvent("SCREENSHOT_FAILED")

local shutdownDone = false

local function InvalidateChatTap()
  local capture = RDL.Capture
  local tap = capture and capture.ChatTap
  if not tap then return end
  tap._active = nil
  tap._timerToken = (tonumber(tap._timerToken) or 0) + 1
end

local function StopRuntimeConsumers()
  if RDL.Diagnostics then ICall("Diagnostics:Stop", RDL.Diagnostics.Stop, RDL.Diagnostics) end
  if RDL.Screenshots then ICall("Screenshots:Stop", RDL.Screenshots.Stop, RDL.Screenshots) end
  InvalidateChatTap()
  local capture = RDL.Capture
  if capture and capture.BugGrabber and type(capture.BugGrabber.Disable) == "function" then
    ICall("BugGrabber:Disable", capture.BugGrabber.Disable, capture.BugGrabber)
  end
  if RDL.Mem and type(RDL.Mem.StopWatcher) == "function" then
    ICall("Mem:StopWatcher", RDL.Mem.StopWatcher, RDL.Mem)
  end
end

local function FailInitialization(stage, detail)
  StopRuntimeConsumers()
  RDL._initializing = false
  RDL._initialized = false
  RDL._initGeneration = (tonumber(RDL._initGeneration) or 0) + 1
  RDL._initFailure = {
    ts = type(_G.time) == "function" and _G.time() or 0,
    stage = SafeText(stage, 128),
    detail = SafeText(detail, 2048),
  }
  if type(RDL.Log) == "function" then
    pcall(RDL.Log, RDL, "ERROR", "BOOT", "RothDevLib initialization failed", RDL._initFailure)
  end
  return false
end

local function SyncCaptureRuntimeStatus(capture)
  capture._fallback = type(capture._fallback) == "table" and capture._fallback or {}
  local chatTap = capture.ChatTap
  capture._fallback.chatTapHooked = type(chatTap) == "table" and chatTap._hooked == true
  capture.ownerInfo = type(capture.ownerInfo) == "table" and capture.ownerInfo or {}
  capture.ownerInfo.fallback = capture._fallback.kind
end

local function InitAll()
  if RDL._initialized then return true end
  if RDL._initializing or shutdownDone then return false end
  RDL._initializing = true
  RDL._initWarnings = {}

  -- DB/session readiness is the root invariant. Do not start consumers if the
  -- authoritative persistence owner failed to start.
  local db = RDL.DB
  if not (db and type(db.MarkPlayerReady) == "function" and type(db.Init) == "function") then
    return FailInitialization("DB", "owner-unavailable")
  end

  local markOK, markResult = ICall("DB:MarkPlayerReady", db.MarkPlayerReady, db)
  if not markOK then return FailInitialization("DB:MarkPlayerReady", markResult) end

  local initOK, ready = ICall("DB:Init", db.Init, db)
  if not initOK or ready ~= true then
    return FailInitialization("DB:Init", initOK and "not-ready" or ready)
  end

  -- Diagnostics helpers are useful but not allowed to strand core capture.
  if RDL.Logger then OptionalCall("Logger:Init", RDL.Logger.Init, RDL.Logger) end
  if RDL.Doctor then OptionalCall("Doctor:Init", RDL.Doctor.Init, RDL.Doctor) end
  if RDL.Validation then OptionalCall("Validation:Init", RDL.Validation.Init, RDL.Validation) end
  if RDL.Bus then OptionalCall("Bus:Init", RDL.Bus.Init, RDL.Bus) end

  -- Capture is the essential runtime service. Missing/throwing capture must not
  -- produce a false initialized state. Its boolean result describes handler
  -- ownership, not initialization success, so only call success is required.
  local capture = RDL.Capture
  if not (capture and type(capture.Init) == "function") then
    return FailInitialization("Capture:Init", "owner-unavailable")
  end
  local captureOK, captureResult = ICall("Capture:Init", capture.Init, capture)
  if not captureOK then return FailInitialization("Capture:Init", captureResult) end
  SyncCaptureRuntimeStatus(capture)

  if type(capture.FlushBootQueue) ~= "function" then
    return FailInitialization("Capture:FlushBootQueue", "unavailable")
  end
  local flushOK, flushResult = ICall("Capture:FlushBootQueue", capture.FlushBootQueue, capture)
  if not flushOK then return FailInitialization("Capture:FlushBootQueue", flushResult) end

  if RDL.Suppress then
    OptionalCall("Suppress:SuppressAll", RDL.Suppress.SuppressAll, RDL.Suppress)
  end
  if RDL.UI then
    OptionalCall("UI:Init", RDL.UI.Init, RDL.UI)
    OptionalCall("UI:UpdateTitle", RDL.UI.UpdateTitle, RDL.UI)
  end
  if RDL.Mem then
    OptionalCall("Mem:StartWatcher", RDL.Mem.StartWatcher, RDL.Mem)
  end

  if RDL.Screenshots then OptionalCall("Screenshots:Init", RDL.Screenshots.Init, RDL.Screenshots) end
  if RDL.Diagnostics then OptionalCall("Diagnostics:Init", RDL.Diagnostics.Init, RDL.Diagnostics) end

  RDL._initFailure = nil
  RDL._initialized = true
  RDL._initializing = false
  RDL._initGeneration = (tonumber(RDL._initGeneration) or 0) + 1
  local generation = RDL._initGeneration

  if RDL.UI and type(RDL.UI.InitMinimapButton) == "function" then
    local function InitMinimap()
      if shutdownDone or not RDL._initialized or RDL._initGeneration ~= generation then return end
      OptionalCall("UI:InitMinimapButton", RDL.UI.InitMinimapButton, RDL.UI)
    end
    local timers = _G.C_Timer
    if type(timers) == "table" and type(timers.After) == "function" then
      local okTimer, timerError = pcall(timers.After, 0.25, InitMinimap)
      if not okTimer then
        RecordInitWarning("UI:InitMinimapButton:timer", timerError)
        InitMinimap()
      end
    else
      InitMinimap()
    end
  end

  if type(RDL.Log) == "function" then
    pcall(RDL.Log, RDL, "INFO", "BOOT", "RothDevLib initialized", {
      version = RDL.version,
      captureOwned = captureResult == true,
      chatTapHooked = capture._fallback and capture._fallback.chatTapHooked == true,
      bootEntriesFlushed = tonumber(flushResult) or 0,
      warnings = #RDL._initWarnings,
    })
  end
  return true
end

local function Shutdown(reason)
  if shutdownDone then return false end
  shutdownDone = true
  RDL._initGeneration = (tonumber(RDL._initGeneration) or 0) + 1
  RDL._initialized = false
  RDL._initializing = false

  StopRuntimeConsumers()
  if RDL.Diagnostics then
    ICall("Diagnostics:Checkpoint", RDL.Diagnostics.Checkpoint, RDL.Diagnostics, reason)
  end
  if RDL.DB and type(RDL.DB.OnShutdown) == "function" then
    ICall("DB:OnShutdown", RDL.DB.OnShutdown, RDL.DB, reason)
  end
  return true
end

local function HandlePersistenceFailure(addonName)
  if addonName ~= RDL.addonName and addonName ~= RDL.name
      and addonName ~= "!RothDevLib" then
    return false
  end

  local db = RDL.DB
  if not (db and type(db.HandlePersistenceFailure) == "function") then return false end
  local ok, handled = pcall(db.HandlePersistenceFailure, db, addonName)
  if ok then
    if handled == true then
      if RDL.Diagnostics then ICall("Diagnostics:Stop", RDL.Diagnostics.Stop, RDL.Diagnostics) end
      if RDL.Screenshots then ICall("Screenshots:Stop", RDL.Screenshots.Stop, RDL.Screenshots) end
    end
    return handled == true
  end

  if type(_G.print) == "function" then
    pcall(_G.print,
      "|cffff3333RothDevLib|r SavedVariables recovery failed; use "
      .. "|cffffff00/rdev clear|r and |cffffff00/reload|r.")
  end
  return false
end

local FALLBACK_ADDONS = {
  ["!BugGrabber"] = true,
  BugGrabber = true,
  BugSack = true,
}

local function RefreshLateFallback(addonName)
  if not RDL._initialized or not FALLBACK_ADDONS[addonName] then return false end
  local capture = RDL.Capture
  if not capture or capture.ownsHandler == true
      or type(capture.InstallFallbackHooks) ~= "function" then
    return false
  end
  local ok, result = ICall("Capture:InstallFallbackHooks",
    capture.InstallFallbackHooks, capture)
  if not ok then RecordInitWarning("Capture:InstallFallbackHooks", result) end
  if ok then SyncCaptureRuntimeStatus(capture) end
  return ok
end

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if RDL.Diagnostics then RDL.Diagnostics._inventoryDirty = true end
    if name == RDL.addonName then
      -- File loading is complete, but player/session state is still deferred.
      if RDL.Logger then OptionalCall("Logger:Init", RDL.Logger.Init, RDL.Logger) end
      if RDL.Validation then OptionalCall("Validation:Init", RDL.Validation.Init, RDL.Validation) end
      if RDL.Capture and type(RDL.Capture.EarlyInit) == "function" then
        local ok, result = ICall("Capture:EarlyInit", RDL.Capture.EarlyInit, RDL.Capture)
        if not ok then RecordInitWarning("Capture:EarlyInit", result) end
      end
      if RDL.SelfCheckEarly then
        OptionalCall("RDL:SelfCheckEarly", RDL.SelfCheckEarly, RDL, "ADDON_LOADED")
      end
    else
      if name == "Blizzard_DebugTools" or name == "Blizzard_ScriptErrors"
          or name == "Blizzard_ScriptErrorsFrame" then
        if RDL.Suppress then
          OptionalCall("Suppress:SuppressAll", RDL.Suppress.SuppressAll, RDL.Suppress)
        end
      end
      RefreshLateFallback(name)
    end
    return
  end

  if event == "PLAYER_LOGIN" then
    if not InitAll() then return end
    if RDL.SelfCheckEarly then
      OptionalCall("RDL:SelfCheckEarly", RDL.SelfCheckEarly, RDL, "PLAYER_LOGIN")
    end
    if RDL.Validation then
      OptionalCall("Validation:MaybeContinueReloadLoop",
        RDL.Validation.MaybeContinueReloadLoop, RDL.Validation)
    end
    return
  end

  if event == "PLAYER_LOGOUT" or event == "ADDONS_UNLOADING" then
    Shutdown(event)
    return
  end

  if event == "SAVED_VARIABLES_TOO_LARGE" then
    HandlePersistenceFailure(...)
    return
  end

  if event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then
    if RDL.Screenshots then
      ICall("Screenshots:OnEvent", RDL.Screenshots.OnEvent, RDL.Screenshots, event)
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
