-- !RothDevLib/Core/Core.lua
-- Global namespace + public API surface.
-- Merged from !RothGrabber/Core.lua + RothDevLib/Bootstrap.lua.
-- Single addon: ! prefix ensures earliest load order.

local ADDON, ns = ...

_G.RothDevLib = _G.RothDevLib or {}
local RDL = _G.RothDevLib

RDL.name = "RothDevLib"
RDL.addonName = ADDON  -- "!RothDevLib"
RDL.version = "1.0.0-alpha.19.0"
RDL._initialized = false

-- Module slots (populated by other files)
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

-- API fingerprints (guard against accidental override by internal modules)
-- NOTE: These are assigned after the methods are defined further below.
RDL._apiFingerprint = RDL._apiFingerprint or {}

-- Timer baseline fingerprint (used to detect invasive timer hooks by any addon).
RDL._timerFingerprint = RDL._timerFingerprint or {}

function RDL:Log(level, tag, msg, data)
  if self.Logger and self.Logger.Log then
    self.Logger:Log(level, tag, msg, data)
  end
end

-- SafeCall: xpcall wrapper that captures suppressed errors WITH locals.
-- Doctor context correlation is included.
function RDL:SafeCall(addonName, funcName, fn, ...)
  if type(fn) ~= "function" then return end
  if self.Doctor and self.Doctor.Enter then
    self.Doctor:Enter(addonName, funcName, { note = "SafeCall" })
  end

  local function ErrHandler(err)
    local stack = debugstack(2, 40, 40)
    local locals, lmeta = nil, nil

    if self.Locals and self.Locals.CaptureBest then
      local ok2, l, m = pcall(function()
        return self.Locals:CaptureBest({ addon = addonName, stack = stack, baseLevel = 2 })
      end)
      if ok2 then locals, lmeta = l, m end
    else
      local lok, lval = pcall(debuglocals, 2)
      if lok and lval and self.Util and self.Util.FilterLocals then
        local settings = self.DB and self.DB.GetSettings and self.DB:GetSettings() or nil
        locals = self.Util:FilterLocals(lval, (settings and settings.maxLocalsSize) or 8192)
      end
    end

    if self.Capture and self.Capture.OnSuppressedError then
      self.Capture:OnSuppressedError(err, stack, locals, addonName, funcName, { localsProbe = lmeta })
    end
    return err
  end

  local cpu = self.CPU
  local ok, r1, r2, r3, r4, r5
  if cpu and cpu.Measure then
    ok, r1, r2, r3, r4, r5 = cpu:Measure(addonName, funcName, function(...)
      return xpcall(fn, ErrHandler, ...)
    end, nil, ...)
  else
    ok, r1, r2, r3, r4, r5 = xpcall(fn, ErrHandler, ...)
  end

  if self.Doctor and self.Doctor.Leave then
    self.Doctor:Leave()
  end

  if ok then
    return r1, r2, r3, r4, r5
  end
  return nil
end
-- SafeCallCtx: like SafeCall, but lets the caller provide Doctor context for this invocation.
-- This is the safest way to attach dynamic context without manual Enter/Leave bookkeeping.
function RDL:SafeCallCtx(addonName, funcName, ctx, fn, ...)
  if type(fn) ~= "function" then return end

  if self.Doctor and self.Doctor.Enter then
    self.Doctor:Enter(addonName, funcName, ctx)
  end

  local function ErrHandler(err)
    local stack = debugstack(2, 40, 40)
    local locals, lmeta = nil, nil

    if self.Locals and self.Locals.CaptureBest then
      local ok2, l, m = pcall(function()
        return self.Locals:CaptureBest({ addon = addonName, stack = stack, baseLevel = 2 })
      end)
      if ok2 then locals, lmeta = l, m end
    else
      local lok, lval = pcall(debuglocals, 2)
      if lok and lval and self.Util and self.Util.FilterLocals then
        local settings = self.DB and self.DB.GetSettings and self.DB:GetSettings() or nil
        locals = self.Util:FilterLocals(lval, (settings and settings.maxLocalsSize) or 8192)
      end
    end

    if self.Capture and self.Capture.OnSuppressedError then
      self.Capture:OnSuppressedError(err, stack, locals, addonName, funcName, { localsProbe = lmeta })
    end
    return err
  end

  local cpu = self.CPU
  local ok, r1, r2, r3, r4, r5
  if cpu and cpu.Measure then
    ok, r1, r2, r3, r4, r5 = cpu:Measure(addonName, funcName, function(...)
      return xpcall(fn, ErrHandler, ...)
    end, nil, ...)
  else
    ok, r1, r2, r3, r4, r5 = xpcall(fn, ErrHandler, ...)
  end

  if self.Doctor and self.Doctor.Leave then
    self.Doctor:Leave()
  end

  if ok then
    return r1, r2, r3, r4, r5
  end
  return nil
end



-- WrapUnsafe: keeps hard errors hard, but adds Doctor context for correlation.
function RDL:WrapUnsafe(addonName, funcName, fn, ctxFn)
  return function(...)
    if self.Doctor and self.Doctor.Enter then
      local ctx = nil
      if type(ctxFn) == "function" then
        local ok2, c = pcall(ctxFn, ...)
        if ok2 then ctx = c end
      end
      self.Doctor:Enter(addonName, funcName, ctx)
    end

    local r1, r2, r3, r4, r5 = fn(...)

    if self.Doctor and self.Doctor.Leave then
      self.Doctor:Leave()
    end
    return r1, r2, r3, r4, r5
  end
end

-- WrapSafe: converts hard errors into suppressed entries WITH locals.
function RDL:WrapSafe(addonName, funcName, fn, staticCtx)
  return function(...)
    if self.Doctor and self.Doctor.Enter then
      self.Doctor:Enter(addonName, funcName, staticCtx)
    end

    local function ErrHandler(err)
      local stack = debugstack(2, 40, 40)
      local locals, lmeta = nil, nil

      if self.Locals and self.Locals.CaptureBest then
        local ok2, l, m = pcall(function()
          return self.Locals:CaptureBest({ addon = addonName, stack = stack, baseLevel = 2 })
        end)
        if ok2 then locals, lmeta = l, m end
      else
        local lok, lval = pcall(debuglocals, 2)
        if lok and lval and self.Util and self.Util.FilterLocals then
          local settings = self.DB and self.DB.GetSettings and self.DB:GetSettings() or nil
          locals = self.Util:FilterLocals(lval, (settings and settings.maxLocalsSize) or 8192)
        end
      end

      if self.Capture and self.Capture.OnSuppressedError then
        self.Capture:OnSuppressedError(err, stack, locals, addonName, funcName, { localsProbe = lmeta })
      end
      return err
    end

    local cpu = self.CPU
    local ok, r1, r2, r3, r4, r5
    if cpu and cpu.Measure then
      ok, r1, r2, r3, r4, r5 = cpu:Measure(addonName, funcName, function(...)
        return xpcall(fn, ErrHandler, ...)
      end, nil, ...)
    else
      ok, r1, r2, r3, r4, r5 = xpcall(fn, ErrHandler, ...)
    end

    if self.Doctor and self.Doctor.Leave then
      self.Doctor:Leave()
    end

    if ok then
      return r1, r2, r3, r4, r5
    end
    return nil
  end
end


-- WrapSafeCtx: like WrapSafe, but computes Doctor context per call.
-- ctxFn receives the same arguments as the wrapped function.
function RDL:WrapSafeCtx(addonName, funcName, fn, ctxFn)
  return function(...)
    if self.Doctor and self.Doctor.Enter then
      local ctx = nil
      if type(ctxFn) == "function" then
        local ok2, c = pcall(ctxFn, ...)
        if ok2 then ctx = c end
      end
      self.Doctor:Enter(addonName, funcName, ctx)
    end

    local function ErrHandler(err)
      local stack = debugstack(2, 40, 40)
      local locals, lmeta = nil, nil

      if self.Locals and self.Locals.CaptureBest then
        local ok2, l, m = pcall(function()
          return self.Locals:CaptureBest({ addon = addonName, stack = stack, baseLevel = 2 })
        end)
        if ok2 then locals, lmeta = l, m end
      else
        local lok, lval = pcall(debuglocals, 2)
        if lok and lval and self.Util and self.Util.FilterLocals then
          local settings = self.DB and self.DB.GetSettings and self.DB:GetSettings() or nil
          locals = self.Util:FilterLocals(lval, (settings and settings.maxLocalsSize) or 8192)
        end
      end

      if self.Capture and self.Capture.OnSuppressedError then
        self.Capture:OnSuppressedError(err, stack, locals, addonName, funcName, { localsProbe = lmeta })
      end
      return err
    end

    local cpu = self.CPU
    local ok, r1, r2, r3, r4, r5
    if cpu and cpu.Measure then
      ok, r1, r2, r3, r4, r5 = cpu:Measure(addonName, funcName, function(...)
        return xpcall(fn, ErrHandler, ...)
      end, nil, ...)
    else
      ok, r1, r2, r3, r4, r5 = xpcall(fn, ErrHandler, ...)
    end

    if self.Doctor and self.Doctor.Leave then
      self.Doctor:Leave()
    end

    if ok then
      return r1, r2, r3, r4, r5
    end
    return nil
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

-- Capture baseline references for later comparison.
function RDL:_InitFingerprints()
  if self._apiFingerprint and self._apiFingerprint._init then return end
  self._apiFingerprint = self._apiFingerprint or {}
  self._apiFingerprint._init = true

  -- Public API methods that must not be overwritten by internal modules.
  self._apiFingerprint.SafeCall = self.SafeCall
  self._apiFingerprint.SafeCallCtx = self.SafeCallCtx
  self._apiFingerprint.WrapSafe = self.WrapSafe
  self._apiFingerprint.WrapSafeCtx = self.WrapSafeCtx
  self._apiFingerprint.WrapUnsafe = self.WrapUnsafe

  -- Timer baselines (used to detect invasive C_Timer monkey-patching by any addon).
  self._timerFingerprint = self._timerFingerprint or {}
  local CT = _G.C_Timer
  self._timerFingerprint.atLoad = time()
  self._timerFingerprint.After = CT and CT.After or nil
  self._timerFingerprint.NewTicker = CT and CT.NewTicker or nil
  self._timerFingerprint.NewTimer = CT and CT.NewTimer or nil
  self._timerFingerprint.AfterInfo = FnInfo(CT and CT.After)
  self._timerFingerprint.NewTickerInfo = FnInfo(CT and CT.NewTicker)
  self._timerFingerprint.NewTimerInfo = FnInfo(CT and CT.NewTimer)
end

local function EmitAlert(code, message, data)
  -- Prefer storing as an ALERT entry so it shows up in UI/exports.
  if RDL and RDL.Capture and RDL.Capture.OnIntegrationEvent then
    pcall(RDL.Capture.OnIntegrationEvent, RDL.Capture, "ALERT", RDL.addonName or "RothDevLib", code, message, data, "WARN")
    return
  end
  if RDL and RDL.Log then
    RDL:Log("WARN", "ALERT", tostring(message), { code = code, data = data })
  end
end

-- Run lightweight invariants. Call after Capture.EarlyInit so ALERT can be stored.
function RDL:SelfCheckEarly(stage)
  self:_InitFingerprints()
  stage = tostring(stage or "early")

  -- API override detection
  local api = self._apiFingerprint or {}
  local function CheckAPI(name)
    if api[name] and self[name] ~= api[name] then
      EmitAlert("API_OVERRIDDEN", "Public API method was overwritten: " .. name, {
        stage = stage,
        expected = tostring(FnInfo(api[name]) and FnInfo(api[name]).short_src or "?"),
        actual = tostring(FnInfo(self[name]) and FnInfo(self[name]).short_src or "?"),
      })
    end
  end
  CheckAPI("SafeCall")
  CheckAPI("SafeCallCtx")
  CheckAPI("WrapSafe")
  CheckAPI("WrapSafeCtx")
  CheckAPI("WrapUnsafe")

  -- Timer monkey-patch detection
  local CT = _G.C_Timer
  local tf = self._timerFingerprint or {}
  if CT and type(CT) == "table" then
    if tf.After and CT.After ~= tf.After then
      EmitAlert("C_TIMER_AFTER_HOOKED", "C_Timer.After was replaced after load (taint risk)", {
        stage = stage,
        baseline = tf.AfterInfo,
        now = FnInfo(CT.After),
      })
    end
    if tf.NewTicker and CT.NewTicker ~= tf.NewTicker then
      EmitAlert("C_TIMER_NEWTICKER_HOOKED", "C_Timer.NewTicker was replaced after load (taint risk)", {
        stage = stage,
        baseline = tf.NewTickerInfo,
        now = FnInfo(CT.NewTicker),
      })
    end
    if tf.NewTimer and CT.NewTimer ~= tf.NewTimer then
      EmitAlert("C_TIMER_NEWTIMER_HOOKED", "C_Timer.NewTimer was replaced after load (taint risk)", {
        stage = stage,
        baseline = tf.NewTimerInfo,
        now = FnInfo(CT.NewTimer),
      })
    end

    -- Heuristic: Blizzard timer functions are typically C-side; warn if they look Lua.
    local ai = FnInfo(CT.After)
    if ai and ai.what == "Lua" then
      EmitAlert("C_TIMER_AFTER_LUA", "C_Timer.After appears to be a Lua function (likely hooked)", {
        stage = stage,
        now = ai,
      })
    end
  end
end


-- Initialize fingerprints at file load.
RDL:_InitFingerprints()
