-- !RothDevLib/Capture/Engine.lua
-- Compact capture owner: one handler installation, bounded storage routing,
-- ownership observation, and no automatic handler wars.

local RDL = _G.RothDevLib
if not RDL then return end

local Capture = {
  _lastChatNotify = 0,
  _pendingChatNotify = false,
  _inHandler = false,
  _disabled = false,
  _earlyInited = false,
  _bootQueue = {},
  _bootQueueMax = 50,
}
RDL.Capture = Capture

local function Now()
  return type(_G.time) == "function" and _G.time() or 0
end

local function Settings()
  if RDL.DB and type(RDL.DB.GetSettings) == "function" then
    local ok, settings = pcall(RDL.DB.GetSettings, RDL.DB)
    if ok and type(settings) == "table" then return settings end
  end
  return {}
end

local function SafeText(value, fallback, maxBytes)
  local util = RDL.Util
  local text = fallback or ""
  if util and type(util.SafeToString) == "function" then
    local ok, result = pcall(util.SafeToString, util, value)
    if ok and type(result) == "string" then text = result end
  elseif type(value) == "string" then
    text = value
  end
  if util and type(util.FilterSecretEscapes) == "function" then
    local ok, result = pcall(util.FilterSecretEscapes, util, text)
    if ok and type(result) == "string" then text = result end
  end
  maxBytes = tonumber(maxBytes) or 8192
  if #text > maxBytes then text = text:sub(1, maxBytes) .. "<truncated>" end
  return text
end

local function SafeCopy(value, opts)
  local util = RDL.Util
  if util and type(util.CopyDiagnosticValue) == "function" then
    local ok, copy = pcall(util.CopyDiagnosticValue, util, value, opts or {
      maxDepth = 4,
      maxEntries = 80,
      maxNodes = 500,
      maxStringBytes = 8192,
    })
    if ok then return copy end
  end
  if value == nil then return nil end
  return SafeText(value, "<unavailable>", 8192)
end

local function FunctionSource(fn)
  if type(fn) ~= "function" then return SafeText(fn, "<?>" , 256) end
  local debugTable = _G.debug
  local getInfo = type(debugTable) == "table" and debugTable.getinfo or nil
  if type(getInfo) ~= "function" then return "<?>" end
  local ok, info = pcall(getInfo, fn, "S")
  if not ok or type(info) ~= "table" then return "<?>" end
  return SafeText(info.short_src, "<?>" , 512)
end

local function AddonFromSource(source)
  source = SafeText(source, "", 1024):gsub("^@", "")
  return source:match("Interface[/\\]AddOns[/\\]([^/\\]+)[/\\]")
    or source:match("AddOns[/\\]([^/\\]+)[/\\]")
end

local function SafeStack(level, fallback)
  local trace = SafeText(fallback, "", 128 * 1024)
  if trace ~= "" or type(_G.debugstack) ~= "function" then return trace end
  local ok, value = pcall(_G.debugstack, level or 3, 40, 40)
  if ok then return SafeText(value, "", 128 * 1024) end
  return ""
end

local function IsInternalAddon(name)
  return name ~= nil and (name == RDL.addonName or name == RDL.name)
end

local function CaptureLocals(level)
  if RDL.Locals and type(RDL.Locals.CaptureAtLevel) == "function" then
    local ok, value = pcall(RDL.Locals.CaptureAtLevel, RDL.Locals, level)
    if ok then return SafeCopy(value, { maxDepth = 4, maxEntries = 80, maxNodes = 500, maxStringBytes = 8192 }) end
  end
  if type(_G.debuglocals) ~= "function" then return nil end
  local ok, value = pcall(_G.debuglocals, level or 3)
  if not ok then return nil end
  if RDL.Util and type(RDL.Util.FilterLocals) == "function" then
    local maxBytes = tonumber(Settings().maxLocalsSize) or 8192
    local okFilter, filtered = pcall(RDL.Util.FilterLocals, RDL.Util, value, maxBytes)
    if okFilter then return filtered end
  end
  return SafeCopy(value, { maxDepth = 3, maxEntries = 80, maxNodes = 500, maxStringBytes = 8192 })
end
Capture.CaptureLocals = CaptureLocals

local function BuildEntry(kind, message, stack, locals, addonName, funcName, extra)
  local util = RDL.Util
  local messageText = SafeText(message, "", 64 * 1024)
  local stackText = SafeText(stack, "", 128 * 1024)
  local kindText = SafeText(kind, "INTEGRATION", 64)
  if kindText == "" then kindText = "INTEGRATION" end

  local sys = { ts = Now() }
  if util and type(util.SnapshotSys) == "function" then
    local ok, snapshot = pcall(util.SnapshotSys, util)
    if ok and type(snapshot) == "table" then sys = SafeCopy(snapshot) end
  end

  local top, chain
  if RDL.Doctor and type(RDL.Doctor.GetTop) == "function" then
    local ok, value = pcall(RDL.Doctor.GetTop, RDL.Doctor)
    if ok then top = SafeCopy(value) end
  end
  if RDL.Doctor and type(RDL.Doctor.GetSnapshotChain) == "function" then
    local ok, value = pcall(RDL.Doctor.GetSnapshotChain, RDL.Doctor)
    if ok then chain = SafeCopy(value) end
  end

  local originFromMessage, originFromStack
  if util and type(util.ParseOrigin) == "function" then
    local okMessage, valueMessage = pcall(util.ParseOrigin, util, nil, messageText)
    if okMessage then originFromMessage = SafeCopy(valueMessage) end
    local okStack, valueStack = pcall(util.ParseOrigin, util, stackText, messageText)
    if okStack then originFromStack = SafeCopy(valueStack) end
  end
  local origin = originFromMessage or originFromStack

  local addonArgument = SafeText(addonName, "", 128)
  if addonArgument == "" or addonArgument == "nil" or addonArgument == "<?>" then addonArgument = nil end
  local addonFromMessage = type(originFromMessage) == "table" and originFromMessage.addon or nil
  local addonFromStack
  if util and type(util.GuessAddonFromStack) == "function" then
    local ok, value = pcall(util.GuessAddonFromStack, util, stackText)
    if ok then addonFromStack = SafeText(value, "", 128) end
    if addonFromStack == "" or addonFromStack == "nil" then addonFromStack = nil end
  end
  local addonFromTop = type(top) == "table" and top.addon or nil

  local addonGuess = addonFromMessage
    or (addonArgument and not IsInternalAddon(addonArgument) and addonArgument)
    or (addonFromStack and not IsInternalAddon(addonFromStack) and addonFromStack)
    or (addonFromTop and not IsInternalAddon(addonFromTop) and addonFromTop)
    or addonArgument or addonFromStack or addonFromTop or "<?>"

  local funcGuess = SafeText(funcName, "", 512)
  if funcGuess == "" or funcGuess == "nil" then
    if type(top) == "table" and top.addon == addonGuess and not IsInternalAddon(top.addon) then
      funcGuess = SafeText(top.func, "<?>" , 512)
    else
      funcGuess = "<?>"
    end
  end

  local extraContext = SafeCopy(extra)
  if type(extraContext) ~= "table" then extraContext = {} end
  if origin then
    extraContext.originAddon = origin.addon
    extraContext.originFile = origin.file
    extraContext.originLine = origin.line
  end
  extraContext.faultAddon = extraContext.faultAddon or addonFromMessage or addonArgument or addonGuess
  if addonFromStack and addonFromStack ~= extraContext.faultAddon then
    extraContext.wrapperAddon = addonFromStack
  end

  local busContext
  if RDL.Breadcrumbs and type(RDL.Breadcrumbs.GetForError) == "function" then
    local ok, value = pcall(RDL.Breadcrumbs.GetForError, RDL.Breadcrumbs, addonGuess)
    if ok then busContext = SafeCopy(value) end
  elseif RDL.Bus and type(RDL.Bus.GetErrorContext) == "function" then
    local ok, value = pcall(RDL.Bus.GetErrorContext, RDL.Bus, addonGuess)
    if ok then busContext = SafeCopy(value) end
  end
  if type(busContext) == "table" and busContext.breadcrumbs == nil
      and type(busContext[1]) == "table" then
    busContext = { breadcrumbs = busContext }
  end

  local signature = kindText .. "|" .. messageText
  if util and type(util.MakeSignature) == "function" then
    local ok, value = pcall(util.MakeSignature, util, kindText, messageText, stackText)
    if ok then signature = SafeText(value, signature, 4096) end
  end

  return {
    ts = Now(),
    sessionId = RDL.DB and RDL.DB.sessionId or nil,
    kind = kindText,
    message = messageText,
    stack = stackText,
    locals = SafeCopy(locals, { maxDepth = 4, maxEntries = 80, maxNodes = 500, maxStringBytes = 8192 }),
    addon = addonGuess,
    func = funcGuess,
    origin = origin,
    sys = sys,
    bus = busContext,
    ctx = {
      top = top,
      chain = chain,
      extra = extraContext,
    },
    sig = signature,
  }
end
Capture.BuildEntry = BuildEntry

local function StoreEntry(entry)
  if type(entry) ~= "table" then return "failed" end

  local ready = false
  if RDL.DB and type(RDL.DB.EnsureReady) == "function" then
    local ok, value = pcall(RDL.DB.EnsureReady, RDL.DB)
    ready = ok and value == true
  end
  if not ready then
    Capture._bootQueue = Capture._bootQueue or {}
    entry.sys = type(entry.sys) == "table" and entry.sys or { ts = Now() }
    entry.sys.bootQueued = true
    Capture._bootQueue[#Capture._bootQueue + 1] = entry
    local maximum = tonumber(Capture._bootQueueMax) or 50
    while #Capture._bootQueue > maximum do table.remove(Capture._bootQueue, 1) end
    return "queued"
  end

  if RDL.Storm and type(RDL.Storm.Allow) == "function" then
    local ok, allowed = pcall(RDL.Storm.Allow, RDL.Storm, entry.kind)
    if ok and allowed == false then
      if RDL.DB.session then
        RDL.DB.session.throttledCount = (tonumber(RDL.DB.session.throttledCount) or 0) + 1
      end
      return "throttled"
    end
  end

  if type(RDL.DB.IsIgnored) == "function" then
    local ok, ignored = pcall(RDL.DB.IsIgnored, RDL.DB, entry.sig, entry.addon, entry.message)
    if ok and ignored then return "ignored" end
  end

  if type(RDL.DB.UpsertGroup) ~= "function" then return "failed" end
  local ok, group = pcall(RDL.DB.UpsertGroup, RDL.DB, entry)
  if not ok or type(group) ~= "table" then return "failed" end

  Capture._lastStoredSig = entry.sig
  Capture._lastStoredKind = entry.kind
  Capture._lastStoredAddon = entry.addon

  local session = RDL.DB.session
  if type(session) == "table" then
    session.errors = (tonumber(session.errors) or 0) + (entry.kind == "LUA_ERROR" and 1 or 0)
    session.warnings = (tonumber(session.warnings) or 0) + (entry.kind == "LUA_WARNING" and 1 or 0)
    session.taints = (tonumber(session.taints) or 0)
      + ((entry.kind == "TAINT_BLOCKED" or entry.kind == "TAINT_FORBIDDEN" or entry.kind == "TAINT_STATE") and 1 or 0)
    session.suppressed = (tonumber(session.suppressed) or 0) + (entry.kind == "SUPPRESSED" and 1 or 0)
    session.alerts = (tonumber(session.alerts) or 0) + (entry.kind == "ALERT" and 1 or 0)
    session.asserts = (tonumber(session.asserts) or 0) + (entry.kind == "ASSERT" and 1 or 0)
  end

  if RDL.Validation and type(RDL.Validation.OnEntryStored) == "function" then
    pcall(RDL.Validation.OnEntryStored, RDL.Validation, entry, "stored")
  end
  return "stored"
end
Capture.StoreEntry = StoreEntry

function Capture:FlushBootQueue()
  if type(self._bootQueue) ~= "table" or #self._bootQueue == 0 then return 0 end

  local ready = false
  if RDL.DB and type(RDL.DB.IsReady) == "function" then
    local ok, value = pcall(RDL.DB.IsReady, RDL.DB)
    ready = ok and value == true
  end
  if not ready then return 0 end

  local queue = self._bootQueue
  self._bootQueue = {}
  local stored = 0
  for index = 1, #queue do
    local status = StoreEntry(queue[index])
    if status == "stored" or status == "ignored" then stored = stored + 1 end
  end
  return stored
end

local function Mode()
  local settings = Settings()
  local mode = SafeText(settings.errorHandlerMode, "chain", 32):lower()
  if mode ~= "chain" and mode ~= "exclusive" then mode = "chain" end
  return mode, settings
end

function Capture:_SetOwnershipState(state, reason, extra)
  self.ownerInfo = self.ownerInfo or {}
  self.ownerInfo.state = SafeText(state, "not-owned", 64)
  self.ownerInfo.reason = SafeText(reason, self.ownerInfo.reason or "unknown", 128)
  self.ownerInfo.mode = self._handlerMode or self.ownerInfo.mode
  local copied = SafeCopy(extra)
  if type(copied) == "table" then
    for key, value in next, copied do self.ownerInfo[key] = value end
  end
end

function Capture:GetOwnershipState()
  local current = type(_G.geterrorhandler) == "function" and _G.geterrorhandler() or nil
  return {
    owns = self.ownsHandler == true,
    state = self.ownerInfo and self.ownerInfo.state or "not-owned",
    mode = self._handlerMode or "?",
    nowHandlerSrc = FunctionSource(current),
    nowHandlerAddon = AddonFromSource(FunctionSource(current)),
    prevHandlerSrc = FunctionSource(self.prevErrorHandler),
    prevHandlerAddon = AddonFromSource(FunctionSource(self.prevErrorHandler)),
  }
end

function Capture:EnsureHandler(previous)
  local mode = Mode()
  if mode == "chain" then
    if type(previous) ~= "function" and type(_G.geterrorhandler) == "function" then
      previous = _G.geterrorhandler()
    end
    if previous == self._handler then previous = self._handlerPrev end
    if self._handler and self._handlerMode == "chain" and self._handlerPrev == previous then return self._handler end

    self._handlerMode = "chain"
    self._handlerPrev = previous
    self._handler = function(errorValue)
      if Capture._disabled then
        if type(previous) == "function" then pcall(previous, errorValue) end
        return
      end

      local stack = SafeStack(2)
      Capture._inChainWrapper = true
      local ok = pcall(Capture.OnLuaError, Capture, errorValue, stack, true)
      Capture._inChainWrapper = false
      if not ok then
        -- The base handler is installed before Safety.lua replaces it. Keep the
        -- process handler recoverable even if intake fails in that short window.
        Capture._inHandler = false
        if RDL.Doctor and type(RDL.Doctor.Reset) == "function" then
          pcall(RDL.Doctor.Reset, RDL.Doctor)
        end
      end

      local settings = Settings()
      if settings.chainCallPrevHandler ~= false and type(previous) == "function"
          and previous ~= Capture._handler and not Capture._callingPrevHandler then
        Capture._callingPrevHandler = true
        pcall(previous, errorValue)
        Capture._callingPrevHandler = false
      end
    end
  else
    if self._handler and self._handlerMode == "exclusive" then return self._handler end
    self._handlerMode = "exclusive"
    self._handlerPrev = nil
    self._handler = function(errorValue)
      local ok = pcall(Capture.OnLuaError, Capture, errorValue, SafeStack(2), false)
      if not ok then
        Capture._inHandler = false
        Capture._inChainWrapper = false
        if RDL.Doctor and type(RDL.Doctor.Reset) == "function" then
          pcall(RDL.Doctor.Reset, RDL.Doctor)
        end
      end
    end
  end

  RDL.ErrorHandler = self._handler
  return self._handler
end

function Capture:SyncOwnership(reason)
  local current = type(_G.geterrorhandler) == "function" and _G.geterrorhandler() or nil
  local owned = self._handler ~= nil and current == self._handler
  local prior = self.ownerInfo and self.ownerInfo.state
  self.ownsHandler = owned
  self.ownerInfo = self.ownerInfo or {}
  self.ownerInfo.nowHandlerSrc = FunctionSource(current)
  self.ownerInfo.nowHandlerAddon = AddonFromSource(self.ownerInfo.nowHandlerSrc)

  if owned then
    self:_SetOwnershipState("owned", reason or "owned")
  elseif prior == "owned" then
    self:_SetOwnershipState("replaced", reason or "replaced", {
      replacedBy = self.ownerInfo.nowHandlerAddon,
    })
  else
    self:_SetOwnershipState("not-owned", reason or "not-owned")
  end
  return owned
end

function Capture:ProbeSetErrorHandler()
  local current = type(_G.geterrorhandler) == "function" and _G.geterrorhandler() or nil
  local result = {
    ts = Now(),
    skipped = true,
    reason = "non-mutating-policy",
    global_src = FunctionSource(_G.seterrorhandler),
    real_src = FunctionSource(self._real_seterrorhandler),
    before_src = FunctionSource(current),
    before_addon = AddonFromSource(FunctionSource(current)),
  }
  self.ownerInfo = self.ownerInfo or {}
  self.ownerInfo.setEHProbe = result
  self._setEHProbe = result
  return result
end

function Capture:ApplyHandlerLock()
  self._locked = false
  local settings = Settings()
  if settings.lockErrorHandler == true then settings.lockErrorHandler = false end
end

function Capture:InstallFallbackHooks()
  self._fallback = self._fallback or { kind = "unavailable" }
end

local function ManualReason(reason)
  return reason == "slash" or reason == "manual" or reason == "user"
end

function Capture:TryReclaimHandler(reason)
  reason = SafeText(reason, "automatic", 64)
  if not ManualReason(reason) then
    self:SyncOwnership(reason)
    if not self.ownsHandler then self:InstallFallbackHooks() end
    self.ownerInfo = self.ownerInfo or {}
    self.ownerInfo.autoReclaimSuppressed = true
    self.ownerInfo.autoReclaimReason = reason
    return self.ownsHandler == true
  end

  local current = type(_G.geterrorhandler) == "function" and _G.geterrorhandler() or nil
  if self.ownsHandler and current == self._handler then return true end
  self:EnsureHandler(current)
  local setter = self._real_seterrorhandler or _G.seterrorhandler
  if type(setter) ~= "function" then return false end
  local ok = pcall(setter, self._handler)
  self:SyncOwnership(reason)
  if not (ok and self.ownsHandler) then self:InstallFallbackHooks() end
  return ok and self.ownsHandler == true
end

function Capture:EarlyInit()
  if self._earlyInited then return self.ownsHandler == true end
  self._earlyInited = true

  if RDL.DB and type(RDL.DB.EnsureReady) == "function" then
    pcall(RDL.DB.EnsureReady, RDL.DB)
  end

  local current = type(_G.geterrorhandler) == "function" and _G.geterrorhandler() or nil
  self.prevErrorHandler = current
  self.ownerInfo = {
    seterrorhandlerSrc = FunctionSource(_G.seterrorhandler),
    oldHandlerSrc = FunctionSource(current),
    oldHandlerAddon = AddonFromSource(FunctionSource(current)),
  }
  self:EnsureHandler(current)

  self._real_seterrorhandler = type(_G.seterrorhandler) == "function" and _G.seterrorhandler or nil
  local installed = false
  if self._real_seterrorhandler and type(self._handler) == "function" then
    installed = pcall(self._real_seterrorhandler, self._handler)
  end
  self.ownerInfo.setAttemptOk = installed == true
  self:SyncOwnership("early")

  -- Observe ownership changes, but never reclaim automatically.
  if type(_G.hooksecurefunc) == "function" and not self._setEHHooked then
    local okHook = pcall(_G.hooksecurefunc, "seterrorhandler", function(newHandler)
      if not Capture or Capture._disabled or newHandler == Capture._handler then return end
      Capture.ownerInfo = Capture.ownerInfo or {}
      Capture.ownerInfo.lastSetEHNewSrc = FunctionSource(newHandler)
      Capture.ownerInfo.lastSetEHNewAddon = AddonFromSource(Capture.ownerInfo.lastSetEHNewSrc)
      Capture:SyncOwnership("seterrorhandler")
      if not Capture.ownsHandler then Capture:InstallFallbackHooks() end
    end)
    self._setEHHooked = okHook == true
  end

  self:ApplyHandlerLock()
  return self.ownsHandler == true
end

function Capture:Init()
  self:EarlyInit()

  if self.ChatTap and type(self.ChatTap.Init) == "function" then
    local ok, hooked = pcall(self.ChatTap.Init, self.ChatTap)
    self._fallback = self._fallback or {}
    self._fallback.chatTapHooked = ok and (hooked == true or self.ChatTap._hooked == true)
  end

  self:SyncOwnership("init")
  self:InstallFallbackHooks()
  return self.ownsHandler == true
end

-- Safe base implementation for errors that occur while later capture modules
-- are still loading. Safety.lua replaces this with the richer bounded path.
function Capture:OnLuaError(errorValue, stack, noForward)
  if self._disabled or self._inHandler then return false end
  self._inHandler = true

  local message = SafeText(errorValue, "<unavailable>", 64 * 1024)
  local trace = SafeStack(3, stack)
  local entry = BuildEntry("LUA_ERROR", message, trace, CaptureLocals(3), nil, nil, {
    source = "errorhandler-early",
  })
  local status = StoreEntry(entry)
  local captured = status ~= "failed" and status ~= "throttled"

  if RDL.Doctor and type(RDL.Doctor.Reset) == "function" then
    pcall(RDL.Doctor.Reset, RDL.Doctor)
  end
  self._inHandler = false

  if not noForward and Settings().forwardToDefaultErrorHandler == true
      and type(self.prevErrorHandler) == "function" then
    pcall(self.prevErrorHandler, errorValue)
  end
  return captured, entry.sig, message
end

function Capture:OnSuppressedError(errorValue, stack, locals, addonName, funcName, extra)
  local copied = SafeCopy(extra)
  if type(copied) ~= "table" then copied = {} end
  copied.suppressed = true
  local entry = BuildEntry("SUPPRESSED", errorValue, stack, locals, addonName, funcName, copied)
  StoreEntry(entry)
  return entry
end

function Capture:OnIntegrationEvent(kind, addonName, code, message, data, level)
  local messageText = SafeText(message, "", 64 * 1024)
  local codeText = SafeText(code, "", 256)
  local levelText = SafeText(level, "", 32)
  if codeText ~= "" and codeText ~= "nil" then messageText = codeText .. ": " .. messageText end
  if levelText ~= "" and levelText ~= "nil" then messageText = "[" .. levelText .. "] " .. messageText end
  local entry = BuildEntry(kind, messageText, SafeStack(3), nil, addonName, nil, {
    code = codeText,
    level = levelText,
    data = SafeCopy(data),
    source = "integration",
  })
  StoreEntry(entry)
  return entry
end

function Capture:OnLeaveCombat()
  if not self._pendingChatNotify then return end
  self._pendingChatNotify = false
  if type(_G.print) == "function" then
    pcall(_G.print, "|cffff3333RothDevLib|r captured errors while in combat. Use |cffffff00/rdev|r")
  end
end

function Capture:RunTest(kind)
  kind = SafeText(kind, "hard", 64):lower()
  if kind == "suppressed" and type(RDL.SafeCall) == "function" then
    RDL:SafeCall("RothDevLib", "Test:Suppressed", function() error("TEST_SUPPRESSED") end)
  elseif kind == "hard" and _G.C_Timer and type(_G.C_Timer.After) == "function" then
    _G.C_Timer.After(0.05, function() error("TEST_HARD_ERROR") end)
  elseif kind == "warning" and type(self.OnLuaWarning) == "function" then
    self:OnLuaWarning("TEST_WARNING", "manual")
  elseif kind == "taint" and type(self.OnTaintEvent) == "function" then
    self:OnTaintEvent("ADDON_ACTION_BLOCKED", RDL.addonName or "RothDevLib", "TEST_PROTECTED_CALL")
  elseif kind == "taintmacro" and type(self.OnTaintEvent) == "function" then
    self:OnTaintEvent("MACRO_ACTION_BLOCKED", "TEST_MACRO_CALL")
  elseif kind == "taintstate" and type(self.OnRestrictionStateChanged) == "function" then
    local restrictionType = _G.Enum and _G.Enum.AddOnRestrictionType and _G.Enum.AddOnRestrictionType.Combat or 0
    local state = _G.Enum and _G.Enum.AddOnRestrictionState and _G.Enum.AddOnRestrictionState.Active or 2
    self:OnRestrictionStateChanged("ADDON_RESTRICTION_STATE_CHANGED", restrictionType, state)
  elseif kind == "breadcrumb" and type(RDL.Breadcrumb) == "function" then
    RDL:Breadcrumb("RothDevLib", "test", "breadcrumb", { n = 1 })
  elseif kind == "metric" and type(RDL.Metric) == "function" then
    RDL:Metric("RothDevLib", "test_metric", 123, "unit", { minInterval = 0 })
  elseif kind == "alert" and type(RDL.Alert) == "function" then
    RDL:Alert("RothDevLib", "TEST_ALERT", "test alert", { a = 1 }, "WARN")
  elseif kind == "assert" and type(RDL.Assert) == "function" then
    RDL:Assert("RothDevLib", false, "TEST_ASSERT", "test assert", { b = 2 })
  elseif kind == "report" and type(RDL.ReportError) == "function" then
    RDL:ReportError("RothDevLib", "TEST_REPORTED_ERROR", { func = "Test:Report", tag = "manual" })
  elseif kind == "cpu" and type(RDL.Profile) == "function" then
    RDL:Profile("RothDevLib", "Test:CPU", function()
      local result = 0
      for index = 1, 300000 do result = result + index end
      return result
    end, { spikeMs = 1, metricMinInterval = 0 })
  elseif kind == "mem" and type(RDL.MemDelta) == "function" then
    RDL:MemDelta("RothDevLib", "Test:Mem", function()
      local values = {}
      for index = 1, 8000 do values[index] = tostring(index) end
      return #values
    end, { spikeKB = 1, metricMinInterval = 0 })
  end
end

pcall(Capture.EarlyInit, Capture)
