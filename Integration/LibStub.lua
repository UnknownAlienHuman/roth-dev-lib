-- !RothDevLib/Integration/LibStub.lua
-- Optional LibStub facade over the authoritative _G.RothDevLib singleton.

local core = _G.RothDevLib
if not core then return end

local LibStub = _G.LibStub
if type(LibStub) ~= "table" or type(LibStub.NewLibrary) ~= "function" then return end

local MAJOR, MINOR = "RothDevLib-1.0", 3
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
  lib = LibStub(MAJOR, true)
  if not lib then return end
end

lib.MAJOR = MAJOR
lib.MINOR = MINOR
lib._core = core

function lib:GetCore()
  return _G.RothDevLib or self._core
end

local function Proxy(method)
  return function(self, ...)
    local current = _G.RothDevLib or self._core
    if not current then return nil end
    local fn = current[method]
    if type(fn) ~= "function" then return nil end
    return fn(current, ...)
  end
end

-- Core wrappers
lib.Log = Proxy("Log")
lib.SafeCall = Proxy("SafeCall")
lib.SafeCallCtx = Proxy("SafeCallCtx")
lib.WrapSafe = Proxy("WrapSafe")
lib.WrapSafeCtx = Proxy("WrapSafeCtx")
lib.WrapUnsafe = Proxy("WrapUnsafe")

-- Profiling
lib.Profile = Proxy("Profile")
lib.WrapProfiled = Proxy("WrapProfiled")
lib.MemDelta = Proxy("MemDelta")
lib.WrapMemDelta = Proxy("WrapMemDelta")
lib.MemSample = Proxy("MemSample")

-- Integration bus
lib.InitAddon = Proxy("InitAddon")
lib.Breadcrumb = Proxy("Breadcrumb")
lib.Metric = Proxy("Metric")
lib.Alert = Proxy("Alert")
lib.Assert = Proxy("Assert")
lib.Enter = Proxy("Enter")
lib.Leave = Proxy("Leave")
lib.NewAddon = Proxy("NewAddon")

-- Explicit report intake
lib.Report = Proxy("Report")
lib.ReportError = Proxy("ReportError")
lib.ReportWarning = Proxy("ReportWarning")
lib.ReportTaint = Proxy("ReportTaint")
lib.ReportSuppressed = Proxy("ReportSuppressed")

local function OrdinaryTable(value)
  local guard = core.SecretGuard
  if guard and guard.CanAccess and not guard:CanAccess(value) then return nil end
  if type(value) ~= "table" then return nil end
  if guard and guard.CanAccessTable and not guard:CanAccessTable(value) then return nil end
  return value
end

local function AddonName(value)
  local util = core.Util
  local ordinary = value
  if util and util.Scrub then
    local ok, scrubbed = pcall(util.Scrub, util, value)
    if not ok then return nil end
    ordinary = scrubbed
  else
    local guard = core.SecretGuard
    if guard and guard.CanAccess and not guard:CanAccess(value) then return nil end
  end
  if ordinary == nil then return nil end

  local name
  if util and util.SafeToString then
    local ok, rendered = pcall(util.SafeToString, util, ordinary)
    if ok then name = rendered end
  elseif type(ordinary) == "string" then
    name = ordinary
  end

  if type(name) ~= "string" or name == "" then return nil end
  if name == "<inaccessible>" or name == "<secret>" then return nil end
  if #name > 128 then name = name:sub(1, 128) end
  return name
end
local function Install(target, methods)
  local ok = pcall(function()
    for name, fn in pairs(methods) do target[name] = fn end
  end)
  return ok
end

-- Embed(target, addonName[, opts]) adds namespaced bound helpers.
function lib:Embed(target, addonName, opts)
  target = OrdinaryTable(target)
  addonName = AddonName(addonName)
  if not target or not addonName then return nil end

  local current = _G.RothDevLib or self._core
  if not current then return nil end
  local okInit = pcall(current.InitAddon, current, addonName, opts)
  if not okInit then return nil end

  local methods = {
    RDL_Breadcrumb = function(_, category, message, data)
      return current:Breadcrumb(addonName, category, message, data)
    end,
    RDL_Metric = function(_, name, value, unit, metricOpts)
      return current:Metric(addonName, name, value, unit, metricOpts)
    end,
    RDL_Alert = function(_, code, message, data, level)
      return current:Alert(addonName, code, message, data, level)
    end,
    RDL_Assert = function(_, condition, code, message, data)
      return current:Assert(addonName, condition, code, message, data)
    end,
    RDL_SafeCall = function(_, funcName, fn, ...)
      return current:SafeCall(addonName, funcName, fn, ...)
    end,
    RDL_SafeCallCtx = function(_, funcName, ctx, fn, ...)
      return current:SafeCallCtx(addonName, funcName, ctx, fn, ...)
    end,
    RDL_WrapSafe = function(_, funcName, fn, staticCtx)
      return current:WrapSafe(addonName, funcName, fn, staticCtx)
    end,
    RDL_WrapSafeCtx = function(_, funcName, fn, ctxFn)
      return current:WrapSafeCtx(addonName, funcName, fn, ctxFn)
    end,
    RDL_WrapUnsafe = function(_, funcName, fn, ctxFn)
      return current:WrapUnsafe(addonName, funcName, fn, ctxFn)
    end,
    RDL_Profile = function(_, funcName, fn, profileOpts, ...)
      return current:Profile(addonName, funcName, fn, profileOpts, ...)
    end,
    RDL_WrapProfiled = function(_, funcName, fn, profileOpts)
      return current:WrapProfiled(addonName, funcName, fn, profileOpts)
    end,
    RDL_MemDelta = function(_, funcName, fn, memOpts, ...)
      return current:MemDelta(addonName, funcName, fn, memOpts, ...)
    end,
    RDL_WrapMemDelta = function(_, funcName, fn, memOpts)
      return current:WrapMemDelta(addonName, funcName, fn, memOpts)
    end,
    RDL_MemSample = function(_, tag, sampleOpts)
      return current:MemSample(addonName, tag, sampleOpts)
    end,
    RDL_Enter = function(_, funcName, ctx)
      return current:Enter(addonName, funcName, ctx)
    end,
    RDL_Leave = function(_, token)
      return current:Leave(token)
    end,
    RDL_Report = function(_, kind, message, reportOpts)
      return current:Report(addonName, kind, message, reportOpts)
    end,
    RDL_Error = function(_, message, reportOpts)
      return current:ReportError(addonName, message, reportOpts)
    end,
    RDL_Warning = function(_, message, reportOpts)
      return current:ReportWarning(addonName, message, reportOpts)
    end,
    RDL_Taint = function(_, message, reportOpts)
      return current:ReportTaint(addonName, message, reportOpts)
    end,
    RDL_Suppressed = function(_, message, reportOpts)
      return current:ReportSuppressed(addonName, message, reportOpts)
    end,
  }

  if not Install(target, methods) then return nil end
  return target
end
