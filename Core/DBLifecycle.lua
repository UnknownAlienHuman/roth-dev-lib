-- !RothDevLib/Core/DBLifecycle.lua
-- Separates early SavedVariables availability from player-session readiness and
-- repairs critical persisted limits before capture starts writing.

local RDL = _G.RothDevLib
local DB = RDL and RDL.DB
if not DB then return end

local OriginalInit = DB.Init
local OriginalEnsureReady = DB.EnsureReady
local OriginalUpsertGroup = DB.UpsertGroup

DB._playerReady = false

local function FiniteNumber(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
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

local function NormalizeSettings(settings)
  if type(settings) ~= "table" then return end

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
  ClampNumber(settings, "maxLocalsSize", 8192, 256, 1024 * 1024, true)
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
  NormalizeBoolean(settings, "enablePerfProfiling", true)
  NormalizeBoolean(settings, "memWatchEnabled", false)

  -- Compatibility-first capture policy. Old persisted values must not revive
  -- handler wars or global setter replacement.
  settings.errorHandlerMode = "chain"
  settings.chainCallPrevHandler = true
  settings.maintainOwnership = false
  settings.lockErrorHandler = false
  settings.fallbackHookScriptErrors = false

  if type(settings.minimap) ~= "table" then settings.minimap = {} end
  NormalizeBoolean(settings.minimap, "hide", false)
  ClampNumber(settings.minimap, "minimapPos", 225, 0, 360, false)
  settings.minimapHide = settings.minimap.hide
  settings.minimapAngle = settings.minimap.minimapPos

  if type(settings.uiFrames) ~= "table" then settings.uiFrames = {} end
  if type(settings.uiPanes) ~= "table" then settings.uiPanes = {} end
end

local function NormalizeOccurrence(entry)
  if type(entry) ~= "table" then return nil end
  if not FiniteNumber(entry.ts) then entry.ts = 0 end
  if type(entry.kind) ~= "string" then entry.kind = "INTEGRATION" end
  if type(entry.message) ~= "string" then entry.message = "<invalid persisted message>" end
  if type(entry.stack) ~= "string" then entry.stack = "" end
  if type(entry.addon) ~= "string" then entry.addon = "<?>" end
  if type(entry.func) ~= "string" then entry.func = "<?>" end
  return entry
end

local function NormalizeGroups(db)
  local groups = db.groups
  if type(groups) ~= "table" then
    db.groups = {}
    return
  end

  local maximumOccurrences = db.settings.maxOccurrencesPerGroup
  for signature, group in pairs(groups) do
    if type(signature) ~= "string" or signature == "" or type(group) ~= "table" then
      groups[signature] = nil
    else
      group.sig = signature
      if not FiniteNumber(group.count) or group.count < 0 then group.count = 0 end
      group.count = math.floor(group.count)
      if not FiniteNumber(group.firstSeen) then group.firstSeen = 0 end
      if not FiniteNumber(group.lastSeen) then group.lastSeen = group.firstSeen end
      if type(group.kind) ~= "string" then group.kind = "INTEGRATION" end
      if type(group.addon) ~= "string" then group.addon = "<?>" end
      if type(group.func) ~= "string" then group.func = "<?>" end
      if type(group.message) ~= "string" then group.message = "<invalid persisted message>" end
      if type(group.stack) ~= "string" then group.stack = "" end
      group.pinned = group.pinned == true
      group.ignored = group.ignored == true

      local source = type(group.occurrences) == "table" and group.occurrences or {}
      local occurrences = {}
      for index = 1, math.min(#source, maximumOccurrences) do
        local entry = NormalizeOccurrence(source[index])
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
    -- Preserve pinned groups before ordinary groups, but never let pinning turn
    -- the persistence limit into an unbounded store.
    if a.pinned ~= b.pinned then return a.pinned == false end
    if a.lastSeen == b.lastSeen then return a.signature < b.signature end
    return a.lastSeen < b.lastSeen
  end)
  local removeCount = math.max(0, count - db.settings.maxGroups)
  for index = 1, math.min(removeCount, #candidates) do
    groups[candidates[index].signature] = nil
  end
end

local function NormalizeSessions(db)
  if type(db.sessions) ~= "table" then db.sessions = {} end
  local sessions, validIds = {}, {}
  for index = 1, math.min(#db.sessions, 50) do
    local session = db.sessions[index]
    if type(session) == "table" and FiniteNumber(session.id) then
      session.id = math.floor(session.id)
      if session.id >= 0 and not validIds[session.id] then
        local counters = { "errors", "warnings", "taints", "suppressed", "alerts", "asserts", "throttledCount" }
        for counterIndex = 1, #counters do
          local key = counters[counterIndex]
          if not FiniteNumber(session[key]) or session[key] < 0 then session[key] = 0 end
          session[key] = math.floor(session[key])
        end
        sessions[#sessions + 1] = session
        validIds[session.id] = true
      end
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
            and type(record) == "table" and type(db.groups[signature]) == "table" then
          local count = FiniteNumber(record.count) and math.max(0, math.floor(record.count)) or 0
          records[#records + 1] = {
            signature = signature,
            record = {
              count = count,
              firstSeen = FiniteNumber(record.firstSeen) and record.firstSeen or 0,
              lastSeen = FiniteNumber(record.lastSeen) and record.lastSeen or 0,
              kind = type(record.kind) == "string" and record.kind or db.groups[signature].kind,
              addon = type(record.addon) == "string" and record.addon or db.groups[signature].addon,
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

local function PrepareRawDatabase()
  if type(_G.RothDevLibDB) ~= "table" then _G.RothDevLibDB = {} end
  local db = _G.RothDevLibDB
  if type(db.settings) ~= "table" then db.settings = {} end
  if type(db.groups) ~= "table" then db.groups = {} end
  if type(db.sessions) ~= "table" then db.sessions = {} end
  if type(db.sessionIndex) ~= "table" then db.sessionIndex = {} end
  if type(db.ignore) ~= "table" then db.ignore = { sig = {}, addon = {} } end
  if type(db.ignore.sig) ~= "table" then db.ignore.sig = {} end
  if type(db.ignore.addon) ~= "table" then db.ignore.addon = {} end

  -- Bound persisted work before the legacy owner scans sessions or merges
  -- defaults. This remains player-independent and does not create a session.
  NormalizeSettings(db.settings)
  NormalizeGroups(db)
  NormalizeSessions(db)
  return db
end

local function NormalizeDatabase(self)
  local db = self.raw
  if type(db) ~= "table" then return false end
  if self._normalizedRoot == db then return true end
  if type(db.settings) ~= "table" then db.settings = {} end
  NormalizeSettings(db.settings)
  NormalizeGroups(db)
  NormalizeSessions(db)
  db._schema = 4
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
    if type(signature) == "string" and type(group) == "table" then
      candidates[#candidates + 1] = {
        signature = signature,
        pinned = group.pinned == true,
        lastSeen = FiniteNumber(group.lastSeen) and group.lastSeen or 0,
      }
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


-- Early entries captured before PLAYER_LOGIN have no session identity. Bind them
-- to the first real player session only when they are finally committed.
function DB:UpsertGroup(entry)
  if type(entry) == "table" and entry.sessionId == nil and self.sessionId ~= nil then
    entry.sessionId = self.sessionId
  end
  local group = OriginalUpsertGroup(self, entry)
  HardTrimRuntimeGroups(self)
  if type(entry) == "table" and type(entry.sig) == "string"
      and type(self.raw) == "table" and type(self.raw.groups) == "table" then
    return self.raw.groups[entry.sig]
  end
  return group
end
