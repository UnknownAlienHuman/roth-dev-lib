-- !RothDevLib/Capture/ErrorHandler.lua
-- Core error capture engine.
-- Ported and enhanced from !RothGrabber/Modules/Capture.lua (split into modules).
-- Owns the global Lua error handler, captures suppressed errors, integration events.

local RDL = _G.RothDevLib
local Capture = {}
RDL.Capture = Capture

Capture._lastChatNotify = 0
Capture._pendingChatNotify = false
Capture._inHandler = false
Capture._disabled = false
-- Pre-DB boot queue: if capture happens before SavedVariables/DB init, keep entries in memory and flush later.
Capture._bootQueue = Capture._bootQueue or {}
Capture._bootQueueMax = 50


Capture._earlyInited = false
Capture._locked = false
Capture._real_seterrorhandler = nil

-- Helpers ---------------------------------------------------------------

local function GetDebugGetInfo()
  local dbg = _G and _G.debug
  if type(dbg) == "table" and type(dbg.getinfo) == "function" then
    return dbg.getinfo
  end
  return nil
end

local function NowPrecise()
  if type(_G.GetTimePreciseSec) == "function" then
    local ok, v = pcall(_G.GetTimePreciseSec)
    if ok and type(v) == "number" then return v end
  end
  if type(_G.GetTime) == "function" then
    local ok, v = pcall(_G.GetTime)
    if ok and type(v) == "number" then return v end
  end
  return time()
end

local function BuildLuaErrorMessageKey(message)
  local msg = tostring(message or "")
  -- For sync/dedup keys keep line numbers (do not collapse to #).
  msg = msg:gsub("\\", "/")
  msg = msg:gsub("Interface/AddOns/", "")
  msg = msg:gsub("table:%s*0x[%x]+", "table:<?>")
  return msg
end

local function BuildLuaErrorKey(message, stack)
  local msg = BuildLuaErrorMessageKey(message)
  local st = tostring(stack or "")
  st = st:gsub("\\", "/")
  st = st:gsub("Interface/AddOns/", "")
  st = st:gsub("table:%s*0x[%x]+", "table:<?>")
  return msg .. "\031" .. st
end

local function BumpScriptErrorsSyncKey(key, n)
  if not key or key == "" then return end
  Capture._scriptErrorsSyncCountByKey = Capture._scriptErrorsSyncCountByKey or {}
  local byKey = Capture._scriptErrorsSyncCountByKey
  byKey[key] = (tonumber(byKey[key]) or 0) + (tonumber(n) or 1)
  if byKey[key] < 0 then byKey[key] = 0 end
end

local function FuncSrc(fn)
  if type(fn) ~= "function" then return tostring(fn) end
  local getinfo = GetDebugGetInfo()
  if type(getinfo) ~= "function" then return "<?>" end
  local ok, info = pcall(getinfo, fn, "S")
  if not ok or type(info) ~= "table" then return "<?>" end
  return (info and info.short_src) or "<?>"
end

local function AddonFromSrc(src)
  if not src then return nil end
  src = tostring(src):gsub("^@", "")
  -- Support both "/" and "\" separators (debug sources may use either).
  local name = src:match("Interface[/\\]AddOns[/\\]([^/\\]+)[/\\]")
  if not name then
    name = src:match("AddOns[/\\]([^/\\]+)[/\\]")
  end
  return name
end


local function ChatNotifyThrottled(msg)
  local settings = RDL.DB and RDL.DB:GetSettings()
  if not settings or not settings.chatNotifyOnError then return end

  if UnitAffectingCombat("player") then
    Capture._pendingChatNotify = true
    return
  end

  local now = time()
  local throttle = settings.chatNotifyThrottleSec or 3
  if now - (Capture._lastChatNotify or 0) < throttle then return end
  Capture._lastChatNotify = now
  print(msg)
end

-- Build structured error entry ------------------------------------------

local function CaptureLocals(level)
  -- Backward compatible helper (explicit level).
  if RDL.Locals and RDL.Locals.CaptureAtLevel then
    local ok, v = pcall(function() return RDL.Locals:CaptureAtLevel(level) end)
    if ok then return v end
  end
  if type(_G.debuglocals) ~= "function" then
    return nil
  end
  local lok, lval = pcall(_G.debuglocals, level)
  if lok and lval and RDL.Util and RDL.Util.FilterLocals then
    local settings = RDL.DB and RDL.DB:GetSettings()
    local maxSize = (settings and settings.maxLocalsSize) or 8192
    return RDL.Util:FilterLocals(lval, maxSize)
  end
  return (lok and lval) or nil
end

-- Derive stack/locals from Blizzard error-callstack helpers when possible.
-- Mirrors BugGrabber behavior: keep debuglocals level conservative (<= 3).
local function CaptureHardErrorData(fallbackStack)
  local stack = (type(fallbackStack) == "string" and fallbackStack) or ""
  local locals = nil
  local meta = {}

  local level = 3
  if type(_G.GetCallstackHeight) == "function" and type(_G.GetErrorCallstackHeight) == "function" then
    local okCur, cur = pcall(_G.GetCallstackHeight)
    local okErr, errH = pcall(_G.GetErrorCallstackHeight)
    if okCur and okErr and type(cur) == "number" and type(errH) == "number" then
      local offset = errH - 1
      local probeLevel = cur - (offset or 0)
      if type(probeLevel) == "number" and probeLevel >= 1 then
        level = probeLevel
      end
      meta.callstackHeight = cur
      meta.errorCallstackHeight = errH
    end
  end
  meta.stackLevel = level

  if type(_G.debugstack) == "function" then
    local okS, s = pcall(_G.debugstack, level)
    if okS and type(s) == "string" and s ~= "" then
      stack = s
    end
  end

  local localsLevel = level
  if localsLevel > 3 then localsLevel = 3 end
  if localsLevel < 1 then localsLevel = 1 end
  meta.localsLevel = localsLevel

  if type(_G.debuglocals) == "function" then
    local okL, l = pcall(_G.debuglocals, localsLevel, true)
    if not okL then
      okL, l = pcall(_G.debuglocals, localsLevel)
    end
    if okL and type(l) == "string" and l ~= "" then
      locals = l
    end
  end

  if locals and RDL.Util and RDL.Util.FilterLocals then
    local settings = RDL.DB and RDL.DB:GetSettings()
    local maxSize = (settings and settings.maxLocalsSize) or 8192
    locals = RDL.Util:FilterLocals(locals, maxSize)
  end

  return stack, locals, meta
end

local function BuildEntry(kind, message, stack, locals, addonName, funcName, extra)
  local U = RDL.Util
  local sys = U and U:SnapshotSys() or { ts = time() }

  local top = (RDL.Doctor and RDL.Doctor:GetTop()) or nil
  local chain = (RDL.Doctor and RDL.Doctor:GetSnapshotChain()) or nil

  local msg = U and U:Scrub(message) or message
  local msgText = tostring(msg or "")
  local stackText = tostring(stack or "")

  local originFromMsg = (U and U.ParseOrigin) and U:ParseOrigin(nil, msgText) or nil
  local originFromStack = (U and U.ParseOrigin) and U:ParseOrigin(stackText, msgText) or nil
  local origin = originFromMsg or originFromStack

  local addonFromArgRaw = (type(addonName) == "string" and addonName ~= "" and addonName ~= "<?>") and addonName or nil
  local addonFromMsg = originFromMsg and originFromMsg.addon or nil
  local addonFromStack = (U and U.GuessAddonFromStack) and U:GuessAddonFromStack(stackText) or nil
  local addonFromTop = (top and top.addon) or nil

  local function IsInternalAddon(a)
    if not a or a == "" then return false end
    return a == RDL.addonName or a == RDL.name
  end

  local addonFromArg = (addonFromArgRaw and (not IsInternalAddon(addonFromArgRaw))) and addonFromArgRaw or nil

  local addonGuess = addonFromMsg
      or addonFromArg
      or (not IsInternalAddon(addonFromStack) and addonFromStack)
      or (not IsInternalAddon(addonFromTop) and addonFromTop)
      or addonFromArgRaw
      or addonFromStack
      or addonFromTop
      or "<?>"

  local funcGuess = funcName
  if not funcGuess or funcGuess == "" then
    if top and top.func and (top.addon == addonGuess) and (not IsInternalAddon(top.addon)) then
      funcGuess = top.func
    else
      funcGuess = "<?>"
    end
  end

  local extraCtx = nil
  if type(extra) == "table" then
    extraCtx = {}
    for k, v in pairs(extra) do extraCtx[k] = v end
  else
    extraCtx = {}
  end
  local faultAddon = addonFromMsg or addonFromArg or addonGuess
  if faultAddon and addonFromStack and addonFromStack ~= faultAddon then
    extraCtx.wrapperAddon = addonFromStack
  end
  if faultAddon and addonFromTop and addonFromTop ~= faultAddon and addonFromTop ~= addonFromStack then
    extraCtx.handlerAddon = addonFromTop
  end
  if faultAddon then
    extraCtx.faultAddon = faultAddon
  end
  if addonFromArgRaw and faultAddon and addonFromArgRaw ~= faultAddon then
    extraCtx.hintAddon = addonFromArgRaw
  end
  if origin then
    extraCtx.originAddon = origin.addon
    extraCtx.originFile = origin.file
    extraCtx.originLine = origin.line
  end

  -- Breadcrumbs for context
  local busCtx = nil
  if RDL.Breadcrumbs and RDL.Breadcrumbs.GetForError then
    busCtx = RDL.Breadcrumbs:GetForError(addonGuess)
  elseif RDL.Bus and RDL.Bus.GetErrorContext then
    busCtx = RDL.Bus:GetErrorContext(addonGuess)
  end

  -- Normalize to the structure expected by UI/Report: { breadcrumbs = { ... }, metrics = ... }
  -- Bus snapshot APIs return an array; wrap it for forward-compat.
  if busCtx and busCtx.breadcrumbs == nil and type(busCtx[1]) == "table" then
    busCtx = { breadcrumbs = busCtx }
  end

  local sig = U and U:MakeSignature(kind, msg, stack) or (kind .. "|" .. tostring(msg))

  local e = {
    ts = time(),
    sessionId = (RDL.DB and RDL.DB.sessionId) or nil,
    kind = kind,
    message = tostring(msg),
    stack = stack,
    locals = locals,
    addon = addonGuess,
    func = funcGuess,
    origin = origin,
    sys = sys,
    bus = busCtx,
    ctx = {
      top = top and { addon = top.addon, func = top.func, ctx = top.ctx } or nil,
      chain = chain,
      extra = extraCtx,
    },
  }
  e.sig = sig
  return e
end

local function StoreEntry(entry)
  if not RDL.DB or not RDL.DB:EnsureReady() then
    -- DB not ready yet (early boot). Queue entry in memory and flush later.
    Capture._bootQueue = Capture._bootQueue or {}
    if entry then
      entry.sys = entry.sys or { ts = time() }
      entry.sys.bootQueued = true
      table.insert(Capture._bootQueue, entry)
      local maxQ = Capture._bootQueueMax or 50
      while #Capture._bootQueue > maxQ do
        table.remove(Capture._bootQueue, 1)
      end
    end
    if RDL and RDL.Log then
      pcall(function() RDL:Log("ERROR", "DB", "StoreEntry: DB not ready (queued)", { kind = entry and entry.kind }) end)
    end
    return "queued"
  end

  -- Storm (flood protection)
  if RDL.Storm and RDL.Storm.Allow then
    if not RDL.Storm:Allow(entry.kind) then
      if RDL.DB.session then
        RDL.DB.session.throttledCount = (RDL.DB.session.throttledCount or 0) + 1
      end
      return "throttled"
    end
  end

  -- Ignore rules (signature/addon patterns)
  if RDL.DB.IsIgnored and RDL.DB:IsIgnored(entry.sig, entry.addon, entry.message) then
    return "ignored"
  end

  local g = RDL.DB:UpsertGroup(entry)
  if not g then return "failed" end

  -- Remember last stored signature for chat hyperlinks / quick-open.
  Capture._lastStoredSig = entry.sig
  Capture._lastStoredKind = entry.kind
  Capture._lastStoredAddon = entry.addon

  -- Update session counters
  if RDL.DB.session then
    local s      = RDL.DB.session
    s.errors     = (s.errors or 0) + (entry.kind == "LUA_ERROR" and 1 or 0)
    s.warnings   = (s.warnings or 0) + (entry.kind == "LUA_WARNING" and 1 or 0)
    s.taints     = (s.taints or 0) +
    ((entry.kind == "TAINT_BLOCKED" or entry.kind == "TAINT_FORBIDDEN" or entry.kind == "TAINT_STATE") and 1 or 0)
    s.suppressed = (s.suppressed or 0) + (entry.kind == "SUPPRESSED" and 1 or 0)
    s.alerts     = (s.alerts or 0) + (entry.kind == "ALERT" and 1 or 0)
    s.asserts    = (s.asserts or 0) + (entry.kind == "ASSERT" and 1 or 0)
  end

  -- UI updates are routed via the callback fired from DB:UpsertGroup().
  if RDL.Validation and RDL.Validation.OnEntryStored then
    pcall(function() RDL.Validation:OnEntryStored(entry, "stored") end)
  end
  return "stored"
end

-- Expose for other Capture sub-modules (Warnings, Taint)
Capture.BuildEntry = BuildEntry
Capture.StoreEntry = StoreEntry

-- Flush queued entries captured before DB/SavedVariables were ready.
function Capture:FlushBootQueue()
  if not self._bootQueue or #self._bootQueue == 0 then return end
  if not RDL.DB or not RDL.DB.IsReady or not RDL.DB:IsReady() then return end
  local q = self._bootQueue
  self._bootQueue = {}
  for i = 1, #q do
    local e = q[i]
    if e then
      pcall(function() StoreEntry(e) end)
    end
  end
end

Capture.CaptureLocals = CaptureLocals

-- Ownership sync + diagnostics --------------------------------------------

local function IsAddonLoaded(name)
  if type(name) ~= "string" then return false end
  if _G.C_AddOns and type(_G.C_AddOns.IsAddOnLoaded) == "function" then
    local ok, v = pcall(_G.C_AddOns.IsAddOnLoaded, name)
    return ok and v and true or false
  end
  if type(_G.IsAddOnLoaded) == "function" then
    local ok, v = pcall(_G.IsAddOnLoaded, name)
    return ok and v and true or false
  end
  return false
end

function Capture:SyncOwnership(reason)
  if not self._handler and self.EnsureHandler then
    pcall(function() self:EnsureHandler(geterrorhandler(), "sync") end)
  end

  local nowEH = geterrorhandler()
  local ownedNow = (self._handler ~= nil) and (nowEH == self._handler)
  local previousState = self.ownerInfo and self.ownerInfo.state or nil

  self.ownsHandler = ownedNow and true or false

  self.ownerInfo = self.ownerInfo or {}
  self.ownerInfo.mode = self._handlerMode
  self.ownerInfo.nowHandlerSrc = FuncSrc(nowEH)
  self.ownerInfo.nowHandlerAddon = AddonFromSrc(self.ownerInfo.nowHandlerSrc)

  if ownedNow then
    self._setEHBlocked = false
    self:_SetOwnershipState("owned", "owned")
    return
  end

  if self._setEHBlocked then
    self:_SetOwnershipState("blocked", "seterrorhandler-noop", {
      blockedBy = self.ownerInfo.blockedBy or self.ownerInfo.nowHandlerAddon or "unknown",
    })
    return
  end

  -- If we previously believed we owned it, mark as replaced after boot.
  if previousState == "owned" then
    self:_SetOwnershipState("replaced", "replaced_late", {
      replacedBy = self.ownerInfo.nowHandlerAddon,
    })
  else
    self:_SetOwnershipState("not-owned", tostring(reason or "not-owned"))
  end
end

-- Probe whether global seterrorhandler() is functional (some addons replace it with a no-op). (some addons replace it with a no-op).
-- This temporarily swaps the handler to a probe function and restores it immediately.
function Capture:ProbeSetErrorHandler()
  local out = { ts = time() }
  local before = geterrorhandler()
  local probe = function() end

  local function Try(setter, label)
    if type(setter) ~= "function" then
      out[label .. "_ok"] = false
      out[label .. "_src"] = FuncSrc(setter)
      return
    end
    out[label .. "_src"] = FuncSrc(setter)

    local okSet = pcall(setter, probe)
    local after = geterrorhandler()
    local works = okSet and (after == probe)
    out[label .. "_ok"] = works and true or false

    -- Restore
    if works then
      pcall(setter, before)
    end
  end

  Try(_G.seterrorhandler, "global")
  Try(self._real_seterrorhandler, "real")

  out.before_src = FuncSrc(before)
  out.before_addon = AddonFromSrc(out.before_src)

  self.ownerInfo = self.ownerInfo or {}
  self.ownerInfo.setEHProbe = out
  self._setEHProbe = out

  return out
end

-- Fallback capture when we do not own the handler.
--  1) Hook Blizzard ScriptErrorsFrame reporting (if available)
--  2) Import BugGrabberDB if enabled
function Capture:InstallFallbackHooks()
  local settings = (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or {}
  self._fallback = self._fallback or {}

  local function ShouldSkipFallbackCapture()
    -- Keep fallback active to recover from primary-path failures.
    -- Duplicate suppression is done via guarded forwarding keys.
    return false
  end

  local function CaptureFallbackLuaError(source, message, stack, locals, extra)
    if not Capture or Capture._disabled then return end
    if ShouldSkipFallbackCapture() then return end

    local msg = tostring(message or "")
    if msg == "" then return end

    local st = (type(stack) == "string" and stack) or ""
    if st == "" and type(_G.debugstack) == "function" then
      local okS, s = pcall(_G.debugstack, 3, 40, 40)
      if okS and type(s) == "string" then st = s end
    end

    local msgKey = BuildLuaErrorMessageKey(msg)
    local key = BuildLuaErrorKey(msg, st)
    local now = NowPrecise()
    local guardAt = tonumber(Capture._forwardingPrevAt) or 0
    if (now - guardAt) <= 0.25 then
      local sameForwardKey = (Capture._forwardingPrevErrorKey and Capture._forwardingPrevErrorKey == key)
      local sameForwardMsg = (Capture._forwardingPrevErrorMsgKey and Capture._forwardingPrevErrorMsgKey == msgKey)
      if sameForwardKey or sameForwardMsg then
        return
      end
    end
    if Capture._lastFallbackLuaErrorKey and Capture._lastFallbackLuaErrorKey == key then
      local lastAt = tonumber(Capture._lastFallbackLuaErrorAt) or 0
      if (now - lastAt) <= 0.001 then
        return
      end
    end

    local ex = {
      source = source,
      hooked = true,
      owned = Capture.ownsHandler and true or false,
    }
    if type(extra) == "table" then
      for k, v in pairs(extra) do ex[k] = v end
    end

    local ok, entry = pcall(BuildEntry, "LUA_ERROR", msg, st, locals, nil, nil, ex)
    if ok and entry then
      local okStore, statusOrErr = pcall(StoreEntry, entry)
      if (not okStore) and RDL and RDL.Log then
        pcall(function()
          RDL:Log("ERROR", "CAPTURE", "Fallback StoreEntry failed", { err = tostring(statusOrErr), source = source })
        end)
      elseif okStore and statusOrErr and statusOrErr ~= "failed" then
        BumpScriptErrorsSyncKey(key, 1)
        Capture._lastFallbackLuaErrorKey = key
        Capture._lastFallbackLuaErrorAt = now
      end
    end
  end

  -- Fallback path for modern clients: register with Blizzard_ScriptErrors pipeline.
  -- This catches hard errors while HandleLuaError owns seterrorhandler().
  if settings.fallbackHookScriptErrors ~= false
      and not self._fallback.blizzardLuaHandlerHooked
      and type(_G.AddLuaErrorHandler) == "function" then
    local okAdd = pcall(_G.AddLuaErrorHandler, function(message, stack, locals)
      CaptureFallbackLuaError("AddLuaErrorHandler", message, stack, locals, { hookType = "blizzard-script-errors" })
    end)
    if okAdd then
      self._fallback.blizzardLuaHandlerHooked = true
    end
  end

  -- Import early unhandled errors accumulated by Blizzard_ScriptErrors before our hooks were active.
  if settings.fallbackHookScriptErrors ~= false and not self._fallback.importedUnhandledScriptErrors then
    local didAttempt = false
    if type(_G.ScriptErrors) == "table" and type(_G.ScriptErrors.GetUnhandledErrors) == "function" then
      didAttempt = true
      local okList, list = pcall(_G.ScriptErrors.GetUnhandledErrors, _G.ScriptErrors)
      if okList and type(list) == "table" then
        for i = 1, #list do
          local rec = list[i]
          if type(rec) == "table" then
            CaptureFallbackLuaError(
              "ScriptErrorsUnhandled",
              rec.errorMessage or rec.message,
              rec.stack,
              rec.locals,
              { hookType = "script-errors-unhandled", unhandledIndex = i }
            )
          end
        end
      end
    end
    if didAttempt then
      self._fallback.importedUnhandledScriptErrors = true
    end
  end

  -- Delta sync from ScriptErrorsFrame.errorData (hard errors only).
  -- Purpose: recover misses without relying on BugGrabber.
  local function SyncScriptErrorsFrameDelta()
    if not Capture or Capture._disabled then return end
    local frame = _G.ScriptErrorsFrame
    if type(frame) ~= "table" or type(frame.errorData) ~= "table" then return end

    local byKey = Capture._scriptErrorsSyncCountByKey or {}
    Capture._scriptErrorsSyncCountByKey = byKey

    local budget = tonumber(settings.scriptErrorsFrameImportMaxPerPoll) or 60
    if budget < 1 then budget = 1 end

    local stopImport = false
    local seen = {}
    local data = frame.errorData
    for i = 1, #data do
      if stopImport or budget <= 0 then break end
      local rec = data[i]
      if type(rec) == "table" then
        local mt = tonumber(rec.messageType)
        if mt == nil or mt == 0 then -- hard errors only (warnings are handled elsewhere)
          local msg = tostring(rec.message or "")
          if msg ~= "" then
            local st = (type(rec.stack) == "string" and rec.stack) or ""
            local key = BuildLuaErrorKey(msg, st)
            seen[key] = true

            local sourceCount = tonumber(rec.count) or 1
            if sourceCount < 1 then sourceCount = 1 end
            local seenCount = tonumber(byKey[key]) or 0

            if sourceCount > seenCount then
              local delta = sourceCount - seenCount
              local importedNow = 0
              for j = 1, delta do
                if budget <= 0 then break end
                local ok, entry = pcall(BuildEntry, "LUA_ERROR", msg, st, rec.locals, nil, nil, {
                  source = "ScriptErrorsFrameSync",
                  imported = true,
                  frameCounter = sourceCount,
                  frameCounterImportedFrom = seenCount,
                  frameCounterImportedStep = j,
                  frameIndex = i,
                })
                if not ok or not entry then break end
                local okStore, status = pcall(StoreEntry, entry)
                if not okStore then break end
                if status == "throttled" then
                  stopImport = true
                  break
                end
                if status == "stored" or status == "queued" or status == "ignored" then
                  importedNow = importedNow + 1
                  budget = budget - 1
                elseif status == "failed" then
                  break
                else
                  if status then
                    importedNow = importedNow + 1
                    budget = budget - 1
                  else
                    break
                  end
                end
              end
              if importedNow > 0 then
                byKey[key] = seenCount + importedNow
              end
            elseif sourceCount < seenCount then
              byKey[key] = sourceCount
            end
          end
        end
      end
    end

    -- Cleanup stale keys that are no longer present in ScriptErrorsFrame.
    for key in pairs(byKey) do
      if not seen[key] then
        byKey[key] = nil
      end
    end
  end

  if settings.fallbackHookScriptErrors ~= false and not self._fallback.scriptErrorsFrameSyncEnabled then
    if _G.C_Timer and type(_G.C_Timer.NewTicker) == "function" then
      local poll = tonumber(settings.scriptErrorsFrameSyncPollSec) or 1.0
      if poll < 0.25 then poll = 0.25 end
      self._fallback.scriptErrorsFrameSyncTicker = _G.C_Timer.NewTicker(poll, function()
        pcall(SyncScriptErrorsFrameDelta)
      end)
      self._fallback.scriptErrorsFrameSyncEnabled = true
      -- One immediate sync for errors already present right now.
      pcall(SyncScriptErrorsFrameDelta)
    end
  end

  -- Hook script error rendering (build-dependent).
  if settings.fallbackHookScriptErrors ~= false and not self._fallback.scriptErrorsHooked then
    local hooked = false

    if type(_G.hooksecurefunc) == "function" then
      if type(_G.ScriptErrorsFrame_OnError) == "function" then
        -- Legacy clients.
        hooksecurefunc("ScriptErrorsFrame_OnError", function(message, stack)
          CaptureFallbackLuaError("ScriptErrorsFrame_OnError", message, stack, nil, nil)
        end)
        hooked = true
        self._fallback.scriptErrorsHookType = "legacy-global"
      elseif type(_G.ScriptErrorsFrameMixin) == "table"
          and type(_G.ScriptErrorsFrameMixin.DisplayMessageInternal) == "function" then
        -- Midnight 12.x path: ScriptErrorsFrameMixin:DisplayMessageInternal(message, messageType, stack, locals)
        hooksecurefunc(_G.ScriptErrorsFrameMixin, "DisplayMessageInternal",
          function(_, message, messageType, stack, locals)
            -- Warnings are routed separately via LUA_WARNING; for this fallback capture only hard errors.
            local isWarning = (type(messageType) == "number" and messageType == 1)
            if isWarning then
              return
            end
            local hasErrorStack = (type(stack) == "string" and stack ~= "")
            local hasLocals = (locals ~= nil)
            if type(messageType) ~= "number" and not hasErrorStack and not hasLocals then
              return
            end
            CaptureFallbackLuaError("ScriptErrorsFrameMixin", message, stack, locals, { messageType = messageType })
          end)
        hooked = true
        self._fallback.scriptErrorsHookType = "mixin"
      end
    end

    if hooked then
      self._fallback.scriptErrorsHooked = true
    elseif not self._fallback.waitingScriptErrors then
      -- If ScriptErrors modules are not loaded yet, retry after they load.
      self._fallback.waitingScriptErrors = true
      local waiter = CreateFrame("Frame")
      waiter:RegisterEvent("ADDON_LOADED")
      waiter:SetScript("OnEvent", function(_, _, addon)
        if addon == "Blizzard_DebugTools" or addon == "Blizzard_ScriptErrorsFrame" or addon == "Blizzard_ScriptErrors" then
          waiter:UnregisterEvent("ADDON_LOADED")
          waiter:SetScript("OnEvent", nil)
          if Capture and Capture.InstallFallbackHooks then
            pcall(function() Capture:InstallFallbackHooks() end)
          end
        end
      end)
    end
  end

  -- Import BugGrabberDB if present and enabled
  if settings.importBugGrabber ~= false and not self.ownsHandler and self.BugGrabber and self.BugGrabber.Enable then
    if self.BugGrabber:IsPresent() then
      self.BugGrabber:Enable()
      self._fallback.bugGrabberEnabled = true
    end
  end

  -- Record likely owners
  self.ownerInfo = self.ownerInfo or {}
  self.ownerInfo.addons = self.ownerInfo.addons or {}
  self.ownerInfo.addons.BugGrabber = IsAddonLoaded("!BugGrabber") or IsAddonLoaded("BugGrabber")
  self.ownerInfo.addons.BugSack = IsAddonLoaded("BugSack")
  self.ownerInfo.addons.DebugTools = IsAddonLoaded("Blizzard_DebugTools")
end

-- Handler ownership ----------------------------------------------------

local function GetMode()
  local s = (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or {}
  local mode = tostring(s.errorHandlerMode or "chain"):lower()
  if mode ~= "exclusive" and mode ~= "chain" then mode = "chain" end
  return mode, s
end

-- Ownership state helpers (single source of truth for UI/diagnostics)
-- state: "owned" | "blocked" | "replaced" | "not-owned"
function Capture:_SetOwnershipState(state, reason, extra)
  self.ownerInfo = self.ownerInfo or {}
  self.ownerInfo.state = tostring(state or "not-owned")
  if reason ~= nil then
    self.ownerInfo.reason = tostring(reason)
  end
  self.ownerInfo.mode = self._handlerMode or self.ownerInfo.mode

  if type(extra) == "table" then
    for k, v in pairs(extra) do
      self.ownerInfo[k] = v
    end
  end
end

function Capture:GetOwnershipState()
  local eh = geterrorhandler()
  return {
    owns = self.ownsHandler and true or false,
    state = (self.ownerInfo and self.ownerInfo.state) or "not-owned",
    mode = self._handlerMode or ((self.ownerInfo and self.ownerInfo.mode) or "?"),
    nowHandlerSrc = FuncSrc(eh),
    nowHandlerAddon = AddonFromSrc(FuncSrc(eh)),
    prevHandlerSrc = FuncSrc(self.prevErrorHandler),
    prevHandlerAddon = AddonFromSrc(FuncSrc(self.prevErrorHandler)),
  }
end

-- Build or rebuild the handler function we install via seterrorhandler().
-- In chain mode, we wrap the current handler to preserve compatibility (BugGrabber/BugSack/Blizzard).
function Capture:EnsureHandler(prev, reason)
  local mode = GetMode()

  if mode == "chain" then
    if type(prev) ~= "function" then prev = geterrorhandler() end

    if self._handler and self._handlerMode == "chain" and self._handlerPrev == prev then
      return
    end

    self._handlerMode = "chain"
    self._handlerPrev = prev

    self._handler = function(err)
      local settings = (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or {}

      if self._disabled then
        if settings.chainCallPrevHandler and type(prev) == "function" and prev ~= self._handler then
          pcall(prev, err)
        end
        return
      end

      local stack = (type(_G.debugstack) == "function") and _G.debugstack(2, 40, 40) or ""
      self._inChainWrapper = true
      local captured, key, msgKey = self:OnLuaError(err, stack, true)
      self._inChainWrapper = false

      -- Forward to previous handler once (BugGrabber/BugSack/Blizzard). Guard against recursion loops.
      if settings.chainCallPrevHandler and type(prev) == "function" and prev ~= self._handler then
        if not self._callingPrevHandler then
          if captured and key then
            self._forwardingPrevErrorKey = key
            self._forwardingPrevErrorMsgKey = msgKey or BuildLuaErrorMessageKey(err)
            self._forwardingPrevAt = NowPrecise()
          else
            self._forwardingPrevErrorKey = nil
            self._forwardingPrevErrorMsgKey = nil
            self._forwardingPrevAt = nil
          end
          self._callingPrevHandler = true
          pcall(prev, err)
          self._callingPrevHandler = false
          self._forwardingPrevErrorKey = nil
          self._forwardingPrevErrorMsgKey = nil
          self._forwardingPrevAt = nil
        end
      end
    end
    RDL.ErrorHandler = self._handler
  else
    if self._handler and self._handlerMode == "exclusive" then
      return
    end

    self._handlerMode = "exclusive"
    self._handlerPrev = nil

    self._handler = function(err)
      if self._disabled then
        if type(self.prevErrorHandler) == "function" then
          pcall(self.prevErrorHandler, err)
        end
        return
      end
      local stack = (type(_G.debugstack) == "function") and _G.debugstack(2, 40, 40) or ""
      self:OnLuaError(err, stack, false)
    end
    RDL.ErrorHandler = self._handler
  end
end

function Capture:ApplyHandlerLock()
  local mode, settings = GetMode()
  local want = settings and settings.lockErrorHandler

  -- lock only makes sense in exclusive mode while we own the handler
  if mode ~= "exclusive" or not self.ownsHandler or type(self._real_seterrorhandler) ~= "function" then
    if self._locked and type(self._real_seterrorhandler) == "function" then
      _G.seterrorhandler = self._real_seterrorhandler
      self._locked = false
      RDL:Log("INFO", "CAPTURE", "Unlocked seterrorhandler() (mode/ownership)", { mode = mode, owns = self.ownsHandler })
    end
    return
  end

  if want and not self._locked then
    _G.seterrorhandler = function() end
    self._locked = true
    RDL:Log("INFO", "CAPTURE", "Locked seterrorhandler()", {})
  elseif (not want) and self._locked then
    _G.seterrorhandler = self._real_seterrorhandler
    self._locked = false
    RDL:Log("INFO", "CAPTURE", "Unlocked seterrorhandler()", {})
  end
end

function Capture:TryReclaimHandler(reason)
  if self.ownsHandler then return true end

  if self._setEHBlocked then
    local okProbe, probe = pcall(function() return self:ProbeSetErrorHandler() end)
    if okProbe and type(probe) == "table" and probe.global_ok then
      self._setEHBlocked = false
      self._real_seterrorhandler = (type(_G.seterrorhandler) == "function") and _G.seterrorhandler or nil
    else
      local blockedBy = (okProbe and type(probe) == "table" and probe.before_addon)
          or (self.ownerInfo and self.ownerInfo.blockedBy)
          or "unknown"
      self:_SetOwnershipState("blocked", "seterrorhandler-noop", { blockedBy = blockedBy })
      return false
    end
  end

  local prev = geterrorhandler()
  if self.EnsureHandler then
    pcall(function() self:EnsureHandler(prev, reason) end)
  end

  local setEH = self._real_seterrorhandler or (type(_G.seterrorhandler) == "function" and _G.seterrorhandler)
  if type(setEH) ~= "function" or not self._handler then return false end

  local ok = pcall(setEH, self._handler)
  local nowEH = geterrorhandler()

  self.ownerInfo = self.ownerInfo or {}
  self.ownerInfo.reclaim = self.ownerInfo.reclaim or {}
  self.ownerInfo.reclaim[#self.ownerInfo.reclaim + 1] = {
    ts = time(), reason = tostring(reason), ok = ok and true or false, nowHandlerSrc = FuncSrc(nowEH),
  }

  if nowEH == self._handler then
    self.ownsHandler = true
    self.ownerInfo.nowHandlerSrc = FuncSrc(nowEH)
    self.ownerInfo.nowHandlerAddon = AddonFromSrc(self.ownerInfo.nowHandlerSrc)
    self:_SetOwnershipState("owned", reason)
    self:ApplyHandlerLock()
    RDL:Log("INFO", "CAPTURE", "Reclaimed Lua errorhandler", { reason = reason, mode = self._handlerMode })
    return true
  end

  self.ownerInfo.nowHandlerSrc = FuncSrc(nowEH)
  self.ownerInfo.nowHandlerAddon = AddonFromSrc(self.ownerInfo.nowHandlerSrc)
  self:_SetOwnershipState("not-owned", reason)
  RDL:Log("WARN", "CAPTURE", "Failed to reclaim Lua errorhandler", { reason = reason, now = FuncSrc(nowEH) })
  return false
end

function Capture:EarlyInit()
  if self._earlyInited then return end
  self._earlyInited = true

  -- Ensure DB exists ASAP (store errors during addon load).
  if RDL.DB and RDL.DB.EnsureReady then
    if RDL.Internal and RDL.Internal.Call then
      RDL.Internal:Call(RDL.addonName, "DB:EnsureReady", RDL.DB.EnsureReady, RDL.DB)
    else
      pcall(function() RDL.DB:EnsureReady() end)
    end
  end

  local oldEH = geterrorhandler()
  self.prevErrorHandler = oldEH
  self.ownsHandler = false

  self.ownerInfo = {
    seterrorhandlerSrc = FuncSrc(_G.seterrorhandler),
    oldHandlerSrc = FuncSrc(oldEH),
    oldHandlerAddon = AddonFromSrc(FuncSrc(oldEH)),
  }

  if self.EnsureHandler then
    pcall(function() self:EnsureHandler(oldEH, "early") end)
  end

  local probe = nil
  if self.ProbeSetErrorHandler then
    local okProbe, p = pcall(function() return self:ProbeSetErrorHandler() end)
    if okProbe and type(p) == "table" then
      probe = p
    end
  end

  local skipSetAttempt = (probe and probe.global_ok == false) and true or false
  local okSet = false

  if skipSetAttempt then
    self._setEHBlocked = true
    self._real_seterrorhandler = nil
    local blockedBy = probe.before_addon or "unknown"
    self.ownerInfo.mode = self._handlerMode
    self.ownerInfo.setAttemptOk = false
    self.ownerInfo.nowHandlerSrc = FuncSrc(geterrorhandler())
    self.ownerInfo.nowHandlerAddon = AddonFromSrc(self.ownerInfo.nowHandlerSrc)
    self:_SetOwnershipState("blocked", "seterrorhandler-noop", {
      blockedBy = blockedBy,
      blockedSrc = probe.global_src or probe.before_src,
    })
    RDL:Log("WARN", "CAPTURE", "seterrorhandler blocked; fallback mode", {
      blockedBy = blockedBy,
      seterrorhandlerSrc = probe.global_src,
      currentHandlerSrc = self.ownerInfo.nowHandlerSrc,
    })
    pcall(function() self:InstallFallbackHooks() end)
  else
    self._setEHBlocked = false
    self._real_seterrorhandler = (type(_G.seterrorhandler) == "function") and _G.seterrorhandler or nil
    if type(self._real_seterrorhandler) == "function" then
      okSet = pcall(self._real_seterrorhandler, self._handler)
    end

    local nowEH = geterrorhandler()
    self.ownerInfo.nowHandlerSrc = FuncSrc(nowEH)
    self.ownerInfo.nowHandlerAddon = AddonFromSrc(self.ownerInfo.nowHandlerSrc)
    self.ownerInfo.setAttemptOk = okSet and true or false
    self.ownerInfo.mode = self._handlerMode

    if nowEH == self._handler then
      self.ownsHandler = true
      self:_SetOwnershipState("owned", "early")
    else
      if nowEH == oldEH then
        self:_SetOwnershipState("blocked", "early")
      else
        self:_SetOwnershipState("replaced", "early")
      end
    end
  end

  self:ApplyHandlerLock()

  -- Observe later seterrorhandler() calls by other addons so we can react immediately.
  if type(hooksecurefunc) == "function" and not self._setEHHooked then
    self._setEHHooked = true
    pcall(function()
      hooksecurefunc("seterrorhandler", function(newHandler)
        if not Capture or Capture._disabled then return end
        if newHandler == Capture._handler then return end
        Capture.ownerInfo = Capture.ownerInfo or {}
        Capture.ownerInfo.lastSetEHNewSrc = FuncSrc(newHandler)
        Capture.ownerInfo.lastSetEHNewAddon = AddonFromSrc(Capture.ownerInfo.lastSetEHNewSrc)
        pcall(function() Capture:SyncOwnership("seterrorhandler") end)
        if not Capture.ownsHandler and Capture.TryReclaimHandler then
          if not Capture._reclaimFromSetEHInProgress then
            Capture._reclaimFromSetEHInProgress = true
            pcall(function() Capture:TryReclaimHandler("seterrorhandler-immediate") end)
            Capture._reclaimFromSetEHInProgress = false
          end
          if not Capture.ownsHandler and _G.C_Timer and type(_G.C_Timer.After) == "function" then
            _G.C_Timer.After(0, function()
              if Capture and Capture.TryReclaimHandler then
                pcall(function() Capture:TryReclaimHandler("seterrorhandler-deferred") end)
              end
            end)
          end
        end
      end)
    end)
  end

  -- Suppress Blizzard popups/UI ASAP

  -- Ownership watchdog: if another addon replaces the handler after login, try to reclaim/chains-wrap it.
  local settings = (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or {}
  if settings.maintainOwnership ~= false then
    local interval = tonumber(settings.maintainOwnershipIntervalSec) or 4
    if interval < 1 then interval = 1 end

    if _G.C_Timer and type(_G.C_Timer.NewTicker) == "function" and not self._ownerTicker then
      self._ownerTicker = _G.C_Timer.NewTicker(interval, function()
        if not Capture or Capture._disabled then return end
        if Capture.ownsHandler then return end
        if Capture.TryReclaimHandler then
          pcall(function() Capture:TryReclaimHandler("watchdog") end)
        end
        pcall(function() Capture:InstallFallbackHooks() end)
      end)
    end
  end

  if RDL.Suppress then
    if RDL.Internal and RDL.Internal.Call then
      RDL.Internal:Call(RDL.addonName, "Suppress:SuppressAll", RDL.Suppress.SuppressAll, RDL.Suppress)
    else
      pcall(function() RDL.Suppress:SuppressAll() end)
    end
  end
end

function Capture:Init()
  self:EarlyInit()

  -- Optional chat tap: capture addon-printed error stacks (suppressed errors).
  if self.ChatTap and self.ChatTap.Init then
    if RDL.Internal and RDL.Internal.Call then
      RDL.Internal:Call(RDL.addonName, "ChatTap:Init", self.ChatTap.Init, self.ChatTap)
      self._fallback = self._fallback or {}
      self._fallback.chatTapHooked = true
    else
      pcall(function() self.ChatTap:Init() end)
      self._fallback = self._fallback or {}
      self._fallback.chatTapHooked = true
    end
  end

  if not self.ownsHandler then
    RDL:Log("WARN", "CAPTURE", "Cannot own errorhandler", {
      reason = self.ownerInfo and self.ownerInfo.reason or "<?>",
      nowHandlerAddon = self.ownerInfo and self.ownerInfo.nowHandlerAddon or nil,
      nowHandlerSrc = self.ownerInfo and self.ownerInfo.nowHandlerSrc or nil,
    })
  else
    RDL:Log("INFO", "CAPTURE", "Owned global Lua errorhandler", {
      seterrorhandlerSrc = self.ownerInfo and self.ownerInfo.seterrorhandlerSrc or nil,
    })
  end

  self:ApplyHandlerLock()

  -- Sync ownership and install fallback hooks (ScriptErrorsFrame hook / BugGrabber import).
  pcall(function() self:SyncOwnership("init") end)
  pcall(function() self:InstallFallbackHooks() end)

  -- Re-check shortly after login: other addons may claim the handler after our EarlyInit().
  if _G.C_Timer and type(_G.C_Timer.After) == "function" then
    _G.C_Timer.After(1.5, function()
      if not Capture then return end
      pcall(function() Capture:SyncOwnership("post-load") end)
      if not Capture.ownsHandler and Capture.TryReclaimHandler then
        pcall(function() Capture:TryReclaimHandler("post-load") end)
      end
      pcall(function() Capture:InstallFallbackHooks() end)
    end)
  end
end

-- Error handlers --------------------------------------------------------

function Capture:OnLuaError(err, stack, noForward)
  if self._disabled then return end
  if self._inHandler then
    if type(self.prevErrorHandler) == "function" then
      pcall(self.prevErrorHandler, err)
    end
    return
  end

  self._inHandler = true
  local captured = false
  local errorKey = nil
  local errorMsgKey = nil
  local okRun, runErr = xpcall(function()
    -- Prefer Blizzard/BugGrabber-like error stack data for hard errors.
    local errStack, hardLocals, hardMeta = CaptureHardErrorData(stack)

    -- Capture locals (calibrated) only when hard-path locals are unavailable.
    local locals, lmeta = hardLocals, nil
    local U = RDL.Util
    local addonHint = (U and U.GuessAddonFromStack) and U:GuessAddonFromStack(errStack) or nil
    if (not locals) and RDL.Locals and RDL.Locals.CaptureBest then
      local okL, l, m = pcall(function()
        return RDL.Locals:CaptureBest({ addon = addonHint, stack = errStack, baseLevel = 3 })
      end)
      if okL then locals, lmeta = l, m end
    elseif not locals then
      locals = CaptureLocals(3)
    end

    errorMsgKey = BuildLuaErrorMessageKey(err)
    errorKey = BuildLuaErrorKey(err, errStack)
    local ok, entry = pcall(BuildEntry, "LUA_ERROR", err, errStack, locals, nil, nil, {
      localsProbe = lmeta,
      hardErrorProbe = hardMeta,
    })
    if ok and entry then
      local okStore, storeStatus = pcall(StoreEntry, entry)
      if okStore then
        if storeStatus ~= "failed" then
          captured = true
          BumpScriptErrorsSyncKey(errorKey, 1)
        end
        RDL:Log("ERROR", "LUA", "Lua error captured", { addon = entry.addon, func = entry.func })
      else
        RDL:Log("ERROR", "CAPTURE", "StoreEntry failed", { err = tostring(storeStatus) })
      end
    else
      RDL:Log("ERROR", "CAPTURE", "BuildEntry failed", { err = entry })
      -- Fallback entry so UI is never empty after a reported capture
      local U = RDL.Util
      local msg = (U and U.SafeToString) and U:SafeToString(err) or tostring(err)
      msg = tostring(msg or "")
      local fbSig = "FALLBACK|LUA_ERROR|" .. string.sub(msg:gsub("|", "/"), 1, 180)
      local fb = {
        ts = time(),
        sessionId = (RDL.DB and RDL.DB.sessionId) or nil,
        kind = "LUA_ERROR",
        message = msg,
        stack = errStack or "",
        addon = "<?>",
        func = "<?>",
        sys = { ts = time(), fallback = true },
        ctx = { extra = { fallback = true, buildEntryErr = tostring(entry) } },
        sig = fbSig,
      }
      local okStore, storeStatus = pcall(StoreEntry, fb)
      if not okStore then
        RDL:Log("ERROR", "CAPTURE", "StoreEntry fallback failed", { err = tostring(storeStatus) })
      elseif storeStatus ~= "failed" then
        captured = true
        BumpScriptErrorsSyncKey(errorKey, 1)
      end
    end

    -- Reset Doctor stack after hard error
    if RDL.Doctor then RDL.Doctor:Reset() end

    local link = ""
    if RDL.UI and RDL.UI.MakeSigLink and self._lastStoredSig then
      link = " " .. tostring(RDL.UI:MakeSigLink(self._lastStoredSig, "open"))
    end
    ChatNotifyThrottled("|cffff3333RothDevLib|r captured Lua error." .. link .. " Use |cffffff00/rdev|r")

    -- Forward to previous handler if configured.
    -- In chain mode we typically forward in the wrapper to avoid double-calling.
    local settings = RDL.DB and RDL.DB:GetSettings()
    if (not noForward) and settings and settings.forwardToDefaultErrorHandler and type(self.prevErrorHandler) == "function" then
      pcall(self.prevErrorHandler, err)
    end
  end, function(e)
    return tostring(e)
  end)

  self._inHandler = false
  if not okRun then
    RDL:Log("ERROR", "CAPTURE", "OnLuaError failed", { err = tostring(runErr) })
  end
  return captured, errorKey, errorMsgKey
end

function Capture:OnSuppressedError(err, stack, locals, addonName, funcName, extra)
  if self._disabled then return end
  local ex = { suppressed = true }
  if type(extra) == "table" then
    for k, v in pairs(extra) do ex[k] = v end
  end
  local entry = BuildEntry("SUPPRESSED", err, stack, locals, addonName, funcName, ex)
  StoreEntry(entry)
  RDL:Log("WARN", "SUPPRESSED", "Suppressed error captured", { addon = entry.addon, func = entry.func })
end

function Capture:OnIntegrationEvent(kind, addonName, code, message, data, level)
  if self._disabled then return end
  kind = tostring(kind or "INTEGRATION")
  local U = RDL.Util

  local msg = message
  if msg == nil then msg = "" end
  msg = U and U:SafeToString(msg) or tostring(msg)
  if code then
    msg = (U and U:SafeToString(code) or tostring(code)) .. ": " .. msg
  end
  if level then
    msg = "[" .. (U and U:SafeToString(level) or tostring(level)) .. "] " .. msg
  end

  local stack = debugstack(3, 40, 40)
  local extra = { code = code, level = level, data = data, source = "integration" }
  local entry = BuildEntry(kind, msg, stack, nil, addonName, nil, extra)
  StoreEntry(entry)

  local logLevel = (kind == "ALERT") and "WARN" or "ERROR"
  RDL:Log(logLevel, kind, "Integration event captured", { addon = entry.addon, code = code })
end

function Capture:OnLeaveCombat()
  if self._pendingChatNotify then
    self._pendingChatNotify = false
    local link = ""
    if RDL.UI and RDL.UI.MakeSigLink and self._lastStoredSig then
      link = " " .. tostring(RDL.UI:MakeSigLink(self._lastStoredSig, "open"))
    end
    ChatNotifyThrottled("|cffff3333RothDevLib|r captured errors while in combat." .. link .. " Use |cffffff00/rdev|r")
  end
end

-- Self-tests ------------------------------------------------------------

function Capture:RunTest(kind)
  if kind == "suppressed" then
    RDL:SafeCall("RothDevLib", "Test:Suppressed", function()
      error("TEST_SUPPRESSED")
    end)
    return
  end
  if kind == "hard" then
    if RDL.Doctor then
      RDL.Doctor:Enter("RothDevLib", "Test:HardError", { note = "timer" })
    end
    C_Timer.After(0.05, function()
      error("TEST_HARD_ERROR")
    end)
    return
  end
  if kind == "warning" then
    if RDL.Capture and RDL.Capture.OnLuaWarning then
      RDL.Capture:OnLuaWarning("TEST_WARNING", "manual")
    end
    return
  end
  if kind == "taint" then
    if RDL.Capture and RDL.Capture.OnTaintEvent then
      RDL.Capture:OnTaintEvent("ADDON_ACTION_BLOCKED", RDL.addonName or "RothDevLib", "TEST_PROTECTED_CALL")
    end
    return
  end
  if kind == "taintmacro" then
    if RDL.Capture and RDL.Capture.OnTaintEvent then
      RDL.Capture:OnTaintEvent("MACRO_ACTION_BLOCKED", "TEST_MACRO_CALL")
    end
    return
  end
  if kind == "taintstate" then
    if RDL.Capture and RDL.Capture.OnRestrictionStateChanged then
      local t = _G.Enum and _G.Enum.AddOnRestrictionType and _G.Enum.AddOnRestrictionType.Combat or 0
      local s = _G.Enum and _G.Enum.AddOnRestrictionState and _G.Enum.AddOnRestrictionState.Active or 2
      RDL.Capture:OnRestrictionStateChanged("ADDON_RESTRICTION_STATE_CHANGED", t, s)
    end
    return
  end
  if kind == "breadcrumb" then
    RDL:Breadcrumb("RothDevLib", "test", "breadcrumb", { n = 1 })
    return
  end
  if kind == "metric" then
    RDL:Metric("RothDevLib", "test_metric", 123, "unit", { minInterval = 0 })
    return
  end
  if kind == "alert" then
    RDL:Alert("RothDevLib", "TEST_ALERT", "test alert", { a = 1 }, "WARN")
    return
  end
  if kind == "assert" then
    RDL:Assert("RothDevLib", false, "TEST_ASSERT", "test assert", { b = 2 })
    return
  end

  if kind == "report" then
    if RDL.ReportError then
      RDL:ReportError("RothDevLib", "TEST_REPORTED_ERROR",
        { func = "Test:Report", stack = debugstack(1, 40, 40), tag = "manual" })
    end
    return
  end

  if kind == "cpu" then
    if RDL.Profile then
      RDL:Profile("RothDevLib", "Test:CPU", function()
        local x = 0
        for i = 1, 300000 do x = x + i end
        return x
      end, { spikeMs = 1, metricMinInterval = 0 })
    end
    return
  end

  if kind == "mem" then
    if RDL.MemDelta then
      RDL:MemDelta("RothDevLib", "Test:Mem", function()
        local t = {}
        for i = 1, 8000 do t[i] = tostring(i) end
        return #t
      end, { spikeKB = 1, metricMinInterval = 0 })
    end
    return
  end
end

-- Install handler ASAP (at file load time) ------------------------------
pcall(function()
  Capture:EarlyInit()
end)
