-- !RothDevLib/Capture/Reported.lua
-- Explicit external report intake with bounded ordinary-value snapshots.

local RDL = _G.RothDevLib
local Capture = RDL and RDL.Capture
if not Capture then return end

local function U()
  return RDL.Util
end

local function SafeText(value, fallback, maxBytes)
  local util = U()
  local ordinary = value
  if util and util.Scrub then
    local ok, scrubbed = pcall(util.Scrub, util, value)
    if ok then ordinary = scrubbed else ordinary = "<unavailable>" end
  end

  local text = fallback or ""
  if ordinary ~= nil and util and util.SafeToString then
    local ok, rendered = pcall(util.SafeToString, util, ordinary)
    if ok then text = rendered end
  elseif ordinary ~= nil and type(ordinary) == "string" then
    text = ordinary
  end

  if util and util.FilterSecretEscapes then
    local ok, filtered = pcall(util.FilterSecretEscapes, util, text)
    if ok then text = filtered end
  end
  if type(text) ~= "string" then text = fallback or "" end

  maxBytes = tonumber(maxBytes) or 8192
  if #text > maxBytes then text = text:sub(1, maxBytes) .. "<truncated>" end
  return text
end

local function SafeCopy(value, opts)
  local util = U()
  if util and util.CopyDiagnosticValue then
    local ok, copy = pcall(util.CopyDiagnosticValue, util, value, opts or {
      maxDepth = 4,
      maxEntries = 80,
      maxStringBytes = 4096,
    })
    if ok then return copy end
  end
  return SafeText(value, "<unavailable>", 4096)
end

local function SafeOptions(value)
  local copied = SafeCopy(value, {
    maxDepth = 4,
    maxEntries = 80,
    maxStringBytes = 8192,
  })
  return type(copied) == "table" and copied or {}
end

local function Settings()
  local raw
  if RDL.DB and type(RDL.DB.GetSettings) == "function" then
    local ok, value = pcall(RDL.DB.GetSettings, RDL.DB)
    if ok then raw = value end
  end
  local copied = SafeCopy(raw, { maxDepth = 2, maxEntries = 100, maxStringBytes = 1024 })
  return type(copied) == "table" and copied or {}
end

local function FilterLocals(value)
  local util = U()
  local copied = SafeCopy(value, {
    maxDepth = 3,
    maxEntries = 80,
    maxStringBytes = 8192,
  })
  if copied == nil then return nil end

  local text
  if type(copied) == "table" and util and util.SafeSerializeTable then
    local ok, rendered = pcall(util.SafeSerializeTable, util, copied)
    if ok then text = rendered else text = "<unavailable>" end
  elseif type(copied) == "string" then
    text = copied
  else
    text = SafeText(copied, "", 8192)
  end

  local settings = Settings()
  local maxSize = tonumber(settings.maxLocalsSize) or 8192
  if maxSize < 256 then maxSize = 256 end
  if maxSize > 1024 * 1024 then maxSize = 1024 * 1024 end

  if util and util.FilterLocals then
    local ok, filtered = pcall(util.FilterLocals, util, text, maxSize)
    if ok then text = filtered else text = "<unavailable>" end
  else
    text = text:gsub("|K[^|]*|k", "<filtered>")
  end

  if type(text) ~= "string" then return nil end
  if #text > maxSize then
    text = text:sub(1, maxSize) .. "\n...[truncated]"
  end
  return text
end

local function NormalizeStack(stack, stackLevel)
  local stackText = SafeCopy(stack, { maxDepth = 1, maxEntries = 1, maxStringBytes = 64 * 1024 })
  if type(stackText) == "string" and stackText ~= "" and stackText ~= "<inaccessible>" then
    local util = U()
    if util and util.FilterSecretEscapes then
      local ok, filtered = pcall(util.FilterSecretEscapes, util, stackText)
      if ok then return filtered end
    end
    return stackText
  end

  local levelValue = SafeCopy(stackLevel, { maxDepth = 1, maxEntries = 1, maxStringBytes = 32 })
  local level = tonumber(levelValue) or 4
  if level < 1 then level = 1 end
  if level > 20 then level = 20 end

  if type(_G.debugstack) ~= "function" then return "" end
  local ok, captured = pcall(_G.debugstack, level, 40, 40)
  if ok then return SafeText(captured, "", 64 * 1024) end
  return ""
end

local function BuildAndStore(kind, message, stack, locals, addonName, funcName, extra, signature)
  if type(Capture.BuildEntry) ~= "function" or type(Capture.StoreEntry) ~= "function" then
    return nil
  end

  local okBuild, entry = pcall(
    Capture.BuildEntry,
    kind,
    message,
    stack,
    locals,
    addonName,
    funcName,
    extra
  )
  if not okBuild or type(entry) ~= "table" then
    if RDL.Log then
      RDL:Log("ERROR", "REPORT", "Failed to build external report", {
        error = SafeText(entry, "<error>", 2048),
      })
    end
    return nil
  end

  if signature and signature ~= "" then entry.sig = signature end

  local okStore, result = pcall(Capture.StoreEntry, entry)
  if not okStore and RDL.Log then
    RDL:Log("ERROR", "REPORT", "Failed to store external report", {
      error = SafeText(result, "<error>", 2048),
    })
    return nil
  end
  return entry
end

function Capture:OnReported(kind, addonName, message, opts)
  if self._disabled then return end

  local safeKind = SafeText(kind, "SUPPRESSED", 64)
  if safeKind == "" then safeKind = "SUPPRESSED" end
  local safeAddon = SafeText(addonName, "<?>", 128)
  if safeAddon == "" then safeAddon = "<?>" end
  local safeOpts = SafeOptions(opts)

  local msg = SafeText(message, "", 64 * 1024)
  local code = safeOpts.code ~= nil and SafeText(safeOpts.code, "", 256) or nil
  local level = safeOpts.level ~= nil and SafeText(safeOpts.level, "", 32) or nil
  if code and code ~= "" then msg = code .. ": " .. msg end
  if level and level ~= "" then msg = "[" .. level .. "] " .. msg end

  local stack = NormalizeStack(safeOpts.stack or safeOpts.traceback, safeOpts.stackLevel)
  local locals = FilterLocals(safeOpts.locals)
  local localsProbe
  if locals == nil and RDL.Locals and type(RDL.Locals.CaptureBest) == "function" then
    local ok, capturedLocals, meta = pcall(RDL.Locals.CaptureBest, RDL.Locals, {
      addon = safeAddon,
      stack = stack,
      baseLevel = 3,
    })
    if ok then
      locals = FilterLocals(capturedLocals)
      localsProbe = SafeCopy(meta)
    end
  end

  local extra = {}
  if type(safeOpts.extra) == "table" then
    for key, value in pairs(safeOpts.extra) do extra[key] = value end
  end
  if extra.source == nil then extra.source = "report" end
  if extra.code == nil then extra.code = code end
  if extra.level == nil then extra.level = level end
  if extra.data == nil then extra.data = safeOpts.data end
  if extra.event == nil then extra.event = safeOpts.event end
  if extra.tag == nil then extra.tag = safeOpts.tag end
  if extra.localsProbe == nil then extra.localsProbe = localsProbe end

  local funcName = safeOpts.func or safeOpts.funcName
  if funcName ~= nil then funcName = SafeText(funcName, "", 512) end

  local rawSignature = safeOpts.signature or safeOpts.sig
  local signature = rawSignature ~= nil and SafeText(rawSignature, "", 2048) or nil
  local entry = BuildAndStore(safeKind, msg, stack, locals, safeAddon, funcName, extra, signature)
  if not entry then return nil end

  if RDL.Log then
    RDL:Log("INFO", "REPORT", "External report captured", {
      kind = safeKind,
      addon = safeAddon,
      func = funcName,
    })
  end
  return entry
end
