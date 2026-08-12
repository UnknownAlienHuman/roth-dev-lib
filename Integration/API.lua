-- !RothDevLib/Integration/API.lua
-- Public integration API for other addons.
-- Ported from !RothGrabber/Modules/API.lua.
-- Callbacks moved to Integration/Callbacks.lua (no duplication).
--
-- Usage example (in some addon):
--   local RDL = _G.RothDevLib
--   if RDL and RDL.InitAddon then
--     RDL:InitAddon("MyAddon")
--     RDL:Breadcrumb("MyAddon", "event", "PLAYER_LOGIN")
--     RDL:Assert("MyAddon", x ~= nil, "E_NO_X", "x missing", { ... })
--   end

local RDL = _G.RothDevLib

-- Bus wrappers -------------------------------------------------------

function RDL:InitAddon(addonName, opts)
  if self.Bus and self.Bus.RegisterAddon then
    return self.Bus:RegisterAddon(addonName, opts)
  end
  return nil
end

function RDL:Breadcrumb(addonName, category, message, data)
  if self.Bus and self.Bus.Breadcrumb then
    self.Bus:Breadcrumb(addonName, category, message, data)
  end
end

function RDL:Metric(addonName, name, value, unit, opts)
  if self.Bus and self.Bus.Metric then
    self.Bus:Metric(addonName, name, value, unit, opts)
  end
end

-- Phase 3: Profiling helpers -----------------------------------------
-- CPU profiling around a call. Emits Bus metrics and ALERT spikes.
function RDL:Profile(addonName, funcName, fn, opts, ...)
  if self.CPU and self.CPU.Measure then
    return self.CPU:Measure(addonName, funcName, fn, opts, ...)
  end
  return fn(...)
end

function RDL:WrapProfiled(addonName, funcName, fn, opts)
  if self.CPU and self.CPU.Wrap then
    return self.CPU:Wrap(addonName, funcName, fn, opts)
  end
  return fn
end

-- Memory delta around a call. Emits Bus metrics and ALERT spikes.
function RDL:MemDelta(addonName, funcName, fn, opts, ...)
  if self.Mem and self.Mem.Measure then
    return self.Mem:Measure(addonName, funcName, fn, opts, ...)
  end
  return fn(...)
end

function RDL:WrapMemDelta(addonName, funcName, fn, opts)
  if self.Mem and self.Mem.Wrap then
    return self.Mem:Wrap(addonName, funcName, fn, opts)
  end
  return fn
end

function RDL:MemSample(addonName, tag, opts)
  if self.Mem and self.Mem.Sample then
    return self.Mem:Sample(addonName, tag, opts)
  end
end

-- Alert / Assert are structured entries stored in SavedVariables.

function RDL:Alert(addonName, code, message, data, level)
  if self.Bus and self.Bus.Alert then
    self.Bus:Alert(addonName, code, message, data, level)
  end
  if self.Capture and self.Capture.OnIntegrationEvent then
    self.Capture:OnIntegrationEvent("ALERT", addonName, code, message, data, level)
  end
  self:Fire("RDL_INTEGRATION", "ALERT", { addon = addonName, code = code, message = message, level = level })
end

function RDL:Assert(addonName, condition, code, message, data)
  if condition then return true end

  local msg = message or "assert failed"
  if code then
    msg = tostring(code) .. ": " .. tostring(msg)
  end

  if self.Capture and self.Capture.OnIntegrationEvent then
    self.Capture:OnIntegrationEvent("ASSERT", addonName, code, msg, data, "ERROR")
  else
    self:Breadcrumb(addonName, "assert", code or "assert", { message = msg, data = data })
  end

  self:Fire("RDL_INTEGRATION", "ASSERT", { addon = addonName, code = code, message = msg })
  return false
end



-- Explicit reports (external intake) ------------------------------------
--
-- Some addons wrap errors in xpcall and do not let them reach the global error handler.
-- They can explicitly report errors/warnings/taints into RothDevLib using this API.
--
-- Example:
--   local Dev = LibStub("RothDevLib-1.0", true)
--   if Dev then Dev:Report("MyAddon", "LUA_ERROR", err, { stack = debugstack(1, 40, 40), func = "Init" }) end

function RDL:Report(addonName, kind, message, opts)
  if self.Capture and self.Capture.OnReported then
    self.Capture:OnReported(kind, addonName, message, opts)
  elseif self.Capture and self.Capture.OnIntegrationEvent then
    -- Fallback: treat as integration event
    self.Capture:OnIntegrationEvent(kind or "SUPPRESSED", addonName, nil, message, opts and opts.data, opts and opts.level)
  end

  self:Fire("RDL_INTEGRATION", "REPORT", { addon = addonName, kind = kind, message = message })
end

function RDL:ReportError(addonName, message, opts)
  return self:Report(addonName, "LUA_ERROR", message, opts)
end

function RDL:ReportWarning(addonName, message, opts)
  return self:Report(addonName, "LUA_WARNING", message, opts)
end

function RDL:ReportTaint(addonName, message, opts)
  -- Caller can choose TAINT_BLOCKED vs TAINT_FORBIDDEN via opts.kind override.
  local k = (opts and opts.kind) or "TAINT_BLOCKED"
  return self:Report(addonName, k, message, opts)
end

function RDL:ReportSuppressed(addonName, message, opts)
  return self:Report(addonName, "SUPPRESSED", message, opts)
end

-- Doctor helpers (convenience API on RDL namespace) --------------------

function RDL:Enter(addonName, funcName, ctx)
  if self.Doctor and self.Doctor.Enter then
    return self.Doctor:Enter(addonName, funcName, ctx)
  end
  return nil
end

function RDL:Leave()
  if self.Doctor and self.Doctor.Leave then
    self.Doctor:Leave()
  end
end

-- Convenience: create a small per-addon client object so callers don't need to
-- pass addonName on every call.
--
-- Example:
--   local dev = RDL:NewAddon("MyAddon")
--   dev:Breadcrumb("event", "PLAYER_LOGIN")
--   dev:Assert(x ~= nil, "E_NO_X", "x missing")
function RDL:NewAddon(addonName, opts)
  if type(addonName) ~= "string" or addonName == "" then return nil end

  -- Register addon ring buffer settings once.
  self:InitAddon(addonName, opts)

  local client = { addon = addonName }

  function client:Breadcrumb(category, message, data)
    return RDL:Breadcrumb(addonName, category, message, data)
  end

  function client:Metric(name, value, unit, mopts)
    return RDL:Metric(addonName, name, value, unit, mopts)
  end

  function client:Profile(funcName, fn, popts, ...)
    return RDL:Profile(addonName, funcName, fn, popts, ...)
  end

  function client:WrapProfiled(funcName, fn, popts)
    return RDL:WrapProfiled(addonName, funcName, fn, popts)
  end

  function client:MemDelta(funcName, fn, mopts, ...)
    return RDL:MemDelta(addonName, funcName, fn, mopts, ...)
  end

  function client:WrapMemDelta(funcName, fn, mopts)
    return RDL:WrapMemDelta(addonName, funcName, fn, mopts)
  end

  function client:MemSample(tag, sopts)
    return RDL:MemSample(addonName, tag, sopts)
  end

  function client:Alert(code, message, data, level)
    return RDL:Alert(addonName, code, message, data, level)
  end

  function client:Assert(condition, code, message, data)
    return RDL:Assert(addonName, condition, code, message, data)
  end

  function client:Report(kind, message, opts)
    return RDL:Report(addonName, kind, message, opts)
  end

  function client:Error(message, opts)
    return RDL:ReportError(addonName, message, opts)
  end

  function client:Warning(message, opts)
    return RDL:ReportWarning(addonName, message, opts)
  end

  function client:Taint(message, opts)
    return RDL:ReportTaint(addonName, message, opts)
  end

  function client:Suppressed(message, opts)
    return RDL:ReportSuppressed(addonName, message, opts)
  end
  function client:SafeCall(funcName, fn, ...)
    return RDL:SafeCall(addonName, funcName, fn, ...)
  end

  function client:SafeCallCtx(funcName, ctx, fn, ...)
    return RDL:SafeCallCtx(addonName, funcName, ctx, fn, ...)
  end

  function client:WrapSafe(funcName, fn, staticCtx)
    return RDL:WrapSafe(addonName, funcName, fn, staticCtx)
  end

  function client:WrapSafeCtx(funcName, fn, ctxFn)
    return RDL:WrapSafeCtx(addonName, funcName, fn, ctxFn)
  end

  function client:WrapUnsafe(funcName, fn, ctxFn)
    return RDL:WrapUnsafe(addonName, funcName, fn, ctxFn)
  end


  function client:Enter(funcName, ctx)
    return RDL:Enter(addonName, funcName, ctx)
  end

  function client:Leave()
    return RDL:Leave()
  end
  function client:Log(level, category, message, data)
    level = level and level:upper() or "INFO"
    if level == "ERROR" or level == "CRITICAL" then
      return RDL:ReportError(addonName, message, { data = data, level = level, source = category })
    elseif level == "WARN" or level == "WARNING" then
      return RDL:ReportWarning(addonName, message, { data = data, level = level, source = category })
    else
      return RDL:Breadcrumb(addonName, category or "log", message, data)
    end
  end

  return client
end
