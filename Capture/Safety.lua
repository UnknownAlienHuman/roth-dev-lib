-- !RothDevLib/Capture/Safety.lua
-- Central safety policy for capture paths retained from the legacy owner.
-- Loaded immediately after ErrorHandler.lua so its public methods replace the
-- unsafe intake edges without duplicating the ownership/fallback machinery.

local RDL = _G.RothDevLib
local Capture = RDL and RDL.Capture
if not Capture then return end

local function U()
  return RDL.Util
end

local function SafeText(value, fallback, maxBytes)
  local util = U()
  local ordinary = value
  if util and util.Scrub then
    local ok, scrubbed = pcall(util.Scrub, util, value)
    if ok then ordinary = scrubbed else ordinary = "<unavailable>" end
  end

  local text = fallback
  if text == nil then text = "" end
  if ordinary ~= nil and util and util.SafeToString then
    local ok, rendered = pcall(util.SafeToString, util, ordinary)
    if ok then text = rendered end
  elseif ordinary ~= nil and type(ordinary) == "string" then
    text = ordinary
  end

  if util and util.FilterSecretEscapes then
    local ok, filtered = pcall(util.FilterSecretEscapes, util, text)
    if ok then text = filtered end
  end
  if type(text) ~= "string" then
    text = fallback
    if type(text) ~= "string" then text = "" end
  end

  maxBytes = tonumber(maxBytes) or 8192
  if #text > maxBytes then text = text:sub(1, maxBytes) .. "<truncated>" end
  return text
end

local function SafeCopy(value, opts)
  local util = U()
  if util and util.CopyDiagnosticValue then
    local ok, copy = pcall(util.CopyDiagnosticValue, util, value, opts or {
      maxDepth = 4,
      maxEntries = 80,
      maxStringBytes = 4096,
    })
    if ok then return copy end
  end
  return SafeText(value, "<unavailable>", 4096)
end

local function OptionalText(value, maxBytes)
  local copy = SafeCopy(value, { maxDepth = 1, maxEntries = 1, maxStringBytes = maxBytes or 256 })
  if copy == nil then return nil end
  return SafeText(copy, "", maxBytes)
end

local function GetSettings()
  if RDL.DB and type(RDL.DB.GetSettings) == "function" then
    local ok, settings = pcall(RDL.DB.GetSettings, RDL.DB)
    if ok and type(settings) == "table" then return settings end
  end
  return {}
end

local function SafeLog(level, tag, message, data)
  if type(RDL.Log) ~= "function" then return end
  pcall(RDL.Log, RDL, level, tag, message, SafeCopy(data))
end

local function BuildErrorKeys(message, stack)
  local msg = SafeText(message, "", 64 * 1024)
  local trace = SafeText(stack, "", 128 * 1024)

  msg = msg:gsub("\\", "/")
    :gsub("Interface/AddOns/", "")
    :gsub("table:%s*0x[%x]+", "table:<?>")
  trace = trace:gsub("\\", "/")
    :gsub("Interface/AddOns/", "")
    :gsub("table:%s*0x[%x]+", "table:<?>")

  return msg .. "\031" .. trace, msg
end

local function BuildAndStore(kind, message, stack, locals, addonName, funcName, extra)
  if type(Capture.BuildEntry) ~= "function" or type(Capture.StoreEntry) ~= "function" then
    return nil, "unavailable"
  end

  local okBuild, entry = pcall(
    Capture.BuildEntry,
    SafeText(kind, "INTEGRATION", 64),
    SafeText(message, "", 64 * 1024),
    SafeText(stack, "", 128 * 1024),
    SafeCopy(locals, { maxDepth = 4, maxEntries = 80, maxStringBytes = 8192 }),
    OptionalText(addonName, 128),
    OptionalText(funcName, 256),
    SafeCopy(extra)
  )
  if not okBuild or type(entry) ~= "table" then
    SafeLog("ERROR", "CAPTURE", "BuildEntry failed", {
      error = SafeText(entry, "<error>", 2048),
      kind = kind,
    })
    return nil, "build-failed"
  end

  local okStore, result = pcall(Capture.StoreEntry, entry)
  if not okStore then
    SafeLog("ERROR", "CAPTURE", "StoreEntry failed", {
      error = SafeText(result, "<error>", 2048),
      kind = kind,
    })
    return nil, "store-failed"
  end
  return entry, result
end

local function CaptureStack(level, fallback)
  local trace = SafeText(fallback, "", 128 * 1024)
  if trace ~= "" or type(_G.debugstack) ~= "function" then return trace end

  local ok, value = pcall(_G.debugstack, level or 3, 40, 40)
  if ok then return SafeText(value, "", 128 * 1024) end
  return ""
end

local function CaptureLocals()
  if type(Capture.CaptureLocals) ~= "function" then return nil end
  local ok, value = pcall(Capture.CaptureLocals, 3)
  if not ok then return nil end
  return SafeCopy(value, { maxDepth = 4, maxEntries = 80, maxStringBytes = 8192 })
end

local function NotifyCaptured()
  local settings = GetSettings()
  if settings.chatNotifyOnError ~= true then return end

  if type(_G.UnitAffectingCombat) == "function" then
    local ok, inCombat = pcall(_G.UnitAffectingCombat, "player")
    if ok and inCombat then
      Capture._pendingChatNotify = true
      return
    end
  end

  local now = type(_G.time) == "function" and _G.time() or 0
  local throttle = tonumber(settings.chatNotifyThrottleSec) or 3
  if now - (tonumber(Capture._lastChatNotify) or 0) < throttle then return end
  Capture._lastChatNotify = now

  local link = ""
  if RDL.UI and type(RDL.UI.MakeSigLink) == "function" and Capture._lastStoredSig then
    local ok, value = pcall(RDL.UI.MakeSigLink, RDL.UI, Capture._lastStoredSig, "open")
    if ok then link = " " .. SafeText(value, "", 2048) end
  end

  if type(_G.print) == "function" then
    pcall(_G.print, "|cffff3333RothDevLib|r captured Lua error." .. link .. " Use |cffffff00/rdev|r")
  end
end

local function IsAddonLoaded(name)
  local addons = _G.C_AddOns
  local checker = addons and addons.IsAddOnLoaded
  if type(checker) ~= "function" then return false end
  local ok, loaded = pcall(checker, name)
  return ok and loaded == true
end

-- Current Retail fallback: Blizzard_ScriptErrors fans hard errors out through
-- AddLuaErrorHandler. Keep exactly one callback and ignore it while our own
-- global handler is active, otherwise chain mode would store the same error
-- twice after forwarding to Blizzard.
function Capture:InstallFallbackHooks()
  self._fallback = self._fallback or {}
  local settings = GetSettings()

  if settings.fallbackHookScriptErrors ~= false
      and not self._fallback.blizzardLuaHandlerHooked
      and type(_G.AddLuaErrorHandler) == "function" then
    local ok = pcall(_G.AddLuaErrorHandler, function(message, stack, locals)
      if not Capture or Capture._disabled or Capture.ownsHandler then return end
      local entry = BuildAndStore("LUA_ERROR", message, stack, locals, nil, nil, {
        source = "AddLuaErrorHandler",
        fallback = true,
      })
      if entry then
        SafeLog("ERROR", "LUA", "Fallback Lua error captured", {
          addon = entry.addon,
          func = entry.func,
        })
      end
    end)
    self._fallback.blizzardLuaHandlerHooked = ok == true
  end

  if settings.fallbackHookScriptErrors ~= false
      and not self._fallback.blizzardLuaHandlerHooked
      and not self._fallback.waitingScriptErrors
      and type(_G.CreateFrame) == "function" then
    local okFrame, watcher = pcall(_G.CreateFrame, "Frame")
    if okFrame and watcher and type(watcher.RegisterEvent) == "function"
        and type(watcher.SetScript) == "function" then
      self._fallback.waitingScriptErrors = true
      pcall(watcher.RegisterEvent, watcher, "ADDON_LOADED")
      pcall(watcher.SetScript, watcher, "OnEvent", function(owner)
        if type(_G.AddLuaErrorHandler) ~= "function" then return end
        if type(owner.UnregisterEvent) == "function" then
          pcall(owner.UnregisterEvent, owner, "ADDON_LOADED")
        end
        if type(owner.SetScript) == "function" then
          pcall(owner.SetScript, owner, "OnEvent", nil)
        end
        Capture._fallback.waitingScriptErrors = false
        Capture:InstallFallbackHooks()
      end)
    end
  end

  if settings.importBugGrabber ~= false and not self.ownsHandler
      and self.BugGrabber and type(self.BugGrabber.Enable) == "function"
      and type(self.BugGrabber.IsPresent) == "function" then
    local okPresent, present = pcall(self.BugGrabber.IsPresent, self.BugGrabber)
    if okPresent and present then
      pcall(self.BugGrabber.Enable, self.BugGrabber)
      self._fallback.bugGrabberEnabled = true
    end
  end

  self.ownerInfo = self.ownerInfo or {}
  self.ownerInfo.addons = self.ownerInfo.addons or {}
  self.ownerInfo.addons.BugGrabber = IsAddonLoaded("!BugGrabber") or IsAddonLoaded("BugGrabber")
  self.ownerInfo.addons.BugSack = IsAddonLoaded("BugSack")
  self.ownerInfo.addons.DebugTools = IsAddonLoaded("Blizzard_DebugTools")
end

-- Replacing seterrorhandler() with a no-op is intentionally unsupported.
-- ErrorHandler.lua runs EarlyInit at file load, so restore the real setter when
-- an old persisted lock setting already installed the no-op before this file.
function Capture:ApplyHandlerLock()
  if self._locked and type(self._real_seterrorhandler) == "function" then
    _G.seterrorhandler = self._real_seterrorhandler
  end
  self._locked = false

  local settings = GetSettings()
  if settings.lockErrorHandler == true then
    settings.lockErrorHandler = false
    if not self._lockPolicyLogged then
      self._lockPolicyLogged = true
      SafeLog("WARN", "CAPTURE", "Disabled obsolete lockErrorHandler setting", {
        reason = "global seterrorhandler replacement is not allowed",
      })
    end
  end
end

-- Secret-safe hard-error intake. Handler closures created by ErrorHandler.lua
-- resolve this method dynamically, so replacing it here also fixes handlers
-- that were installed during EarlyInit before this module loaded.
function Capture:OnLuaError(err, stack, noForward)
  if self._disabled then return false end
  if self._inHandler then
    if type(self.prevErrorHandler) == "function" then
      pcall(self.prevErrorHandler, err)
    end
    return false
  end

  self._inHandler = true
  local captured = false
  local errorKey, errorMessageKey

  local okRun, runError = xpcall(function()
    local message = SafeText(err, "<unavailable>", 64 * 1024)
    local trace = CaptureStack(3, stack)
    local locals = CaptureLocals()
    errorKey, errorMessageKey = BuildErrorKeys(message, trace)

    local entry, status = BuildAndStore("LUA_ERROR", message, trace, locals, nil, nil, {
      source = "errorhandler",
    })
    if entry and status ~= "failed" then
      captured = true
      SafeLog("ERROR", "LUA", "Lua error captured", {
        addon = entry.addon,
        func = entry.func,
      })
    end

    if RDL.Doctor and type(RDL.Doctor.Reset) == "function" then
      pcall(RDL.Doctor.Reset, RDL.Doctor)
    end

    if captured then NotifyCaptured() end
  end, function(innerError)
    return SafeText(innerError, "<capture-error>", 2048)
  end)

  self._inHandler = false
  if not okRun then
    SafeLog("ERROR", "CAPTURE", "OnLuaError failed", { error = runError })
  end

  -- Exclusive mode may optionally forward. Chain mode passes noForward=true
  -- and forwards exactly once in its already-installed wrapper.
  local settings = GetSettings()
  if not noForward and settings.forwardToDefaultErrorHandler == true
      and type(self.prevErrorHandler) == "function" then
    pcall(self.prevErrorHandler, err)
  end

  return captured, errorKey, errorMessageKey
end

function Capture:OnSuppressedError(err, stack, locals, addonName, funcName, extra)
  if self._disabled then return nil end

  local safeExtra = SafeCopy(extra)
  if type(safeExtra) ~= "table" then safeExtra = {} end
  safeExtra.suppressed = true

  local entry = BuildAndStore(
    "SUPPRESSED",
    SafeText(err, "<unavailable>", 64 * 1024),
    CaptureStack(3, stack),
    locals,
    addonName,
    funcName,
    safeExtra
  )
  if entry then
    SafeLog("WARN", "SUPPRESSED", "Suppressed error captured", {
      addon = entry.addon,
      func = entry.func,
    })
  end
  return entry
end

-- Direct callers of the low-level integration method receive the same boundary
-- as the public API. This also protects internal alerts assembled from API data.
function Capture:OnIntegrationEvent(kind, addonName, code, message, data, level)
  if self._disabled then return nil end

  local safeKind = SafeText(kind, "INTEGRATION", 64)
  if safeKind == "" then safeKind = "INTEGRATION" end
  local safeAddon = SafeText(addonName, "<?>" , 128)
  if safeAddon == "" then safeAddon = "<?>" end
  local safeCode = OptionalText(code, 256)
  local safeLevel = OptionalText(level, 32)
  local safeData = SafeCopy(data)

  local msg = SafeText(message, "", 64 * 1024)
  if safeCode and safeCode ~= "" then msg = safeCode .. ": " .. msg end
  if safeLevel and safeLevel ~= "" then msg = "[" .. safeLevel .. "] " .. msg end

  local entry = BuildAndStore(safeKind, msg, CaptureStack(3), nil, safeAddon, nil, {
    code = safeCode,
    level = safeLevel,
    data = safeData,
    source = "integration",
  })
  if not entry then return nil end

  local logLevel = safeKind == "ALERT" and "WARN" or "ERROR"
  SafeLog(logLevel, safeKind, "Integration event captured", {
    addon = safeAddon,
    code = safeCode,
  })
  return entry
end
