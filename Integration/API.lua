-- !RothDevLib/Integration/API.lua
-- Public integration API. External diagnostics cross one bounded ordinary-value
-- boundary before they reach storage, callbacks or the UI.

local RDL = _G.RothDevLib
if not RDL then return end

local function Util()
  return RDL.Util
end

local function Guard()
  return RDL.SecretGuard
end

local function SafeText(value, fallback, maxBytes)
  local U = Util()
  local ordinary = value
  if U and U.Scrub then
    local ok, scrubbed = pcall(U.Scrub, U, value)
    if ok then ordinary = scrubbed else ordinary = "<unavailable>" end
  else
    local SG = Guard()
    if SG and SG.CanAccess and not SG:CanAccess(value) then ordinary = "<inaccessible>" end
  end

  local text = fallback or "<?>"
  if ordinary ~= nil and U and U.SafeToString then
    local ok, result = pcall(U.SafeToString, U, ordinary)
    if ok then text = result end
  elseif ordinary ~= nil and type(ordinary) == "string" then
    text = ordinary
  end

  if U and U.FilterSecretEscapes then
    local ok, result = pcall(U.FilterSecretEscapes, U, text)
    if ok then text = result end
  end
  if type(text) ~= "string" then text = fallback or "<?>" end

  maxBytes = tonumber(maxBytes) or 1024
  if #text > maxBytes then text = text:sub(1, maxBytes) .. "<truncated>" end
  return text
end
local function SafeAddonName(value)
  local name = SafeText(value, "", 128)
  if name == "" or name == "<inaccessible>" or name == "<secret>" then return nil end
  return name
end

local function SafePayload(value, opts)
  local U = Util()
  if U and U.CopyDiagnosticValue then
    local ok, copied = pcall(U.CopyDiagnosticValue, U, value, opts or {
      maxDepth = 4,
      maxEntries = 80,
      maxStringBytes = 4096,
    })
    if ok then return copied end
  end
  return SafeText(value, "<unavailable>", 4096)
end

local function SafeOptions(value)
  local copied = SafePayload(value, {
    maxDepth = 3,
    maxEntries = 50,
    maxStringBytes = 4096,
  })
  return type(copied) == "table" and copied or {}
end

local function Callable(fn)
  local SG = Guard()
  if SG and SG.CanAccess and not SG:CanAccess(fn) then return false end
  return type(fn) == "function"
end

local function OrdinaryCondition(value)
  local SG = Guard()
  if SG then
    if SG.CanAccess and not SG:CanAccess(value) then return false end
    if SG.IsSecret and SG:IsSecret(value) then return false end
  end
  return value and true or false
end


local function SinkCall(label, fn, owner, ...)
  if type(fn) ~= "function" then return false, nil end
  local ok, r1, r2, r3 = pcall(fn, owner, ...)
  if not ok and RDL.Log then
    pcall(RDL.Log, RDL, "ERROR", "INTEGRATION", label .. " failed", { error = SafeText(r1, "<error>", 2048) })
  end
  return ok, r1, r2, r3
end

-- Bus wrappers ------------------------------------------------------------

function RDL:InitAddon(addonName, opts)
  local name = SafeAddonName(addonName)
  if not name then return nil end
  if self.Bus and self.Bus.RegisterAddon then
    local ok, result = SinkCall("Bus:RegisterAddon", self.Bus.RegisterAddon, self.Bus, name, SafeOptions(opts))
    if ok then return result end
  end
  return nil
end

function RDL:Breadcrumb(addonName, category, message, data)
  local name = SafeAddonName(addonName)
  if not name then return end
  if self.Bus and self.Bus.Breadcrumb then
    SinkCall(
      "Bus:Breadcrumb",
      self.Bus.Breadcrumb,
      self.Bus,
      name,
      SafeText(category, "event", 128),
      SafeText(message, "", 4096),
      SafePayload(data)
    )
  end
end

function RDL:Metric(addonName, name, value, unit, opts)
  local addon = SafeAddonName(addonName)
  if not addon then return end
  if self.Bus and self.Bus.Metric then
    SinkCall(
      "Bus:Metric",
      self.Bus.Metric,
      self.Bus,
      addon,
      SafeText(name, "metric", 256),
      SafePayload(value, { maxDepth = 2, maxEntries = 20, maxStringBytes = 1024 }),
      SafeText(unit, "", 64),
      SafeOptions(opts)
    )
  end
end

-- Profiling helpers -------------------------------------------------------

function RDL:Profile(addonName, funcName, fn, opts, ...)
  if not Callable(fn) then return nil end
  local addon = SafeAddonName(addonName) or "<?>"
  local label = SafeText(funcName, "<?>", 256)
  if self.CPU and self.CPU.Measure then
    return self.CPU:Measure(addon, label, fn, SafeOptions(opts), ...)
  end
  return fn(...)
end

function RDL:WrapProfiled(addonName, funcName, fn, opts)
  if not Callable(fn) then return nil end
  local addon = SafeAddonName(addonName) or "<?>"
  local label = SafeText(funcName, "<?>", 256)
  if self.CPU and self.CPU.Wrap then
    return self.CPU:Wrap(addon, label, fn, SafeOptions(opts))
  end
  return fn
end

function RDL:MemDelta(addonName, funcName, fn, opts, ...)
  if not Callable(fn) then return nil end
  local addon = SafeAddonName(addonName) or "<?>"
  local label = SafeText(funcName, "<?>", 256)
  if self.Mem and self.Mem.Measure then
    return self.Mem:Measure(addon, label, fn, SafeOptions(opts), ...)
  end
  return fn(...)
end

function RDL:WrapMemDelta(addonName, funcName, fn, opts)
  if not Callable(fn) then return nil end
  local addon = SafeAddonName(addonName) or "<?>"
  local label = SafeText(funcName, "<?>", 256)
  if self.Mem and self.Mem.Wrap then
    return self.Mem:Wrap(addon, label, fn, SafeOptions(opts))
  end
  return fn
end

function RDL:MemSample(addonName, tag, opts)
  local addon = SafeAddonName(addonName)
  if not addon then return end
  if self.Mem and self.Mem.Sample then
    local ok, result = SinkCall("Mem:Sample", self.Mem.Sample, self.Mem, addon, SafeText(tag, "sample", 256), SafeOptions(opts))
    if ok then return result end
  end
end

-- Structured alerts/assertions ------------------------------------------

function RDL:Alert(addonName, code, message, data, level)
  local addon = SafeAddonName(addonName) or "<?>"
  local safeCode = SafeText(code, "ALERT", 256)
  local safeMessage = SafeText(message, "", 8192)
  local safeLevel = SafeText(level, "WARN", 32)
  local safeData = SafePayload(data)

  if self.Bus and self.Bus.Alert then
    SinkCall("Bus:Alert", self.Bus.Alert, self.Bus, addon, safeCode, safeMessage, safeData, safeLevel)
  end
  if self.Capture and self.Capture.OnIntegrationEvent then
    SinkCall("Capture:OnIntegrationEvent", self.Capture.OnIntegrationEvent, self.Capture,
      "ALERT", addon, safeCode, safeMessage, safeData, safeLevel)
  end
  SinkCall("RDL:Fire", self.Fire, self, "RDL_INTEGRATION", "ALERT", {
    addon = addon,
    code = safeCode,
    message = safeMessage,
    level = safeLevel,
  })
end

function RDL:Assert(addonName, condition, code, message, data)
  if OrdinaryCondition(condition) then return true end

  local addon = SafeAddonName(addonName) or "<?>"
  local safeCode = SafeText(code, "ASSERT", 256)
  local safeMessage = SafeText(message, "assert failed", 8192)
  local safeData = SafePayload(data)
  local fullMessage = safeCode .. ": " .. safeMessage

  if self.Capture and self.Capture.OnIntegrationEvent then
    SinkCall("Capture:OnIntegrationEvent", self.Capture.OnIntegrationEvent, self.Capture,
      "ASSERT", addon, safeCode, safeMessage, safeData, "ERROR")
  else
    self:Breadcrumb(addon, "assert", safeCode, { message = fullMessage, data = safeData })
  end

  SinkCall("RDL:Fire", self.Fire, self, "RDL_INTEGRATION", "ASSERT", {
    addon = addon,
    code = safeCode,
    message = fullMessage,
  })
  return false
end

-- Explicit reports -------------------------------------------------------

function RDL:Report(addonName, kind, message, opts)
  local addon = SafeAddonName(addonName) or "<?>"
  local safeKind = SafeText(kind, "SUPPRESSED", 64)
  local safeMessage = SafeText(message, "", 8192)
  local safeOpts = SafeOptions(opts)

  if self.Capture and self.Capture.OnReported then
    SinkCall("Capture:OnReported", self.Capture.OnReported, self.Capture,
      safeKind, addon, safeMessage, safeOpts)
  elseif self.Capture and self.Capture.OnIntegrationEvent then
    SinkCall("Capture:OnIntegrationEvent", self.Capture.OnIntegrationEvent, self.Capture,
      safeKind, addon, safeOpts.code, safeMessage, safeOpts.data, safeOpts.level)
  end

  SinkCall("RDL:Fire", self.Fire, self, "RDL_INTEGRATION", "REPORT", {
    addon = addon,
    kind = safeKind,
    message = safeMessage,
  })
end

function RDL:ReportError(addonName, message, opts)
  return self:Report(addonName, "LUA_ERROR", message, opts)
end

function RDL:ReportWarning(addonName, message, opts)
  return self:Report(addonName, "LUA_WARNING", message, opts)
end

function RDL:ReportTaint(addonName, message, opts)
  local safeOpts = SafeOptions(opts)
  local kind = SafeText(safeOpts.kind, "TAINT_BLOCKED", 64)
  return self:Report(addonName, kind, message, safeOpts)
end

function RDL:ReportSuppressed(addonName, message, opts)
  return self:Report(addonName, "SUPPRESSED", message, opts)
end

-- Doctor helpers ---------------------------------------------------------

function RDL:Enter(addonName, funcName, ctx)
  local addon = SafeAddonName(addonName) or "<?>"
  if self.Doctor and self.Doctor.Enter then
    local ok, result = SinkCall("Doctor:Enter", self.Doctor.Enter, self.Doctor,
      addon, SafeText(funcName, "<?>", 256), SafePayload(ctx))
    if ok then return result end
  end
  return nil
end

function RDL:Leave()
  if self.Doctor and self.Doctor.Leave then
    SinkCall("Doctor:Leave", self.Doctor.Leave, self.Doctor)
  end
end

-- Per-addon client -------------------------------------------------------

function RDL:NewAddon(addonName, opts)
  local addon = SafeAddonName(addonName)
  if not addon then return nil end
  self:InitAddon(addon, opts)

  local client = { addon = addon }

  function client:Breadcrumb(category, message, data)
    return RDL:Breadcrumb(addon, category, message, data)
  end
  function client:Metric(name, value, unit, metricOpts)
    return RDL:Metric(addon, name, value, unit, metricOpts)
  end
  function client:Profile(funcName, fn, profileOpts, ...)
    return RDL:Profile(addon, funcName, fn, profileOpts, ...)
  end
  function client:WrapProfiled(funcName, fn, profileOpts)
    return RDL:WrapProfiled(addon, funcName, fn, profileOpts)
  end
  function client:MemDelta(funcName, fn, memOpts, ...)
    return RDL:MemDelta(addon, funcName, fn, memOpts, ...)
  end
  function client:WrapMemDelta(funcName, fn, memOpts)
    return RDL:WrapMemDelta(addon, funcName, fn, memOpts)
  end
  function client:MemSample(tag, sampleOpts)
    return RDL:MemSample(addon, tag, sampleOpts)
  end
  function client:Alert(code, message, data, level)
    return RDL:Alert(addon, code, message, data, level)
  end
  function client:Assert(condition, code, message, data)
    return RDL:Assert(addon, condition, code, message, data)
  end
  function client:Report(kind, message, reportOpts)
    return RDL:Report(addon, kind, message, reportOpts)
  end
  function client:Error(message, reportOpts)
    return RDL:ReportError(addon, message, reportOpts)
  end
  function client:Warning(message, reportOpts)
    return RDL:ReportWarning(addon, message, reportOpts)
  end
  function client:Taint(message, reportOpts)
    return RDL:ReportTaint(addon, message, reportOpts)
  end
  function client:Suppressed(message, reportOpts)
    return RDL:ReportSuppressed(addon, message, reportOpts)
  end
  function client:SafeCall(funcName, fn, ...)
    return RDL:SafeCall(addon, funcName, fn, ...)
  end
  function client:SafeCallCtx(funcName, ctx, fn, ...)
    return RDL:SafeCallCtx(addon, funcName, ctx, fn, ...)
  end
  function client:WrapSafe(funcName, fn, staticCtx)
    return RDL:WrapSafe(addon, funcName, fn, staticCtx)
  end
  function client:WrapSafeCtx(funcName, fn, ctxFn)
    return RDL:WrapSafeCtx(addon, funcName, fn, ctxFn)
  end
  function client:WrapUnsafe(funcName, fn, ctxFn)
    return RDL:WrapUnsafe(addon, funcName, fn, ctxFn)
  end
  function client:Enter(funcName, ctx)
    return RDL:Enter(addon, funcName, ctx)
  end
  function client:Leave()
    return RDL:Leave()
  end
  function client:Log(level, category, message, data)
    local normalizedLevel = SafeText(level, "INFO", 32):upper()
    if normalizedLevel == "ERROR" or normalizedLevel == "CRITICAL" then
      return RDL:ReportError(addon, message, { data = SafePayload(data), level = normalizedLevel, source = category })
    end
    if normalizedLevel == "WARN" or normalizedLevel == "WARNING" then
      return RDL:ReportWarning(addon, message, { data = SafePayload(data), level = normalizedLevel, source = category })
    end
    return RDL:Breadcrumb(addon, SafeText(category, "log", 128), message, data)
  end

  return client
end
