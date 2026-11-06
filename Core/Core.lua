-- !RothDevLib/Core/Core.lua
-- Namespace bootstrap and lightweight integrity checks.
-- Public call wrappers live in Core/CallSafety.lua after the ordinary-value
-- boundary has loaded; do not duplicate them here.

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

-- Minimal pre-CallSafety logger. Core/CallSafety.lua replaces this with the
-- bounded implementation once Util/SecretGuard are available.
function RDL:Log(level, tag, message, data)
  local logger = self.Logger
  if logger and type(logger.Log) == "function" then
    return pcall(logger.Log, logger, level, tag, message, data)
  end
  return false
end

local function FnInfo(fn)
  if type(fn) ~= "function" then return nil end
  local debugTable = _G.debug
  local getInfo = type(debugTable) == "table" and debugTable.getinfo or nil
  if type(getInfo) ~= "function" then return nil end

  local ok, info = pcall(getInfo, fn, "S")
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
  -- These are nil during bootstrap. Core/CallSafety.lua installs the final
  -- implementations and updates the same fingerprint fields.
  self._apiFingerprint.SafeCall = self.SafeCall
  self._apiFingerprint.SafeCallCtx = self.SafeCallCtx
  self._apiFingerprint.WrapSafe = self.WrapSafe
  self._apiFingerprint.WrapSafeCtx = self.WrapSafeCtx
  self._apiFingerprint.WrapUnsafe = self.WrapUnsafe

  local timers = _G.C_Timer
  self._timerFingerprint = self._timerFingerprint or {}
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
    pcall(RDL.Capture.OnIntegrationEvent, RDL.Capture, "ALERT",
      RDL.addonName or "RothDevLib", code, message, data, "WARN")
    return
  end
  RDL:Log("WARN", "ALERT", message, { code = code, data = data })
end

function RDL:SelfCheckEarly(stage)
  self:_InitFingerprints()
  if type(stage) ~= "string" or stage == "" then stage = "early" end

  local api = self._apiFingerprint or {}
  local function CheckAPI(name)
    local expected = api[name]
    if expected and self[name] ~= expected then
      local expectedInfo = FnInfo(expected)
      local actualInfo = FnInfo(self[name])
      EmitAlert("API_OVERRIDDEN", "Public API method was overwritten: " .. name, {
        stage = stage,
        expected = expectedInfo and expectedInfo.short_src or "?",
        actual = actualInfo and actualInfo.short_src or "?",
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
  if type(timers) ~= "table" then return end

  if baseline.After and timers.After ~= baseline.After then
    EmitAlert("C_TIMER_AFTER_HOOKED", "C_Timer.After was replaced after load", {
      stage = stage,
      baseline = baseline.AfterInfo,
      now = FnInfo(timers.After),
    })
  end
  if baseline.NewTicker and timers.NewTicker ~= baseline.NewTicker then
    EmitAlert("C_TIMER_NEWTICKER_HOOKED", "C_Timer.NewTicker was replaced after load", {
      stage = stage,
      baseline = baseline.NewTickerInfo,
      now = FnInfo(timers.NewTicker),
    })
  end
  if baseline.NewTimer and timers.NewTimer ~= baseline.NewTimer then
    EmitAlert("C_TIMER_NEWTIMER_HOOKED", "C_Timer.NewTimer was replaced after load", {
      stage = stage,
      baseline = baseline.NewTimerInfo,
      now = FnInfo(timers.NewTimer),
    })
  end
end

RDL:_InitFingerprints()
