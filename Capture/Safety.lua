-- !RothDevLib/Capture/Safety.lua
-- Bounded hard/suppressed/integration intake and fallback policy.

local RDL = _G.RothDevLib
local Capture = RDL and RDL.Capture
if not Capture then return end

-- Engine installs the handler before this file loads. Guard its small bootstrap
-- implementation immediately so any load-time intake fault still clears the
-- recursion flags and preserves prior-handler delivery.
do
  local bootstrapOnLuaError = Capture.OnLuaError
  if type(bootstrapOnLuaError) == "function" then
    Capture.OnLuaError = function(self, errorValue, stack, noForward)
      local ok, captured, key, messageKey = xpcall(function()
        return bootstrapOnLuaError(self, errorValue, stack, noForward)
      end, function() return false end)

      self._inHandler = false
      self._inChainWrapper = false
      if ok then return captured, key, messageKey end

      if not noForward and type(self.prevErrorHandler) == "function" then
        pcall(self.prevErrorHandler, errorValue)
      end
      return false
    end
  end
end

local function Util()
  return RDL.Util
end

local function SafeText(value, fallback, maxBytes)
  local util = Util()
  local ordinary = value
  if util and type(util.Scrub) == "function" then
    local ok, scrubbed = pcall(util.Scrub, util, value)
    ordinary = ok and scrubbed or "<unavailable>"
  end

  local text = type(fallback) == "string" and fallback or ""
  if ordinary ~= nil and util and type(util.SafeToString) == "function" then
    local ok, rendered = pcall(util.SafeToString, util, ordinary)
    if ok and type(rendered) == "string" then text = rendered end
  elseif type(ordinary) == "string" then
    text = ordinary
  end

  if util and type(util.FilterSecretEscapes) == "function" then
    local ok, filtered = pcall(util.FilterSecretEscapes, util, text)
    if ok and type(filtered) == "string" then text = filtered end
  end

  maxBytes = tonumber(maxBytes) or 8192
  if maxBytes < 1 then maxBytes = 1 end
  if #text > maxBytes then text = text:sub(1, maxBytes) .. "<truncated>" end
  return text
end

local function SafeCopy(value, options)
  local util = Util()
  if util and type(util.CopyDiagnosticValue) == "function" then
    local ok, copy = pcall(util.CopyDiagnosticValue, util, value, options or {
      maxDepth = 4,
      maxEntries = 80,
      maxNodes = 500,
      maxStringBytes = 4096,
    })
    if ok then return copy end
  end
  if value == nil then return nil end
  return SafeText(value, "<unavailable>", 4096)
end

local function OptionalText(value, maxBytes)
  if value == nil then return nil end
  local copy = SafeCopy(value, {
    maxDepth = 1,
    maxEntries = 1,
    maxNodes = 4,
    maxStringBytes = maxBytes or 256,
  })
  if copy == nil then return nil end
  return SafeText(copy, "", maxBytes)
end

local function Settings()
  if RDL.DB and type(RDL.DB.GetSettings) == "function" then
    local ok, value = pcall(RDL.DB.GetSettings, RDL.DB)
    if ok and type(value) == "table" then return value end
  end
  return {}
end

local function SafeLog(level, tag, message, data)
  if type(RDL.Log) == "function" then
    pcall(RDL.Log, RDL, level, tag, message, SafeCopy(data))
  end
end

local function FunctionSource(fn)
  if type(fn) ~= "function" then return "<?>" end
  local debugTable = _G.debug
  local getInfo = type(debugTable) == "table" and debugTable.getinfo or nil
  if type(getInfo) ~= "function" then return "<?>" end
  local ok, info = pcall(getInfo, fn, "S")
  if not ok or type(info) ~= "table" then return "<?>" end
  return SafeText(info.short_src, "<?>" , 512)
end

local function AddonFromSource(source)
  if type(source) ~= "string" then return nil end
  source = source:gsub("^@", "")
  return source:match("Interface[/\\]AddOns[/\\]([^/\\]+)[/\\]")
    or source:match("AddOns[/\\]([^/\\]+)[/\\]")
end

local function BuildErrorKeys(message, stack)
  local msg = SafeText(message, "", 64 * 1024)
    :gsub("\\", "/")
    :gsub("Interface/AddOns/", "")
    :gsub("table:%s*0x[%x]+", "table:<?>")
  local trace = SafeText(stack, "", 128 * 1024)
    :gsub("\\", "/")
    :gsub("Interface/AddOns/", "")
    :gsub("table:%s*0x[%x]+", "table:<?>")
  return msg .. "\031" .. trace, msg
end

local ACCEPTED_STATUS = {
  stored = true,
  queued = true,
  ignored = true,
}

local function BuildAndStore(kind, message, stack, locals, addonName, funcName, extra)
  if type(Capture.BuildEntry) ~= "function" or type(Capture.StoreEntry) ~= "function" then
    return nil, "unavailable"
  end

  local okBuild, entry = pcall(
    Capture.BuildEntry,
    SafeText(kind, "INTEGRATION", 64),
    SafeText(message, "", 64 * 1024),
    SafeText(stack, "", 128 * 1024),
    SafeCopy(locals, { maxDepth = 4, maxEntries = 80, maxNodes = 500, maxStringBytes = 8192 }),
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

  local okStore, status = pcall(Capture.StoreEntry, entry)
  if not okStore then
    SafeLog("ERROR", "CAPTURE", "StoreEntry failed", {
      error = SafeText(status, "<error>", 2048),
      kind = kind,
    })
    return nil, "store-failed"
  end
  if not ACCEPTED_STATUS[status] then return nil, status or "store-failed" end
  return entry, status
end

local function CaptureStack(level, fallback)
  local trace = SafeText(fallback, "", 128 * 1024)
  if trace ~= "" or type(_G.debugstack) ~= "function" then return trace end
  local ok, value = pcall(_G.debugstack, level or 3, 40, 40)
  return ok and SafeText(value, "", 128 * 1024) or ""
end

local function CaptureLocals()
  if type(Capture.CaptureLocals) ~= "function" then return nil end
  local ok, value = pcall(Capture.CaptureLocals, 3)
  if not ok then return nil end
  return SafeCopy(value, { maxDepth = 4, maxEntries = 80, maxNodes = 500, maxStringBytes = 8192 })
end

local function ResetDoctor()
  if RDL.Doctor and type(RDL.Doctor.Reset) == "function" then
    pcall(RDL.Doctor.Reset, RDL.Doctor)
  end
end

local function NotifyCaptured()
  local settings = Settings()
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
    pcall(_G.print, "|cffff3333RothDevLib|r captured Lua error." .. link
      .. " Use |cffffff00/rdev|r")
  end
end

local function IsAddonLoaded(name)
  local addons = _G.C_AddOns
  local checker = addons and addons.IsAddOnLoaded
  if type(checker) ~= "function" then return false end
  local ok, _, loaded = pcall(checker, name)
  return ok and loaded == true
end

function Capture:InstallFallbackHooks()
  self._fallback = self._fallback or {}
  self._fallback.blizzardLuaHandlerUnsupported = true
  self._fallback.blizzardLuaHandlerHooked = false
  self._fallback.scriptErrorsHooked = false
  self._fallback.scriptErrorsFrameSyncEnabled = false

  local settings = Settings()
  local bug = self.BugGrabber
  local shouldEnable = false

  if not self.ownsHandler and settings.importBugGrabber ~= false and bug
      and type(bug.Enable) == "function" and type(bug.IsPresent) == "function" then
    local okPresent, present = pcall(bug.IsPresent, bug)
    shouldEnable = okPresent and present == true
  end

  if shouldEnable then
    local okEnable, enabled = pcall(bug.Enable, bug)
    self._fallback.bugGrabberEnabled = okEnable and enabled == true
  else
    if bug and type(bug.Disable) == "function" then pcall(bug.Disable, bug) end
    self._fallback.bugGrabberEnabled = false
  end

  self._fallback.kind = self.ownsHandler and "owned"
    or (self._fallback.bugGrabberEnabled and "buggrabber" or "unavailable")

  self.ownerInfo = self.ownerInfo or {}
  self.ownerInfo.addons = self.ownerInfo.addons or {}
  self.ownerInfo.addons.BugGrabber = IsAddonLoaded("!BugGrabber") or IsAddonLoaded("BugGrabber")
  self.ownerInfo.addons.BugSack = IsAddonLoaded("BugSack")
  self.ownerInfo.addons.DebugTools = IsAddonLoaded("Blizzard_DebugTools")
  self.ownerInfo.fallback = self._fallback.kind
end

function Capture:ApplyHandlerLock()
  -- Cleanup only: undo a lock left by an older loaded revision. New code never
  -- installs the no-op setter.
  if self._locked and type(self._real_seterrorhandler) == "function" then
    _G.seterrorhandler = self._real_seterrorhandler
  end
  self._locked = false
  local settings = Settings()
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

function Capture:ProbeSetErrorHandler()
  local current = type(_G.geterrorhandler) == "function" and _G.geterrorhandler() or nil
  local source = FunctionSource(current)
  local result = {
    ts = type(_G.time) == "function" and _G.time() or 0,
    skipped = true,
    reason = "non-mutating-policy",
    global_src = FunctionSource(_G.seterrorhandler),
    real_src = FunctionSource(self._real_seterrorhandler),
    before_src = source,
    before_addon = AddonFromSource(source),
  }
  self.ownerInfo = self.ownerInfo or {}
  self.ownerInfo.setEHProbe = result
  self._setEHProbe = result
  return result
end

local function IsManualReclaim(reason)
  return reason == "slash" or reason == "manual" or reason == "user"
end

function Capture:TryReclaimHandler(reason)
  reason = SafeText(reason, "automatic", 64)
  if not IsManualReclaim(reason) then
    if type(self.SyncOwnership) == "function" then pcall(self.SyncOwnership, self, reason) end
    if not self.ownsHandler then self:InstallFallbackHooks() end
    self.ownerInfo = self.ownerInfo or {}
    self.ownerInfo.autoReclaimSuppressed = true
    self.ownerInfo.autoReclaimReason = reason
    return self.ownsHandler == true
  end

  local current = type(_G.geterrorhandler) == "function" and _G.geterrorhandler() or nil
  if self.ownsHandler and current == self._handler then return true end
  if type(self.EnsureHandler) == "function" then pcall(self.EnsureHandler, self, current, reason) end

  local setter = self._real_seterrorhandler
  if type(setter) ~= "function" then setter = _G.seterrorhandler end
  if type(setter) ~= "function" or type(self._handler) ~= "function" then
    self:InstallFallbackHooks()
    return false
  end

  local okSet = pcall(setter, self._handler)
  local nowHandler = type(_G.geterrorhandler) == "function" and _G.geterrorhandler() or nil
  local owned = okSet and nowHandler == self._handler
  self.ownsHandler = owned == true

  self.ownerInfo = self.ownerInfo or {}
  self.ownerInfo.reclaim = self.ownerInfo.reclaim or {}
  self.ownerInfo.reclaim[#self.ownerInfo.reclaim + 1] = {
    ts = type(_G.time) == "function" and _G.time() or 0,
    reason = reason,
    ok = owned,
    nowHandlerSrc = FunctionSource(nowHandler),
  }
  self.ownerInfo.nowHandlerSrc = FunctionSource(nowHandler)
  self.ownerInfo.nowHandlerAddon = AddonFromSource(self.ownerInfo.nowHandlerSrc)
  if type(self._SetOwnershipState) == "function" then
    pcall(self._SetOwnershipState, self, owned and "owned" or "not-owned", reason)
  end

  if owned then
    if self.BugGrabber and type(self.BugGrabber.Disable) == "function" then
      pcall(self.BugGrabber.Disable, self.BugGrabber)
    end
    SafeLog("INFO", "CAPTURE", "Reclaimed Lua errorhandler by user request", {
      mode = self._handlerMode,
    })
    return true
  end

  self:InstallFallbackHooks()
  SafeLog("WARN", "CAPTURE", "Failed to reclaim Lua errorhandler", {
    reason = reason,
    now = self.ownerInfo.nowHandlerSrc,
  })
  return false
end

function Capture:OnLuaError(errorValue, stack, noForward)
  if self._disabled then return false end
  if self._inHandler then
    if type(self.prevErrorHandler) == "function" then pcall(self.prevErrorHandler, errorValue) end
    return false
  end

  self._inHandler = true
  local captured = false
  local errorKey, errorMessageKey
  local okRun, runError = xpcall(function()
    local message = SafeText(errorValue, "<unavailable>", 64 * 1024)
    local trace = CaptureStack(3, stack)
    errorKey, errorMessageKey = BuildErrorKeys(message, trace)

    local entry, status = BuildAndStore("LUA_ERROR", message, trace, CaptureLocals(), nil, nil, {
      source = "errorhandler",
    })
    captured = entry ~= nil and (status == "stored" or status == "queued")
    if captured then
      SafeLog("ERROR", "LUA", "Lua error captured", {
        addon = entry.addon,
        func = entry.func,
      })
    end
    ResetDoctor()
    if captured then NotifyCaptured() end
  end, function(innerError)
    return SafeText(innerError, "<capture-error>", 2048)
  end)

  self._inHandler = false
  self._inChainWrapper = false
  if not okRun then
    ResetDoctor()
    SafeLog("ERROR", "CAPTURE", "OnLuaError failed", { error = runError })
  end

  if not noForward and Settings().forwardToDefaultErrorHandler == true
      and type(self.prevErrorHandler) == "function" then
    pcall(self.prevErrorHandler, errorValue)
  end
  return captured, errorKey, errorMessageKey
end

function Capture:OnSuppressedError(errorValue, stack, locals, addonName, funcName, extra)
  if self._disabled then return nil end
  local safeExtra = SafeCopy(extra)
  if type(safeExtra) ~= "table" then safeExtra = {} end
  safeExtra.suppressed = true

  local entry, status = BuildAndStore(
    "SUPPRESSED",
    SafeText(errorValue, "<unavailable>", 64 * 1024),
    CaptureStack(3, stack),
    locals,
    addonName,
    funcName,
    safeExtra
  )
  if entry and (status == "stored" or status == "queued") then
    SafeLog("WARN", "SUPPRESSED", "Suppressed error captured", {
      addon = entry.addon,
      func = entry.func,
    })
  end
  return entry
end

function Capture:OnIntegrationEvent(kind, addonName, code, message, data, level)
  if self._disabled then return nil end

  local safeKind = SafeText(kind, "INTEGRATION", 64)
  if safeKind == "" then safeKind = "INTEGRATION" end
  local safeAddon = SafeText(addonName, "<?>" , 128)
  if safeAddon == "" then safeAddon = "<?>" end
  local safeCode = OptionalText(code, 256)
  local safeLevel = OptionalText(level, 32)

  local msg = SafeText(message, "", 64 * 1024)
  if safeCode and safeCode ~= "" then msg = safeCode .. ": " .. msg end
  if safeLevel and safeLevel ~= "" then msg = "[" .. safeLevel .. "] " .. msg end

  local entry, status = BuildAndStore(safeKind, msg, CaptureStack(3), nil, safeAddon, nil, {
    code = safeCode,
    level = safeLevel,
    data = SafeCopy(data),
    source = "integration",
  })
  if entry and (status == "stored" or status == "queued") then
    SafeLog(safeKind == "ALERT" and "WARN" or "ERROR", safeKind,
      "Integration event captured", { addon = safeAddon, code = safeCode })
  end
  return entry
end
