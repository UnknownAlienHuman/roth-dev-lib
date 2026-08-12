-- !RothDevLib/Core/Events.lua
-- System-level event routing + initialization.
-- Ported from !RothGrabber/Core/Events.lua.
-- Adapted for single-addon architecture (no separate UI addon).

local RDL = _G.RothDevLib

local frame = CreateFrame("Frame", "RothDevLibEventFrame")
RDL._eventFrame = frame

-- Registering unknown events throws since 8.0.1; keep startup resilient.
local function SafeRegisterEvent(ev)
  local ok, err = pcall(function() frame:RegisterEvent(ev) end)
  if not ok then
    RDL._eventRegErrors = RDL._eventRegErrors or {}
    table.insert(RDL._eventRegErrors, { ts = time(), event = tostring(ev), err = tostring(err) })
  end
end

local function ICall(funcName, fn, ...)
  if RDL and RDL.Internal and RDL.Internal.Call then
    return RDL.Internal:Call(RDL.addonName, funcName, fn, ...)
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
  if RDL._initialized then return end

  -- Core modules
  if RDL.DB and RDL.DB.Init then ICall("DB:Init", RDL.DB.Init, RDL.DB) end
  if RDL.Logger and RDL.Logger.Init then ICall("Logger:Init", RDL.Logger.Init, RDL.Logger) end
  if RDL.Doctor and RDL.Doctor.Init then ICall("Doctor:Init", RDL.Doctor.Init, RDL.Doctor) end
  if RDL.Validation and RDL.Validation.Init then ICall("Validation:Init", RDL.Validation.Init, RDL.Validation) end
  if RDL.Bus and RDL.Bus.Init then ICall("Bus:Init", RDL.Bus.Init, RDL.Bus) end

  -- Perf watcher (optional)
  if RDL.Mem and RDL.Mem.StartWatcher then ICall("Mem:StartWatcher", RDL.Mem.StartWatcher, RDL.Mem) end

  -- Capture engine
  if RDL.Capture and RDL.Capture.Init then ICall("Capture:Init", RDL.Capture.Init, RDL.Capture) end

  -- UI (all in one addon now)
  if RDL.UI and RDL.UI.Init then ICall("UI:Init", RDL.UI.Init, RDL.UI) end
  if RDL.UI and RDL.UI.UpdateTitle then ICall("UI:UpdateTitle", RDL.UI.UpdateTitle, RDL.UI) end

  -- Reclaim handler if another grabber stole it during loading
  if RDL.Capture and RDL.Capture.TryReclaimHandler and not (RDL.Capture.ownsHandler == true) then
    ICall("Capture:TryReclaimHandler", RDL.Capture.TryReclaimHandler, RDL.Capture, "login")
  end
  if RDL.UI and RDL.UI.UpdateTitle then ICall("UI:UpdateTitle", RDL.UI.UpdateTitle, RDL.UI) end

  -- Flush any pre-DB captured entries now that Init likely created DB.
  if RDL.Capture and RDL.Capture.FlushBootQueue then
    ICall("Capture:FlushBootQueue", RDL.Capture.FlushBootQueue, RDL.Capture)
  end

  -- Minimap launcher (ensure Minimap frame exists after login)
  if RDL.UI and RDL.UI.InitMinimapButton then
    if C_Timer then
      C_Timer.After(0.25, function()
        ICall("UI:InitMinimapButton", RDL.UI.InitMinimapButton, RDL.UI)
      end)
    else
      ICall("UI:InitMinimapButton", RDL.UI.InitMinimapButton, RDL.UI)
    end
  end

  RDL._initialized = true
  RDL:Log("INFO", "BOOT", "RothDevLib initialized", { version = RDL.version })
end

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...

    if name == RDL.addonName then
      -- Early init: DB + logger + attempt to own errorhandler before other addons.
      if RDL.DB and RDL.DB.EnsureReady then ICall("DB:EnsureReady", RDL.DB.EnsureReady, RDL.DB) end
      if RDL.Logger and RDL.Logger.Init then ICall("Logger:Init", RDL.Logger.Init, RDL.Logger) end
      if RDL.Validation and RDL.Validation.Init then ICall("Validation:Init", RDL.Validation.Init, RDL.Validation) end
      if RDL.Capture and RDL.Capture.EarlyInit then ICall("Capture:EarlyInit", RDL.Capture.EarlyInit, RDL.Capture) end

      -- Correctness self-checks (API overrides, invasive hooks) — capture as ALERT entries.
      if RDL.SelfCheckEarly then
        ICall("RDL:SelfCheckEarly", RDL.SelfCheckEarly, RDL, "ADDON_LOADED")
      end

      -- Flush early boot queue as soon as DB exists.
      if RDL.Capture and RDL.Capture.FlushBootQueue then
        ICall("Capture:FlushBootQueue", RDL.Capture.FlushBootQueue, RDL.Capture)
      end

    elseif name == "Blizzard_DebugTools" then
      -- ScriptErrorsFrame becomes available when DebugTools loads.
      if RDL.Suppress and RDL.Suppress.SuppressAll then
        ICall("Suppress:SuppressAll", RDL.Suppress.SuppressAll, RDL.Suppress)
      end
    end
    return
  end

  if event == "PLAYER_LOGIN" then
    InitAll()

    -- Re-check post-login (other addons may hook timers/handlers after we load).
    if RDL.SelfCheckEarly then
      ICall("RDL:SelfCheckEarly", RDL.SelfCheckEarly, RDL, "PLAYER_LOGIN")
    end

    -- Optional: continue persisted reload loop for QA.
    if RDL.Validation and RDL.Validation.MaybeContinueReloadLoop then
      ICall("Validation:MaybeContinueReloadLoop", RDL.Validation.MaybeContinueReloadLoop, RDL.Validation)
    end
    return
  end

  if event == "PLAYER_LOGOUT" then
    if RDL.DB and RDL.DB.OnShutdown then
      ICall("DB:OnShutdown", RDL.DB.OnShutdown, RDL.DB)
    end

    if RDL.Mem and RDL.Mem.StopWatcher then
      ICall("Mem:StopWatcher", RDL.Mem.StopWatcher, RDL.Mem)
    end
    return
  end

  if not RDL.Capture then return end

  if event == "LUA_WARNING" then
    -- IMPORTANT: do not wrap varargs inside an anonymous function.
    ICall("Capture:OnLuaWarning", RDL.Capture.OnLuaWarning, RDL.Capture, ...)
    return
  end
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN"
    or event == "MACRO_ACTION_BLOCKED" or event == "MACRO_ACTION_FORBIDDEN" then
    ICall("Capture:OnTaintEvent", RDL.Capture.OnTaintEvent, RDL.Capture, event, ...)
    return
  end
  if event == "ADDON_RESTRICTION_STATE_CHANGED" then
    if RDL.Capture.OnRestrictionStateChanged then
      ICall("Capture:OnRestrictionStateChanged", RDL.Capture.OnRestrictionStateChanged, RDL.Capture, event, ...)
    end
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    ICall("Capture:OnLeaveCombat", RDL.Capture.OnLeaveCombat, RDL.Capture)
    return
  end
end)
