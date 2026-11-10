-- !RothDevLib/Core/CallSafety.lua
-- Public call wrappers loaded after the ordinary-value boundary is available.

local RDL = _G.RothDevLib
if not RDL then return end

local Unpack = table.unpack or unpack

local function Pack(...)
  return { n = select("#", ...), ... }
end

local function CanAccess(value)
  local guard = RDL.SecretGuard
  if guard and type(guard.CanAccess) == "function" then
    local ok, accessible = pcall(guard.CanAccess, guard, value)
    if not ok or accessible ~= true then return false end
  elseif type(_G.canaccessvalue) == "function" then
    local ok, accessible = pcall(_G.canaccessvalue, value)
    if not ok or accessible ~= true then return false end
  end

  if guard and type(guard.IsSecret) == "function" then
    local ok, secret = pcall(guard.IsSecret, guard, value)
    if not ok or secret == true then return false end
  elseif type(_G.issecretvalue) == "function" then
    local ok, secret = pcall(_G.issecretvalue, value)
    if not ok or secret == true then return false end
  end
  return true
end

local function IsCallable(value)
  return CanAccess(value) and type(value) == "function"
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
      maxNodes = 500,
      maxStringBytes = 4096,
      maxTotalBytes = 64 * 1024,
    })
    if ok then return copy end
  end

  local valueType = type(value)
  if valueType == "string" then return SafeText(value, "", 4096) end
  if valueType == "number" or valueType == "boolean" then return value end
  return "<" .. valueType .. ">"
end

local function SafeDebugStack(level)
  if type(_G.debugstack) ~= "function" then return "" end
  local ok, stack = pcall(_G.debugstack, level or 2, 40, 40)
  if not ok or type(stack) ~= "string" then return "" end

  local util = RDL.Util
  if util and type(util.FilterSecretEscapes) == "function" then
    local okFilter, filtered = pcall(util.FilterSecretEscapes, util, stack)
    if okFilter and type(filtered) == "string" then return filtered end
  end
  return stack
end

local function EnterDoctor(addonName, funcName, context)
  local doctor = RDL.Doctor
  if not (doctor and type(doctor.Enter) == "function") then return nil end
  local ok, token = pcall(doctor.Enter, doctor, addonName, funcName, SafeContext(context))
  if ok then return token end
  return nil
end

local function LeaveDoctor(token)
  if token == nil then return end
  local doctor = RDL.Doctor
  if doctor and type(doctor.Leave) == "function" then
    pcall(doctor.Leave, doctor, token)
  end
end

local function ArmDoctorCleanup(token)
  if token == nil then return end
  local timers = _G.C_Timer
  if type(timers) ~= "table" or type(timers.After) ~= "function" then return end
  pcall(timers.After, 0, function() LeaveDoctor(token) end)
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
    if ok and RDL.Util and type(RDL.Util.FilterLocals) == "function" then
      local okFilter, filtered = pcall(RDL.Util.FilterLocals, RDL.Util, captured, 8192)
      if okFilter then locals = filtered end
    end
  end
  return locals, meta
end

local function ReportSuppressed(err, stack, locals, addonName, funcName, meta)
  local capture = RDL.Capture
  if capture and type(capture.OnSuppressedError) == "function" then
    pcall(capture.OnSuppressedError, capture, SafeText(err, "<error>", 4096), stack, locals,
      addonName, funcName, { localsProbe = SafeContext(meta) })
  end
end

local function NormalizeIdentity(addonName, funcName)
  return SafeText(addonName, "<?>" , 128), SafeText(funcName, "<?>" , 256)
end

local function RunProtected(addonName, funcName, context, fn, ...)
  if not IsCallable(fn) then return nil end
  addonName, funcName = NormalizeIdentity(addonName, funcName)
  local doctorToken = EnterDoctor(addonName, funcName, context)
  local args = Pack(...)

  local function ErrorHandler(err)
    local stack = SafeDebugStack(3)
    local locals, meta = CaptureLocals(addonName, stack)
    local safeError = SafeText(err, "<error>", 4096)
    ReportSuppressed(safeError, stack, locals, addonName, funcName, meta)
    return safeError
  end

  -- Do not depend on non-standard xpcall vararg forwarding. The explicit
  -- packed closure preserves nil arguments on every Lua runtime WoW may embed.
  local function InvokeTarget()
    return fn(Unpack(args, 1, args.n))
  end

  local result = Pack(pcall(function()
    local cpu = RDL.CPU
    if cpu and type(cpu.Measure) == "function" then
      return cpu:Measure(addonName, funcName, function()
        return xpcall(InvokeTarget, ErrorHandler)
      end, nil)
    end
    return xpcall(InvokeTarget, ErrorHandler)
  end))

  LeaveDoctor(doctorToken)
  if not result[1] then
    if type(RDL.Log) == "function" then
      pcall(RDL.Log, RDL, "ERROR", "CORE", "Protected-call infrastructure failed", {
        addon = addonName,
        func = funcName,
        error = SafeText(result[2], "<error>", 2048),
      })
    end
    return nil
  end
  if result[2] then return Unpack(result, 3, result.n) end
  return nil
end

function RDL:Log(level, tag, message, data)
  local logger = self.Logger
  if not (logger and type(logger.Log) == "function") then return false end
  return pcall(logger.Log, logger,
    SafeText(level, "INFO", 32),
    SafeText(tag, "LOG", 64),
    SafeText(message, "", 4096),
    SafeContext(data))
end

function RDL:SafeCall(addonName, funcName, fn, ...)
  return RunProtected(addonName, funcName, { note = "SafeCall" }, fn, ...)
end

function RDL:SafeCallCtx(addonName, funcName, context, fn, ...)
  return RunProtected(addonName, funcName, context, fn, ...)
end

function RDL:WrapUnsafe(addonName, funcName, fn, contextFn)
  if not IsCallable(fn) then return nil end
  addonName, funcName = NormalizeIdentity(addonName, funcName)
  if not IsCallable(contextFn) then contextFn = nil end

  return function(...)
    local context
    if contextFn then
      local ok, value = pcall(contextFn, ...)
      if ok then context = value end
    end

    local doctorToken = EnterDoctor(addonName, funcName, context)
    ArmDoctorCleanup(doctorToken)
    local result = Pack(fn(...))
    LeaveDoctor(doctorToken)
    return Unpack(result, 1, result.n)
  end
end

function RDL:WrapSafe(addonName, funcName, fn, staticContext)
  if not IsCallable(fn) then return nil end
  addonName, funcName = NormalizeIdentity(addonName, funcName)
  local context = SafeContext(staticContext)
  return function(...)
    return RunProtected(addonName, funcName, context, fn, ...)
  end
end

function RDL:WrapSafeCtx(addonName, funcName, fn, contextFn)
  if not IsCallable(fn) then return nil end
  addonName, funcName = NormalizeIdentity(addonName, funcName)
  if not IsCallable(contextFn) then contextFn = nil end

  return function(...)
    local context
    if contextFn then
      local ok, value = pcall(contextFn, ...)
      if ok then context = value end
    end
    return RunProtected(addonName, funcName, context, fn, ...)
  end
end

-- Core.lua initialized its fingerprints before utilities existed. Point the
-- existing self-check at the final public implementations.
RDL._apiFingerprint = RDL._apiFingerprint or {}
RDL._apiFingerprint.SafeCall = RDL.SafeCall
RDL._apiFingerprint.SafeCallCtx = RDL.SafeCallCtx
RDL._apiFingerprint.WrapSafe = RDL.WrapSafe
RDL._apiFingerprint.WrapSafeCtx = RDL.WrapSafeCtx
RDL._apiFingerprint.WrapUnsafe = RDL.WrapUnsafe
