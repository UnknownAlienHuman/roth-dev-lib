-- !RothDevLib/Capture/Reported.lua
-- External report intake.
--
-- Purpose:
--   Allow other addons to report errors/warnings/taints (or any custom kind) into RothDevLib
--   even when they do not propagate to the global Lua error handler.
--
-- Design:
--   * Low overhead: no hooks; this is only called explicitly by integrating addons.
--   * Best-effort normalization: accepts caller-provided stack/locals, otherwise captures a stack.
--   * Secret-safe: filters Secret Values (|K...|k) in message/stack/locals.

local RDL = _G.RothDevLib
local Capture = RDL and RDL.Capture
if not Capture then return end

local function Settings()
  return (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or {}
end

local function Scrub(s)
  local U = RDL.Util
  if U and U.Scrub then
    return U:Scrub(s)
  end
  return s
end

local function FilterLocals(locals)
  if locals == nil then return nil end

  if RDL.SecretGuard and RDL.SecretGuard.FilterLocals then
    locals = RDL.SecretGuard:FilterLocals(locals)
  elseif type(locals) == "string" then
    locals = locals:gsub("|K[^|]*|k", "<filtered>")
  end

  local s = Settings()
  local maxSize = tonumber(s.maxLocalsSize) or 8192
  if type(locals) == "string" and #locals > maxSize then
    locals = locals:sub(1, maxSize) .. "\n...[truncated]"
  end
  return locals
end

local function NormalizeStack(stack, stackLevel)
  if type(stack) == "string" and stack ~= "" then
    return Scrub(stack)
  end

  local lvl = tonumber(stackLevel) or 4
  local ok, s = pcall(function()
    return debugstack(lvl, 40, 40)
  end)

  if ok and type(s) == "string" then
    return Scrub(s)
  end
  return ""
end

-- Public API for explicit report intake.
--
-- Capture:OnReported(kind, addonName, message, opts)
--
-- opts:
--   stack: string (preferred) - stack trace
--   stackLevel: number - if stack not provided, capture from this stack level (default 4)
--   locals: string|table - locals dump (string preferred)
--   func: string - function/context label shown in UI
--   code: string - optional error code
--   level: string - optional severity string (INFO/WARN/ERROR)
--   data: any - payload for export/debug
--   extra: table - extra metadata (merged)
function Capture:OnReported(kind, addonName, message, opts)
  if self._disabled then return end

  kind = tostring(kind or "SUPPRESSED")
  addonName = tostring(addonName or "<?>")

  opts = opts or {}

  local msg = message
  if msg == nil then msg = "" end
  msg = tostring(msg)
  msg = Scrub(msg)

  -- If the caller passes `code`/`level`, prefix similarly to OnIntegrationEvent.
  if opts.code then
    msg = tostring(opts.code) .. ": " .. msg
  end
  if opts.level then
    msg = "[" .. tostring(opts.level) .. "] " .. msg
  end

  local stack = NormalizeStack(opts.stack or opts.traceback, opts.stackLevel)
  local locals = FilterLocals(opts.locals)
  local lmeta = nil
  if locals == nil and RDL.Locals and RDL.Locals.CaptureBest then
    local okL, l, m = pcall(function()
      -- Call path is typically: addon -> RDL:Report -> Capture:OnReported.
      return RDL.Locals:CaptureBest({ addon = addonName, stack = stack, baseLevel = 3 })
    end)
    if okL then
      locals = l
      lmeta = m
    end
  end

  -- Structured metadata: always tag the source.
  local extra = {}
  if type(opts.extra) == "table" then
    for k, v in pairs(opts.extra) do extra[k] = v end
  end

  extra.source = extra.source or "report"
  extra.code = extra.code or opts.code
  extra.level = extra.level or opts.level
  extra.data = extra.data or opts.data
  extra.event = extra.event or opts.event
  extra.tag = extra.tag or opts.tag
  extra.localsProbe = extra.localsProbe or lmeta

  local funcName = opts.func or opts.funcName or nil

  local entry = Capture.BuildEntry(kind, msg, stack, locals, addonName, funcName, extra)

  -- Optional: allow caller to provide a stable signature for grouping.
  if opts.signature or opts.sig then
    entry.sig = tostring(opts.signature or opts.sig)
  end

  Capture.StoreEntry(entry)

  if RDL and RDL.Log then
    pcall(function()
      RDL:Log("INFO", "REPORT", "External report captured", { kind = kind, addon = addonName, func = funcName })
    end)
  end
end
