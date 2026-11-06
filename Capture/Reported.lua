-- !RothDevLib/Capture/Reported.lua
-- Bounded external report intake for addons that catch their own failures.

local RDL = _G.RothDevLib
local Capture = RDL and RDL.Capture
if not Capture then return end

local ACCEPTED_STATUS = { stored = true, queued = true, ignored = true }

local function Settings()
  if RDL.DB and type(RDL.DB.GetSettings) == "function" then
    local ok, value = pcall(RDL.DB.GetSettings, RDL.DB)
    if ok and type(value) == "table" then return value end
  end
  return {}
end

local function SafeCopy(value, options)
  local util = RDL.Util
  if util and type(util.CopyDiagnosticValue) == "function" then
    local ok, copy = pcall(util.CopyDiagnosticValue, util, value, options or {
      maxDepth = 5,
      maxEntries = 100,
      maxNodes = 600,
      maxStringBytes = 8192,
    })
    if ok then return copy end
  end
  return nil
end

local function SafeText(value, fallback, maximum)
  local util = RDL.Util
  local text = type(fallback) == "string" and fallback or ""
  if util and type(util.SafeToString) == "function" then
    local ok, rendered = pcall(util.SafeToString, util, value)
    if ok and type(rendered) == "string" then text = rendered end
  elseif type(value) == "string" then
    text = value
  end
  if util and type(util.FilterSecretEscapes) == "function" then
    local ok, filtered = pcall(util.FilterSecretEscapes, util, text)
    if ok and type(filtered) == "string" then text = filtered end
  end
  maximum = tonumber(maximum) or 8192
  if #text > maximum then text = text:sub(1, maximum) .. "<truncated>" end
  return text
end

local function NormalizeStack(stack, stackLevel)
  local supplied = SafeCopy(stack, { maxDepth = 1, maxEntries = 1, maxNodes = 2, maxStringBytes = 128 * 1024 })
  if type(supplied) == "string" and supplied ~= "" then
    return SafeText(supplied, "", 128 * 1024)
  end

  local level = tonumber(SafeCopy(stackLevel)) or 4
  if level < 1 then level = 1 elseif level > 100 then level = 100 end
  if type(_G.debugstack) ~= "function" then return "" end
  local ok, value = pcall(_G.debugstack, level, 40, 40)
  return ok and SafeText(value, "", 128 * 1024) or ""
end

local function NormalizeLocals(value)
  local copy = SafeCopy(value, {
    maxDepth = 4,
    maxEntries = 80,
    maxNodes = 500,
    maxStringBytes = tonumber(Settings().maxLocalsSize) or 8192,
  })
  if copy == nil then return nil end
  if type(copy) == "string" then
    return SafeText(copy, "", tonumber(Settings().maxLocalsSize) or 8192)
  end

  local util = RDL.Util
  if util and type(util.SafeSerializeTable) == "function" then
    local ok, text = pcall(util.SafeSerializeTable, util, copy)
    if ok then return SafeText(text, "", tonumber(Settings().maxLocalsSize) or 8192) end
  end
  return SafeText(copy, "<unavailable>", tonumber(Settings().maxLocalsSize) or 8192)
end

local function BuildAndStore(kind, addonName, message, options)
  if type(Capture.BuildEntry) ~= "function" or type(Capture.StoreEntry) ~= "function" then
    return nil, "unavailable"
  end

  local opts = SafeCopy(options)
  if type(opts) ~= "table" then opts = {} end

  local safeKind = SafeText(kind, "SUPPRESSED", 64)
  if safeKind == "" or safeKind == "nil" then safeKind = "SUPPRESSED" end
  local safeAddon = SafeText(addonName, "<?>" , 128)
  if safeAddon == "" or safeAddon == "nil" then safeAddon = "<?>" end
  local msg = SafeText(message, "", 64 * 1024)

  local code = opts.code and SafeText(opts.code, "", 256) or nil
  local level = opts.level and SafeText(opts.level, "", 32) or nil
  if code and code ~= "" then msg = code .. ": " .. msg end
  if level and level ~= "" then msg = "[" .. level .. "] " .. msg end

  local stack = NormalizeStack(opts.stack or opts.traceback, opts.stackLevel)
  local locals = NormalizeLocals(opts.locals)
  local localsProbe
  if locals == nil and RDL.Locals and type(RDL.Locals.CaptureBest) == "function" then
    local ok, captured, meta = pcall(RDL.Locals.CaptureBest, RDL.Locals, {
      addon = safeAddon,
      stack = stack,
      baseLevel = 3,
    })
    if ok then
      locals = NormalizeLocals(captured)
      localsProbe = SafeCopy(meta)
    end
  end

  local extra = SafeCopy(opts.extra)
  if type(extra) ~= "table" then extra = {} end
  if extra.source == nil then extra.source = "report" end
  if extra.code == nil then extra.code = code end
  if extra.level == nil then extra.level = level end
  if extra.data == nil then extra.data = SafeCopy(opts.data) end
  if extra.event == nil then extra.event = SafeCopy(opts.event) end
  if extra.tag == nil then extra.tag = SafeCopy(opts.tag) end
  if extra.localsProbe == nil then extra.localsProbe = localsProbe end

  local funcName = opts.func or opts.funcName
  if funcName ~= nil then funcName = SafeText(funcName, "", 256) end

  local okBuild, entry = pcall(Capture.BuildEntry, safeKind, msg, stack, locals,
    safeAddon, funcName, extra)
  if not okBuild or type(entry) ~= "table" then return nil, "build-failed" end

  local signature = opts.signature
  if signature == nil then signature = opts.sig end
  if signature ~= nil then
    local safeSignature = SafeText(signature, "", 4096)
    if safeSignature ~= "" and safeSignature ~= "<inaccessible>"
        and safeSignature ~= "<secret>" and safeSignature ~= "<unavailable>" then
      entry.sig = safeSignature
    end
  end

  local okStore, status = pcall(Capture.StoreEntry, entry)
  if not okStore or not ACCEPTED_STATUS[status] then return nil, status or "store-failed" end
  return entry, status
end

function Capture:OnReported(kind, addonName, message, options)
  if self._disabled then return nil end
  local entry, status = BuildAndStore(kind, addonName, message, options)
  if entry and (status == "stored" or status == "queued") and type(RDL.Log) == "function" then
    pcall(RDL.Log, RDL, "INFO", "REPORT", "External report captured", {
      kind = entry.kind,
      addon = entry.addon,
      func = entry.func,
    })
  end
  return entry, status
end
