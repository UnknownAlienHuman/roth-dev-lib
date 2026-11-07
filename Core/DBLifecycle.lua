-- !RothDevLib/Core/DBLifecycle.lua
-- Separates early SavedVariables availability from player-session readiness,
-- bounds every persisted diagnostic root, and owns persistence-failure recovery.

local RDL = _G.RothDevLib
local DB = RDL and RDL.DB
if not DB then return end

local OriginalInit = DB.Init
local OriginalEnsureReady = DB.EnsureReady
local OriginalUpsertGroup = DB.UpsertGroup
local OriginalClear = DB.Clear

DB._playerReady = false
DB._writesSuspended = false

local SCHEMA = 5
local GROUP_SIGNATURE_BYTES = 4096
local GROUP_MESSAGE_BYTES = 16 * 1024
local GROUP_STACK_BYTES = 64 * 1024
local OCCURRENCE_MESSAGE_BYTES = 4096
local OCCURRENCE_STACK_BYTES = 16 * 1024
local FAILURE_MAX_GROUPS = 20
local FAILURE_MAX_SESSIONS = 10
local FAILURE_MESSAGE_BYTES = 4096
local FAILURE_STACK_BYTES = 16 * 1024
local MAX_SESSIONS = 50

local ROOT_FIELDS = {
  _schema = true,
  settings = true,
  sessions = true,
  sessionIndex = true,
  ignore = true,
  groups = true,
  persistence = true,
}

local SETTING_FIELDS = {
  maxGroups = true,
  maxOccurrencesPerGroup = true,
  forwardToDefaultErrorHandler = true,
  errorHandlerMode = true,
  chainCallPrevHandler = true,
  maintainOwnership = true,
  maintainOwnershipIntervalSec = true,
  lockErrorHandler = true,
  hideTaintPopups = true,
  hideBlizzardScriptErrors = true,
  minimap = true,
  minimapHide = true,
  minimapAngle = true,
  chatNotifyOnError = true,
  chatNotifyThrottleSec = true,
  captureChatErrors = true,
  chatTapWindowSec = true,
  chatTapMaxStackLines = true,
  chatTapHookAllFrames = true,
  chatTapStripColors = true,
  chatTapDedupSec = true,
  chatTapDedupMax = true,
  fallbackHookScriptErrors = true,
  scriptErrorsFrameSyncPollSec = true,
  scriptErrorsFrameImportMaxPerPoll = true,
  importBugGrabber = true,
  importBugGrabberHistory = true,
  bugGrabberPollSec = true,
  bugGrabberImportMaxPerPoll = true,
  bugGrabberScanMax = true,
  openOnErrorOutOfCombat = true,
  includeBreadcrumbsInErrors = true,
  breadcrumbsPerError = true,
  maxBreadcrumbsPerAddon = true,
  uiRefreshThrottleSec = true,
  metricMinInterval = true,
  minimapForceShowOnNextLogin = true,
  stormErrorsPerSec = true,
  stormWarningsPerSec = true,
  maxLocalsSize = true,
  captureLocals = true,
  localsProbeMax = true,
  localsProbeCache = true,
  localsProbesPerSec = true,
  enablePerfProfiling = true,
  cpuSampleRate = true,
  cpuSpikeMs = true,
  cpuAlertMinIntervalMs = true,
  memSpikeKB = true,
  memAlertMinIntervalMs = true,
  memWatchEnabled = true,
  memWatchIntervalSec = true,
  memWatchSpikeKB = true,
  monitorRefreshSec = true,
  monitorTopN = true,
  monitorMinSamples = true,
  uiFrames = true,
  uiPanes = true,
  uiUseScrollBoxList = true,
  uiGroupGridCols = true,
  uiUseButtonFrameShell = true,
  _validationPassLog = true,
  _reloadLoop = true,
}

local SESSION_FIELDS = {
  id = true,
  started = true,
  ended = true,
  build = true,
  character = true,
  class = true,
  spec = true,
  errors = true,
  warnings = true,
  taints = true,
  suppressed = true,
  alerts = true,
  asserts = true,
  throttledCount = true,
}

local SESSION_COUNTERS = {
  "errors", "warnings", "taints", "suppressed",
  "alerts", "asserts", "throttledCount",
}

local function Now()
  if type(_G.time) ~= "function" then return 0 end
  local ok, value = pcall(_G.time)
  return ok and type(value) == "number" and value or 0
end

local function FiniteNumber(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
end

local function TruncateString(value, maximum, fallback)
  if type(value) ~= "string" then return fallback end
  if #value <= maximum then return value end
  return value:sub(1, maximum) .. "<truncated>"
end

local function CompactDiagnostic(value, options)
  if value == nil then return nil end
  local util = RDL.Util
  if util and type(util.CopyDiagnosticValue) == "function" then
    local ok, copy = pcall(util.CopyDiagnosticValue, util, value, options)
    if ok then return copy end
  end

  local valueType = type(value)
  if valueType == "string" then
    return TruncateString(value, options.maxStringBytes or 4096, "")
  end
  if valueType == "number" then return FiniteNumber(value) and value or nil end
  if valueType == "boolean" then return value end
  return "<diagnostic omitted>"
end

local function CompactTable(value, options)
  local copy = CompactDiagnostic(value, options)
  return type(copy) == "table" and copy or {}
end

local function ClampNumber(settings, key, default, minimum, maximum, integer)
  local value = settings[key]
  if not FiniteNumber(value) then value = default end
  if integer then value = math.floor(value) end
  if value < minimum then value = minimum end
  if value > maximum then value = maximum end
  settings[key] = value
end

local function NormalizeBoolean(settings, key, default)
  if type(settings[key]) ~= "boolean" then settings[key] = default end
end

local function DropUnknownFields(value, allowed)
  if type(value) ~= "table" then return end
  for key in pairs(value) do
    if not allowed[key] then value[key] = nil end
  end
end

local function NormalizeSettings(settings)
  if type(settings) ~= "table" then return end
  DropUnknownFields(settings, SETTING_FIELDS)

  ClampNumber(settings, "maxGroups", 200, 10, 5000, true)
  ClampNumber(settings, "maxOccurrencesPerGroup", 10, 1, 100, true)
  ClampNumber(settings, "chatNotifyThrottleSec", 3, 0, 60, false)
  ClampNumber(settings, "chatTapWindowSec", 0.8, 0.05, 10, false)
  ClampNumber(settings, "chatTapMaxStackLines", 60, 1, 200, true)
  ClampNumber(settings, "chatTapDedupSec", 0.6, 0, 60, false)
  ClampNumber(settings, "chatTapDedupMax", 200, 10, 5000, true)
  ClampNumber(settings, "bugGrabberPollSec", 1, 0.25, 60, false)
  ClampNumber(settings, "bugGrabberImportMaxPerPoll", 200, 1, 1000, true)
  ClampNumber(settings, "bugGrabberScanMax", 5000, 1, 20000, true)
  ClampNumber(settings, "maxLocalsSize", 8192, 256, 64 * 1024, true)
  ClampNumber(settings, "localsProbeMax", 12, 0, 30, true)
  ClampNumber(settings, "localsProbesPerSec", 30, 1, 1000, true)
  ClampNumber(settings, "stormErrorsPerSec", 60, 1, 10000, true)
  ClampNumber(settings, "stormWarningsPerSec", 60, 1, 10000, true)
  ClampNumber(settings, "breadcrumbsPerError", 12, 0, 100, true)
  ClampNumber(settings, "maxBreadcrumbsPerAddon", 80, 10, 400, true)
  ClampNumber(settings, "uiRefreshThrottleSec", 0.15, 0, 5, false)
  ClampNumber(settings, "metricMinInterval", 1, 0, 60, false)
  ClampNumber(settings, "cpuSampleRate", 0.25, 0, 1, false)
  ClampNumber(settings, "cpuSpikeMs", 16, 1, 5000, false)
  ClampNumber(settings, "memSpikeKB", 64, 1, 1024 * 1024, false)
  ClampNumber(settings, "memWatchIntervalSec", 2, 0.2, 300, false)
  ClampNumber(settings, "cpuAlertMinIntervalMs", 2000, 0, 600000, false)
  ClampNumber(settings, "memAlertMinIntervalMs", 2000, 0, 600000, false)
  ClampNumber(settings, "memWatchSpikeKB", 256, 1, 1024 * 1024, false)
  ClampNumber(settings, "monitorRefreshSec", 1, 0.1, 60, false)
  ClampNumber(settings, "monitorTopN", 20, 1, 200, true)
  ClampNumber(settings, "monitorMinSamples", 1, 1, 1000000, true)
  ClampNumber(settings, "maintainOwnershipIntervalSec", 4, 0.25, 60, false)
  ClampNumber(settings, "scriptErrorsFrameSyncPollSec", 1, 0.25, 60, false)
  ClampNumber(settings, "scriptErrorsFrameImportMaxPerPoll", 60, 1, 1000, true)

  NormalizeBoolean(settings, "chainCallPrevHandler", true)
  NormalizeBoolean(settings, "importBugGrabber", true)
  NormalizeBoolean(settings, "importBugGrabberHistory", false)
  NormalizeBoolean(settings, "forwardToDefaultErrorHandler", false)
  NormalizeBoolean(settings, "hideTaintPopups", true)
  NormalizeBoolean(settings, "hideBlizzardScriptErrors", true)
  NormalizeBoolean(settings, "captureChatErrors", true)
  NormalizeBoolean(settings, "chatTapHookAllFrames", true)
  NormalizeBoolean(settings, "chatTapStripColors", true)
  NormalizeBoolean(settings, "chatNotifyOnError", true)
  NormalizeBoolean(settings, "includeBreadcrumbsInErrors", true)
  NormalizeBoolean(settings, "captureLocals", true)
  NormalizeBoolean(settings, "localsProbeCache", true)
  NormalizeBoolean(settings, "enablePerfProfiling", true)
  NormalizeBoolean(settings, "memWatchEnabled", false)
  NormalizeBoolean(settings, "openOnErrorOutOfCombat", false)
  NormalizeBoolean(settings, "minimapForceShowOnNextLogin", true)
  NormalizeBoolean(settings, "uiUseScrollBoxList", true)
  NormalizeBoolean(settings, "uiUseButtonFrameShell", true)

  -- Compatibility-first capture policy. Old persisted values must not revive
  -- handler wars or global setter replacement.
  settings.errorHandlerMode = "chain"
  settings.chainCallPrevHandler = true
  settings.maintainOwnership = false
  settings.lockErrorHandler = false
  settings.fallbackHookScriptErrors = false

  local minimap = type(settings.minimap) == "table" and settings.minimap or {}
  NormalizeBoolean(minimap, "hide", false)
  ClampNumber(minimap, "minimapPos", 225, 0, 360, false)
  settings.minimap = { hide = minimap.hide, minimapPos = minimap.minimapPos }
  settings.minimapHide = settings.minimap.hide
  settings.minimapAngle = settings.minimap.minimapPos

  settings.uiFrames = CompactTable(settings.uiFrames, {
    maxDepth = 3, maxEntries = 64, maxNodes = 300,
    maxStringBytes = 256, maxTotalBytes = 32 * 1024,
  })
  settings.uiPanes = CompactTable(settings.uiPanes, {
    maxDepth = 3, maxEntries = 128, maxNodes = 500,
    maxStringBytes = 256, maxTotalBytes = 32 * 1024,
  })
  settings.uiGroupGridCols = CompactTable(settings.uiGroupGridCols, {
    maxDepth = 2, maxEntries = 16, maxNodes = 32,
    maxStringBytes = 64, maxTotalBytes = 4096,
  })
  settings._validationPassLog = CompactTable(settings._validationPassLog, {
    maxDepth = 4, maxEntries = 80, maxNodes = 300,
    maxStringBytes = 512, maxTotalBytes = 16 * 1024,
  })
  local reloadLoop = CompactDiagnostic(settings._reloadLoop, {
    maxDepth = 2, maxEntries = 8, maxNodes = 16,
    maxStringBytes = 64, maxTotalBytes = 2048,
  })
  settings._reloadLoop = type(reloadLoop) == "table" and reloadLoop or nil
end

local function CompactOrigin(value)
  if type(value) ~= "table" then return nil end
  local addon = TruncateString(value.addon, 128, nil)
  local file = TruncateString(value.file, 1024, nil)
  local line = FiniteNumber(value.line) and math.floor(value.line) or nil
  if addon == nil and file == nil and line == nil then return nil end
  return { addon = addon, file = file, line = line }
end

local function CompactOccurrence(entry)
  if type(entry) ~= "table" then return nil end
  return {
    ts = FiniteNumber(entry.ts) and entry.ts or 0,
    sessionId = FiniteNumber(entry.sessionId) and math.floor(entry.sessionId) or nil,
    kind = TruncateString(entry.kind, 64, "INTEGRATION"),
    addon = TruncateString(entry.addon, 128, "<?>"),
    func = TruncateString(entry.func, 512, "<?>"),
    sig = TruncateString(entry.sig, GROUP_SIGNATURE_BYTES, nil),
    message = TruncateString(entry.message, OCCURRENCE_MESSAGE_BYTES,
      "<invalid persisted message>"),
    stack = TruncateString(entry.stack, OCCURRENCE_STACK_BYTES, ""),
    origin = CompactOrigin(entry.origin),
    compact = true,
  }
end

local function NormalizeGroupFields(group, settings)
  if type(group) ~= "table" then return end
  if not FiniteNumber(group.count) or group.count < 0 then group.count = 0 end
  group.count = math.floor(group.count)
  if not FiniteNumber(group.firstSeen) then group.firstSeen = 0 end
  if not FiniteNumber(group.lastSeen) then group.lastSeen = group.firstSeen end
  group.firstSessionId = FiniteNumber(group.firstSessionId) and math.floor(group.firstSessionId) or nil
  group.lastSessionId = FiniteNumber(group.lastSessionId) and math.floor(group.lastSessionId) or nil
  group.kind = TruncateString(group.kind, 64, "INTEGRATION")
  group.addon = TruncateString(group.addon, 128, "<?>")
  group.func = TruncateString(group.func, 512, "<?>")
  group.message = TruncateString(group.message, GROUP_MESSAGE_BYTES,
    "<invalid persisted message>")
  group.stack = TruncateString(group.stack, GROUP_STACK_BYTES, "")

  local localsMaximum = type(settings) == "table" and settings.maxLocalsSize or 8192
  if type(group.locals) == "string" then
    group.locals = TruncateString(group.locals, localsMaximum, nil)
  elseif group.locals ~= nil then
    group.locals = "<structured locals omitted from persistence>"
  end

  group.origin = CompactOrigin(group.origin)
  group.sys = CompactDiagnostic(group.sys, {
    maxDepth = 4, maxEntries = 80, maxNodes = 500,
    maxStringBytes = 4096, maxTotalBytes = 64 * 1024,
  })
  group.ctx = CompactDiagnostic(group.ctx, {
    maxDepth = 5, maxEntries = 120, maxNodes = 800,
    maxStringBytes = 4096, maxTotalBytes = 96 * 1024,
  })
  group.bus = CompactDiagnostic(group.bus, {
    maxDepth = 5, maxEntries = 160, maxNodes = 1000,
    maxStringBytes = 8192, maxTotalBytes = 128 * 1024,
  })
  group.pinned = group.pinned == true
  group.ignored = group.ignored == true
end

local function NormalizeGroups(db)
  local groups = db.groups
  if type(groups) ~= "table" then
    db.groups = {}
    return
  end

  local maximumOccurrences = db.settings.maxOccurrencesPerGroup
  for signature, group in pairs(groups) do
    if type(signature) ~= "string" or signature == "" or #signature > GROUP_SIGNATURE_BYTES
        or type(group) ~= "table" then
      groups[signature] = nil
    else
      group.sig = signature
      NormalizeGroupFields(group, db.settings)

      local source = type(group.occurrences) == "table" and group.occurrences or {}
      local occurrences = {}
      for index = 1, math.min(#source, maximumOccurrences) do
        local entry = CompactOccurrence(source[index])
        if entry then occurrences[#occurrences + 1] = entry end
      end
      group.occurrences = occurrences
      if group.count < #occurrences then group.count = #occurrences end
    end
  end

  local count, candidates = 0, {}
  for signature, group in pairs(groups) do
    count = count + 1
    candidates[#candidates + 1] = {
      signature = signature,
      pinned = group.pinned == true,
      lastSeen = FiniteNumber(group.lastSeen) and group.lastSeen or 0,
    }
  end
  table.sort(candidates, function(a, b)
    if a.pinned ~= b.pinned then return a.pinned == false end
    if a.lastSeen == b.lastSeen then return a.signature < b.signature end
    return a.lastSeen < b.lastSeen
  end)
  local removeCount = math.max(0, count - db.settings.maxGroups)
  for index = 1, math.min(removeCount, #candidates) do
    groups[candidates[index].signature] = nil
  end
end

local function NormalizeSession(session)
  if type(session) ~= "table" or not FiniteNumber(session.id) then return nil end
  session.id = math.floor(session.id)
  if session.id < 0 then return nil end

  DropUnknownFields(session, SESSION_FIELDS)
  session.started = FiniteNumber(session.started) and session.started or 0
  session.ended = FiniteNumber(session.ended) and session.ended or nil
  if type(session.build) == "string" then
    session.build = TruncateString(session.build, 64, nil)
  elseif not FiniteNumber(session.build) then
    session.build = nil
  end
  session.character = TruncateString(session.character, 256, "?")
  session.class = TruncateString(session.class, 64, nil)
  session.spec = TruncateString(session.spec, 128, nil)

  for index = 1, #SESSION_COUNTERS do
    local key = SESSION_COUNTERS[index]
    local value = session[key]
    if not FiniteNumber(value) or value < 0 then value = 0 end
    session[key] = math.floor(value)
  end
  return session
end

local function NormalizeSessions(db)
  if type(db.sessions) ~= "table" then db.sessions = {} end
  local sessions, validIds = {}, {}
  for index = 1, math.min(#db.sessions, MAX_SESSIONS) do
    local session = NormalizeSession(db.sessions[index])
    if session and not validIds[session.id] then
      sessions[#sessions + 1] = session
      validIds[session.id] = true
    end
  end
  db.sessions = sessions

  local sourceIndex = type(db.sessionIndex) == "table" and db.sessionIndex or {}
  local normalizedIndex = {}
  for sessionId in pairs(validIds) do
    local source = sourceIndex[sessionId] or sourceIndex[tostring(sessionId)]
    local target = { __meta = { n = 0 } }
    if type(source) == "table" then
      local records = {}
      for signature, record in pairs(source) do
        if signature ~= "__meta" and type(signature) == "string"
            and #signature <= GROUP_SIGNATURE_BYTES
            and type(record) == "table" and type(db.groups[signature]) == "table" then
          local count = FiniteNumber(record.count) and math.max(0, math.floor(record.count)) or 0
          records[#records + 1] = {
            signature = signature,
            record = {
              count = count,
              firstSeen = FiniteNumber(record.firstSeen) and record.firstSeen or 0,
              lastSeen = FiniteNumber(record.lastSeen) and record.lastSeen or 0,
              kind = TruncateString(record.kind, 64, db.groups[signature].kind),
              addon = TruncateString(record.addon, 128, db.groups[signature].addon),
            },
          }
        end
      end
      table.sort(records, function(a, b)
        if a.record.lastSeen == b.record.lastSeen then return a.signature < b.signature end
        return a.record.lastSeen > b.record.lastSeen
      end)
      for index = 1, math.min(#records, db.settings.maxGroups) do
        local item = records[index]
        target[item.signature] = item.record
        target.__meta.n = target.__meta.n + 1
      end
    end
    normalizedIndex[sessionId] = target
  end
  db.sessionIndex = normalizedIndex
end

local function NormalizePersistence(value)
  if type(value) ~= "table" then return nil end
  return {
    event = TruncateString(value.event, 64, nil),
    lastFailureAt = FiniteNumber(value.lastFailureAt) and value.lastFailureAt or nil,
    recovery = TruncateString(value.recovery, 64, nil),
    writesSuspendedForSession = value.writesSuspendedForSession == true,
  }
end

local function NormalizeRoot(db)
  DropUnknownFields(db, ROOT_FIELDS)
  db.persistence = NormalizePersistence(db.persistence)
end

local function PrepareRawDatabase()
  if type(_G.RothDevLibDB) ~= "table" then _G.RothDevLibDB = {} end
  local db = _G.RothDevLibDB
  NormalizeRoot(db)
  if type(db.settings) ~= "table" then db.settings = {} end
  if type(db.groups) ~= "table" then db.groups = {} end
  if type(db.sessions) ~= "table" then db.sessions = {} end
  if type(db.sessionIndex) ~= "table" then db.sessionIndex = {} end
  if type(db.ignore) ~= "table" then db.ignore = { sig = {}, addon = {} } end
  if type(db.ignore.sig) ~= "table" then db.ignore.sig = {} end
  if type(db.ignore.addon) ~= "table" then db.ignore.addon = {} end

  NormalizeSettings(db.settings)
  NormalizeGroups(db)
  NormalizeSessions(db)
  return db
end

local function NormalizeDatabase(self)
  local db = self.raw
  if type(db) ~= "table" then return false end
  if self._normalizedRoot == db then return true end
  NormalizeRoot(db)
  if type(db.settings) ~= "table" then db.settings = {} end
  NormalizeSettings(db.settings)
  NormalizeGroups(db)
  NormalizeSessions(db)
  db._schema = SCHEMA
  self._normalizedRoot = db
  return true
end

local function HardTrimRuntimeGroups(self)
  local db = self.raw
  if type(db) ~= "table" or type(db.groups) ~= "table" then return end
  local settings = type(db.settings) == "table" and db.settings or {}
  local maximum = tonumber(settings.maxGroups) or 200
  if maximum < 10 then maximum = 10 elseif maximum > 5000 then maximum = 5000 end

  local candidates = {}
  for signature, group in pairs(db.groups) do
    if type(signature) == "string" and #signature <= GROUP_SIGNATURE_BYTES
        and type(group) == "table" then
      candidates[#candidates + 1] = {
        signature = signature,
        pinned = group.pinned == true,
        lastSeen = FiniteNumber(group.lastSeen) and group.lastSeen or 0,
      }
    else
      db.groups[signature] = nil
    end
  end
  if #candidates <= maximum then return end

  table.sort(candidates, function(a, b)
    if a.pinned ~= b.pinned then return a.pinned == false end
    if a.lastSeen == b.lastSeen then return a.signature < b.signature end
    return a.lastSeen < b.lastSeen
  end)
  local removeCount = #candidates - maximum
  for index = 1, removeCount do
    local signature = candidates[index].signature
    db.groups[signature] = nil
    if type(self._RemoveSigFromAllSessionIndexes) == "function" then
      self:_RemoveSigFromAllSessionIndexes(signature)
    end
  end
end

local function IsOwnAddon(addonName)
  return type(addonName) == "string"
    and (addonName == RDL.addonName or addonName == RDL.name or addonName == "!RothDevLib")
end

local function EmergencyCompact(db)
  if type(db) ~= "table" then return false end
  NormalizeRoot(db)
  if type(db.settings) ~= "table" then db.settings = {} end
  if type(db.groups) ~= "table" then db.groups = {} end
  if type(db.sessions) ~= "table" then db.sessions = {} end
  if type(db.sessionIndex) ~= "table" then db.sessionIndex = {} end

  NormalizeSettings(db.settings)
  db.settings.maxGroups = math.min(db.settings.maxGroups, FAILURE_MAX_GROUPS)
  db.settings.maxOccurrencesPerGroup = 1
  db.settings.maxLocalsSize = math.min(db.settings.maxLocalsSize, 2048)
  db.settings.captureLocals = false

  local candidates = {}
  for signature, group in pairs(db.groups) do
    if type(signature) == "string" and #signature <= GROUP_SIGNATURE_BYTES
        and type(group) == "table" then
      candidates[#candidates + 1] = {
        signature = signature,
        pinned = group.pinned == true,
        lastSeen = FiniteNumber(group.lastSeen) and group.lastSeen or 0,
      }
    else
      db.groups[signature] = nil
    end
  end
  table.sort(candidates, function(a, b)
    if a.pinned ~= b.pinned then return a.pinned == true end
    if a.lastSeen == b.lastSeen then return a.signature < b.signature end
    return a.lastSeen > b.lastSeen
  end)

  local keep = {}
  for index = 1, math.min(#candidates, FAILURE_MAX_GROUPS) do
    keep[candidates[index].signature] = true
  end
  for signature, group in pairs(db.groups) do
    if not keep[signature] then
      db.groups[signature] = nil
    else
      NormalizeGroupFields(group, db.settings)
      group.message = TruncateString(group.message, FAILURE_MESSAGE_BYTES,
        "<invalid persisted message>")
      group.stack = TruncateString(group.stack, FAILURE_STACK_BYTES, "")
      group.locals = nil
      group.sys = nil
      group.ctx = nil
      group.bus = nil
      group.occurrences = {}
    end
  end

  while #db.sessions > FAILURE_MAX_SESSIONS do table.remove(db.sessions) end
  NormalizeSessions(db)
  db._schema = SCHEMA
  db.persistence = {
    event = "SAVED_VARIABLES_TOO_LARGE",
    lastFailureAt = Now(),
    recovery = "emergency-compaction",
    writesSuspendedForSession = true,
  }
  return true
end

function DB:MarkPlayerReady()
  self._playerReady = true
end

function DB:Init()
  if not self._playerReady then return false end
  if not self:IsReady() then
    PrepareRawDatabase()
    local ok, result = pcall(OriginalInit, self)
    if not ok then error(result, 0) end
  end
  return NormalizeDatabase(self) and self:IsReady()
end

function DB:EnsureReady()
  if not self._playerReady then return false end
  if not self:IsReady() then
    local ok, ready = pcall(OriginalEnsureReady, self)
    if not ok or ready ~= true then return false end
  end
  return NormalizeDatabase(self) and true
end

function DB:IsWriteSuspended()
  return self._writesSuspended == true
end

function DB:HandlePersistenceFailure(addonName)
  if not IsOwnAddon(addonName) then return false end
  local db = type(self.raw) == "table" and self.raw or _G.RothDevLibDB
  if not EmergencyCompact(db) then return false end

  self._writesSuspended = true
  self._persistenceFailure = db.persistence
  if type(_G.print) == "function" and not self._persistenceFailureNotified then
    self._persistenceFailureNotified = true
    pcall(_G.print,
      "|cffff3333RothDevLib|r SavedVariables exceeded the client limit. "
      .. "History was compacted and capture is paused for this session. "
      .. "Use |cffffff00/rdev clear|r, then |cffffff00/reload|r.")
  end
  return true
end

-- Early entries captured before PLAYER_LOGIN have no session identity. Bind them
-- to the first real player session only when they are finally committed.
function DB:UpsertGroup(entry)
  if self._writesSuspended then return nil end
  if type(entry) ~= "table" or type(entry.sig) ~= "string"
      or entry.sig == "" or #entry.sig > GROUP_SIGNATURE_BYTES then
    return nil
  end
  if entry.sessionId == nil and self.sessionId ~= nil then entry.sessionId = self.sessionId end

  local group = OriginalUpsertGroup(self, entry)
  if type(group) == "table" then
    group.sig = entry.sig
    NormalizeGroupFields(group, self.raw and self.raw.settings)
    if type(group.occurrences) == "table" then
      group.occurrences[1] = CompactOccurrence(entry)
    end
  end
  HardTrimRuntimeGroups(self)
  if type(self.raw) == "table" and type(self.raw.groups) == "table" then
    return self.raw.groups[entry.sig]
  end
  return group
end

if type(OriginalClear) == "function" then
  function DB:Clear()
    self._writesSuspended = false
    self._persistenceFailure = nil
    self._persistenceFailureNotified = nil
    local db = type(self.raw) == "table" and self.raw or _G.RothDevLibDB
    if type(db) == "table" then db.persistence = nil end
    self._normalizedRoot = nil
    return OriginalClear(self)
  end
end
