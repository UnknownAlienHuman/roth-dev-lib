-- !RothDevLib/Core/Core.lua
-- Namespace, guarded public call wrappers, and lightweight integrity checks.

local ADDON = ...

_G.RothDevLib = _G.RothDevLib or {}
local RDL = _G.RothDevLib

RDL.name = "RothDevLib"
RDL.addonName = ADDON
RDL.version = "1.0.0-alpha.20.0"
RDL._initialized = false

-- Module slots populated by later TOC entries.
RDL.Util = nil
RDL.DB = nil
RDL.Logger = nil
RDL.Doctor = nil
RDL.Breadcrumbs = nil
RDL.Bus = nil
RDL.Capture = nil
RDL.Storm = nil
RDL.SecretGuard = nil
RDL.Locals = nil
RDL.UI = RDL.UI or {}

RDL._apiFingerprint = RDL._apiFingerprint or {}
RDL._timerFingerprint = RDL._timerFingerprint or {}

local Unpack = table.unpack or unpack

local function Pack(...)
  return { n = select("#", ...), ... }
end

local function CanAccess(value)
  local guard = RDL.SecretGuard
  if guard and type(guard.CanAccess) == "function" then
    local ok, accessible = pcall(guard.CanAccess, guard, value)
    if not ok or not accessible then return false end
  elseif type(_G.canaccessvalue) == "function" then
    local ok, accessible = pcall(_G.canaccessvalue, value)
    if not ok or not accessible then return false end
  end

  if guard and type(guard.IsSecret) == "function" then
    local ok, secret = pcall(guard.IsSecret, guard, value)
    if not ok or secret then return false end
  elseif type(_G.issecretvalue) == "function" then
    local ok, secret = pcall(_G.issecretvalue, value)
    if not ok or secret then return false end
  end

  return true
end

local function IsCallable(value)
  if not CanAccess(value) then return false end
  return type(value) == "function"
end

local function SafeText(value, fallback, maxBytes)
  fallback = fallback or "<?>"
  maxBytes = tonumber(maxBytes) or 256

  if not CanAccess(value) then return "<inaccessible>" end
  if value == nil then return fallback end

  local util = RDL.Util
  if util and type(util.SafeToString) == "function" then
    local ok, text = pcall(util.SafeToString, util, value)
    if ok and type(text) == "string" then
      if #text > maxBytes then text = text:sub(1, maxBytes) end
      return text
    end
  end

  if type(value) ~= "string" then return fallback end
  if #value > maxBytes then return value:sub(1, maxBytes) end
  return value
end

local function SafeContext(value)
  if not CanAccess(value) then return "<inaccessible>" end
  if value == nil then return nil end

  local util = RDL.Util
  if util and type(util.CopyDiagnosticValue) == "function" then
    local ok, copy = pcall(util.CopyDiagnosticValue, util, value, {
      maxDepth = 4,
      maxEntries = 80,
      maxStringBytes = 4096,
    })
    if ok then return copy end
  end

  local kind = type(value)
  if kind == "string" then return SafeText(value, "", 4096) end
  if kind == "number" or kind == "boolean" or kind == "nil" then return value end
  return "<" .. kind .. ">"
end

local function SafeDebugStack(level)
  if type(_G.debugstack) ~= "function" then return "" end
  local ok, stack = pcall(_G.debugstack, level or 2, 40, 40)
  if ok and type(stack) == "string" then return stack end
  return ""
end

local function EnterDoctor(addonName, funcName, ctx)
  local doctor = RDL.Doctor
  if doctor and type(doctor.Enter) == "function" then
    pcall(doctor.Enter, doctor, addonName, funcName, SafeContext(ctx))
  end
end

local function LeaveDoctor()
  local doctor = RDL.Doctor
  if doctor and type(doctor.Leave) == "function" then
    pcall(doctor.Leave, doctor)
  end
end

local function CaptureLocals(addonName, stack)
  local locals, meta
  if RDL.Locals and type(RDL.Locals.CaptureBest) == "function" then
    local ok, captured, capturedMeta = pcall(RDL.Locals.CaptureBest, RDL.Locals, {
      addon = addonName,
      stack = stack,
      baseLevel = 2,
    })
    if ok then
      locals = captured
      meta = capturedMeta
    end
  elseif type(_G.debuglocals) == "function" then
    local ok, captured = pcall(_G.debuglocals, 2)
    if ok and captured and RDL.Util and type(RDL.Util.FilterLocals) == "function" then
      local maxBytes = 8192
      if RDL.DB and type(RDL.DB.GetSettings) == "function" then
        local okSettings, settings = pcall(RDL.DB.GetSettings, RDL.DB)
        if okSettings and type(settings) == "table" then
          maxBytes = tonumber(settings.maxLocalsSize) or maxBytes
        end
      end
      local okFilter, filtered = pcall(RDL.Util.FilterLocals, RDL.Util, captured, maxBytes)
      if okFilter then locals = filtered end
    end
  end
  return locals, meta
end

local function ReportSuppressed(err, stack, locals, addonName, funcName, meta)
  local capture = RDL.Capture
  if capture and type(capture.OnSuppressedError) == "function" then
    pcall(capture.OnSuppressedError, capture, SafeText(err, "<error>", 4096), stack, locals, addonName, funcName, {
      localsProbe = SafeContext(meta),
    })
  end
end

local function NormalizeIdentity(addonName, funcName)
  return SafeText(addonName, "<?>", 128), SafeText(funcName, "<?>", 256)
end

local function RunProtected(addonName, funcName, ctx, fn, ...)
  if not IsCallable(fn) then return nil end
  addonName, funcName = NormalizeIdentity(addonName, funcName)
  EnterDoctor(addonName, funcName, ctx)

  local function ErrHandler(err)
    local stack = SafeDebugStack(3)
    local locals, meta = CaptureLocals(addonName, stack)
    ReportSuppressed(err, stack, locals, addonName, funcName, meta)
    return err
  end

  local result
  local cpu = RDL.CPU
  if cpu and type(cpu.Measure) == "function" then
    result = Pack(cpu:Measure(addonName, funcName, function(...)
      return xpcall(fn, ErrHandler, ...)
    end, nil, ...))
  else
    result = Pack(xpcall(fn, ErrHandler, ...))
  end

  LeaveDoctor()
  if result[1] then
    return Unpack(result, 2, result.n)
  end
  return nil
end

function RDL:Log(level, tag, message, data)
  local logger = self.Logger
  if not (logger and type(logger.Log) == "function") then return false end
  local ok = pcall(
    logger.Log,
    logger,
    SafeText(level, "INFO", 32),
    SafeText(tag, "LOG", 64),
    SafeText(message, "", 4096),
    SafeContext(data)
  )
  return ok
end

function RDL:SafeCall(addonName, funcName, fn, ...)
  return RunProtected(addonName, funcName, { note = "SafeCall" }, fn, ...)
end

function RDL:SafeCallCtx(addonName, funcName, ctx, fn, ...)
  return RunProtected(addonName, funcName, ctx, fn, ...)
end

function RDL:WrapUnsafe(addonName, funcName, fn, ctxFn)
  if not IsCallable(fn) then return nil end
  addonName, funcName = NormalizeIdentity(addonName, funcName)
  if not IsCallable(ctxFn) then ctxFn = nil end

  return function(...)
    local ctx
    if ctxFn then
      local ok, value = pcall(ctxFn, ...)
      if ok then ctx = value end
    end
    EnterDoctor(addonName, funcName, ctx)

    -- Deliberately do not catch target errors. The global error handler consumes
    -- the Doctor context and resets it after capture.
    local r1, r2, r3, r4, r5 = fn(...)
    LeaveDoctor()
    return r1, r2, r3, r4, r5
  end
end

function RDL:WrapSafe(addonName, funcName, fn, staticCtx)
  if not IsCallable(fn) then return nil end
  addonName, funcName = NormalizeIdentity(addonName, funcName)
  local ctx = SafeContext(staticCtx)
  return function(...)
    return RunProtected(addonName, funcName, ctx, fn, ...)
  end
end

function RDL:WrapSafeCtx(addonName, funcName, fn, ctxFn)
  if not IsCallable(fn) then return nil end
  addonName, funcName = NormalizeIdentity(addonName, funcName)
  if not IsCallable(ctxFn) then ctxFn = nil end

  return function(...)
    local ctx
    if ctxFn then
      local ok, value = pcall(ctxFn, ...)
      if ok then ctx = value end
    end
    return RunProtected(addonName, funcName, ctx, fn, ...)
  end
end

-- -----------------------------------------------------------------------------
-- Self-checks (correctness / taint risk)
-- -----------------------------------------------------------------------------

local function FnInfo(fn)
  if type(fn) ~= "function" then return nil end
  local dbg = _G and _G.debug
  local getinfo = (type(dbg) == "table" and type(dbg.getinfo) == "function") and dbg.getinfo or nil
  if type(getinfo) ~= "function" then return nil end
  local ok, info = pcall(getinfo, fn, "S")
  if not ok or type(info) ~= "table" then return nil end
  return {
    what = info.what,
    short_src = info.short_src,
    linedefined = info.linedefined,
    lastlinedefined = info.lastlinedefined,
  }
end

function RDL:_InitFingerprints()
  if self._apiFingerprint and self._apiFingerprint._init then return end
  self._apiFingerprint = self._apiFingerprint or {}
  self._apiFingerprint._init = true
  self._apiFingerprint.SafeCall = self.SafeCall
  self._apiFingerprint.SafeCallCtx = self.SafeCallCtx
  self._apiFingerprint.WrapSafe = self.WrapSafe
  self._apiFingerprint.WrapSafeCtx = self.WrapSafeCtx
  self._apiFingerprint.WrapUnsafe = self.WrapUnsafe

  self._timerFingerprint = self._timerFingerprint or {}
  local timers = _G.C_Timer
  self._timerFingerprint.atLoad = type(_G.time) == "function" and _G.time() or 0
  self._timerFingerprint.After = timers and timers.After or nil
  self._timerFingerprint.NewTicker = timers and timers.NewTicker or nil
  self._timerFingerprint.NewTimer = timers and timers.NewTimer or nil
  self._timerFingerprint.AfterInfo = FnInfo(timers and timers.After)
  self._timerFingerprint.NewTickerInfo = FnInfo(timers and timers.NewTicker)
  self._timerFingerprint.NewTimerInfo = FnInfo(timers and timers.NewTimer)
end

local function EmitAlert(code, message, data)
  if RDL.Capture and type(RDL.Capture.OnIntegrationEvent) == "function" then
    pcall(RDL.Capture.OnIntegrationEvent, RDL.Capture, "ALERT", RDL.addonName or "RothDevLib", code, message, data, "WARN")
  elseif RDL.Log then
    RDL:Log("WARN", "ALERT", message, { code = code, data = data })
  end
end

function RDL:SelfCheckEarly(stage)
  self:_InitFingerprints()
  stage = SafeText(stage, "early", 64)

  local api = self._apiFingerprint or {}
  local function CheckAPI(name)
    if api[name] and self[name] ~= api[name] then
      local expected = FnInfo(api[name])
      local actual = FnInfo(self[name])
      EmitAlert("API_OVERRIDDEN", "Public API method was overwritten: " .. name, {
        stage = stage,
        expected = expected and expected.short_src or "?",
        actual = actual and actual.short_src or "?",
      })
    end
  end
  CheckAPI("SafeCall")
  CheckAPI("SafeCallCtx")
  CheckAPI("WrapSafe")
  CheckAPI("WrapSafeCtx")
  CheckAPI("WrapUnsafe")

  local timers = _G.C_Timer
  local baseline = self._timerFingerprint or {}
  if timers and type(timers) == "table" then
    if baseline.After and timers.After ~= baseline.After then
      EmitAlert("C_TIMER_AFTER_HOOKED", "C_Timer.After was replaced after load (taint risk)", {
        stage = stage,
        baseline = baseline.AfterInfo,
        now = FnInfo(timers.After),
      })
    end
    if baseline.NewTicker and timers.NewTicker ~= baseline.NewTicker then
      EmitAlert("C_TIMER_NEWTICKER_HOOKED", "C_Timer.NewTicker was replaced after load (taint risk)", {
        stage = stage,
        baseline = baseline.NewTickerInfo,
        now = FnInfo(timers.NewTicker),
      })
    end
    if baseline.NewTimer and timers.NewTimer ~= baseline.NewTimer then
      EmitAlert("C_TIMER_NEWTIMER_HOOKED", "C_Timer.NewTimer was replaced after load (taint risk)", {
        stage = stage,
        baseline = baseline.NewTimerInfo,
        now = FnInfo(timers.NewTimer),
      })
    end

    local afterInfo = FnInfo(timers.After)
    if afterInfo and afterInfo.what == "Lua" then
      EmitAlert("C_TIMER_AFTER_LUA", "C_Timer.After appears to be a Lua function (likely hooked)", {
        stage = stage,
        now = afterInfo,
      })
    end
  end
end

RDL:_InitFingerprints()
