-- !RothDevLib/Integration/LibStub.lua
-- Optional LibStub registration for embedded-library style integrations.
--
-- Goals:
--   * Allow other addons to depend on RothDevLib as a library:
--       local RDL = LibStub("RothDevLib-1.0", true)
--   * Keep a single authoritative instance (the global _G.RothDevLib singleton).
--   * Provide a minimal stable surface with forward compatibility.

local core = _G.RothDevLib
if not core then return end

local LibStub = _G.LibStub
if type(LibStub) ~= "table" or type(LibStub.NewLibrary) ~= "function" then return end

local MAJOR, MINOR = "RothDevLib-1.0", 2

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
    local c = _G.RothDevLib or self._core
    if not c then return nil end
    local fn = c[method]
    if type(fn) ~= "function" then return nil end
    return fn(c, ...)
  end
end

-- Core wrappers -------------------------------------------------------

lib.Log = lib.Log or Proxy("Log")
lib.SafeCall = lib.SafeCall or Proxy("SafeCall")
lib.SafeCallCtx = lib.SafeCallCtx or Proxy("SafeCallCtx")
lib.WrapSafe = lib.WrapSafe or Proxy("WrapSafe")
lib.WrapSafeCtx = lib.WrapSafeCtx or Proxy("WrapSafeCtx")
lib.WrapUnsafe = lib.WrapUnsafe or Proxy("WrapUnsafe")

-- Perf (Phase 3)
lib.Profile = lib.Profile or Proxy("Profile")
lib.WrapProfiled = lib.WrapProfiled or Proxy("WrapProfiled")
lib.MemDelta = lib.MemDelta or Proxy("MemDelta")
lib.WrapMemDelta = lib.WrapMemDelta or Proxy("WrapMemDelta")
lib.MemSample = lib.MemSample or Proxy("MemSample")

-- Integration bus wrappers -------------------------------------------

lib.InitAddon = lib.InitAddon or Proxy("InitAddon")
lib.Breadcrumb = lib.Breadcrumb or Proxy("Breadcrumb")
lib.Metric = lib.Metric or Proxy("Metric")
lib.Alert = lib.Alert or Proxy("Alert")
lib.Assert = lib.Assert or Proxy("Assert")
lib.Enter = lib.Enter or Proxy("Enter")
lib.Leave = lib.Leave or Proxy("Leave")
lib.NewAddon = lib.NewAddon or Proxy("NewAddon")

-- Explicit report intake (see Integration/API.lua)
lib.Report = lib.Report or Proxy("Report")
lib.ReportError = lib.ReportError or Proxy("ReportError")
lib.ReportWarning = lib.ReportWarning or Proxy("ReportWarning")
lib.ReportTaint = lib.ReportTaint or Proxy("ReportTaint")
lib.ReportSuppressed = lib.ReportSuppressed or Proxy("ReportSuppressed")

-- Embedding -----------------------------------------------------------
--
-- Embed(target, addonName[, opts])
--   Adds bound helper methods to `target` so calls don't need addonName.
--
-- Example:
--   local Dev = LibStub("RothDevLib-1.0", true)
--   if Dev then Dev:Embed(MyAddon, "MyAddon") end
--   MyAddon:RDL_Breadcrumb("event", "PLAYER_LOGIN")

function lib:Embed(target, addonName, opts)
  if type(target) ~= "table" then return nil end
  if type(addonName) ~= "string" or addonName == "" then return nil end

  local coreNow = _G.RothDevLib or self._core
  if not coreNow then return nil end

  coreNow:InitAddon(addonName, opts)

  -- Bound methods use namespaced keys to avoid collisions.
  target.RDL_Breadcrumb = function(_, category, message, data)
    return coreNow:Breadcrumb(addonName, category, message, data)
  end
  target.RDL_Metric = function(_, name, value, unit, mopts)
    return coreNow:Metric(addonName, name, value, unit, mopts)
  end
  target.RDL_Alert = function(_, code, message, data, level)
    return coreNow:Alert(addonName, code, message, data, level)
  end
  target.RDL_Assert = function(_, condition, code, message, data)
    return coreNow:Assert(addonName, condition, code, message, data)
  end
  target.RDL_SafeCall = function(_, funcName, fn, ...)
    return coreNow:SafeCall(addonName, funcName, fn, ...)
  end
  target.RDL_SafeCallCtx = function(_, funcName, ctx, fn, ...)
    return coreNow:SafeCallCtx(addonName, funcName, ctx, fn, ...)
  end
  target.RDL_WrapSafe = function(_, funcName, fn, staticCtx)
    return coreNow:WrapSafe(addonName, funcName, fn, staticCtx)
  end
  target.RDL_WrapSafeCtx = function(_, funcName, fn, ctxFn)
    return coreNow:WrapSafeCtx(addonName, funcName, fn, ctxFn)
  end
  target.RDL_WrapUnsafe = function(_, funcName, fn, ctxFn)
    return coreNow:WrapUnsafe(addonName, funcName, fn, ctxFn)
  end

  -- Perf helpers
  target.RDL_Profile = function(_, funcName, fn, popts, ...)
    return coreNow:Profile(addonName, funcName, fn, popts, ...)
  end
  target.RDL_WrapProfiled = function(_, funcName, fn, popts)
    return coreNow:WrapProfiled(addonName, funcName, fn, popts)
  end
  target.RDL_MemDelta = function(_, funcName, fn, mopts, ...)
    return coreNow:MemDelta(addonName, funcName, fn, mopts, ...)
  end
  target.RDL_WrapMemDelta = function(_, funcName, fn, mopts)
    return coreNow:WrapMemDelta(addonName, funcName, fn, mopts)
  end
  target.RDL_MemSample = function(_, tag, sopts)
    return coreNow:MemSample(addonName, tag, sopts)
  end
  target.RDL_Enter = function(_, funcName, ctx)
    return coreNow:Enter(addonName, funcName, ctx)
  end
  target.RDL_Leave = function(_) return coreNow:Leave() end

  -- Explicit reports (external intake)
  target.RDL_Report = function(_, kind, message, ropts)
    return coreNow:Report(addonName, kind, message, ropts)
  end
  target.RDL_Error = function(_, message, ropts)
    return coreNow:ReportError(addonName, message, ropts)
  end
  target.RDL_Warning = function(_, message, ropts)
    return coreNow:ReportWarning(addonName, message, ropts)
  end
  target.RDL_Taint = function(_, message, ropts)
    return coreNow:ReportTaint(addonName, message, ropts)
  end
  target.RDL_Suppressed = function(_, message, ropts)
    return coreNow:ReportSuppressed(addonName, message, ropts)
  end

  return target
end
