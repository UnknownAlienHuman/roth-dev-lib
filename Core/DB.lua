-- !RothDevLib/Core/DB.lua
-- SavedVariables database + sessions.
-- FIX B2: removed direct UI call, use only Fire callback.
-- FIX B4: session.ended support via OnShutdown().

local RDL = _G.RothDevLib
local DB = {}
RDL.DB = DB

local DEFAULTS = {
  _schema = 3,
  settings = {
    maxGroups = 200,
    maxOccurrencesPerGroup = 10,
    forwardToDefaultErrorHandler = false,
    -- Error handler strategy
    --  chain: capture errors and optionally call the previous handler (BugGrabber/BugSack/Blizzard).
    --  exclusive: replace handler; optional lockErrorHandler can prevent later overrides.
    errorHandlerMode = "chain",
    chainCallPrevHandler = true,
    -- Maintain ownership if other addons replace the handler after login.
    maintainOwnership = true,
    maintainOwnershipIntervalSec = 4,

    lockErrorHandler = false,
    hideTaintPopups = true,
    hideBlizzardScriptErrors = true,
    minimap = { hide = false, minimapPos = 225 },
    chatNotifyOnError = true,
    chatNotifyThrottleSec = 3,
    -- ChatTap: parse addon-printed error stacks (for addons that swallow errors in wrappers).
    captureChatErrors = true,
    chatTapWindowSec = 0.8,
    chatTapMaxStackLines = 60,
    chatTapHookAllFrames = true,
    chatTapStripColors = true,
    -- Collapse identical chat-stacks within this small time window (seconds).
    -- Set to 0 to disable.
    chatTapDedupSec = 0.6,
    chatTapDedupMax = 200,
    -- Fallback capture when we do not own the global errorhandler (parity with BugGrabber).
    fallbackHookScriptErrors = true,
    scriptErrorsFrameSyncPollSec = 1.0,
    scriptErrorsFrameImportMaxPerPoll = 60,
    importBugGrabber = true,
    bugGrabberPollSec = 1.0,
    bugGrabberImportMaxPerPoll = 200,
    openOnErrorOutOfCombat = false,
    includeBreadcrumbsInErrors = true,
    breadcrumbsPerError = 12,
    maxBreadcrumbsPerAddon = 80,
    -- UI: coalesce refreshes during storms.
    uiRefreshThrottleSec = 0.15,
    metricMinInterval = 1,
    minimapForceShowOnNextLogin = true,
    -- Storm (flood protection)
    stormErrorsPerSec = 60,
    stormWarningsPerSec = 60,
    -- Locals
    maxLocalsSize = 8192, -- 8KB per entry
    captureLocals = true,
    -- Locals calibration: probe a few levels beyond the base level if needed.
    localsProbeMax = 12,
    localsProbeCache = true,
    -- Budget for probing (prevents expensive work during storms even if not throttled).
    localsProbesPerSec = 30,

    -- Phase 3: Perf profiling (CPU/Mem)
    enablePerfProfiling = true,
    -- Sampling rate for CPU profiling wrappers (0..1). Lower = less overhead.
    cpuSampleRate = 0.25,
    -- Alert thresholds
    cpuSpikeMs = 16, -- per-call spike threshold
    cpuAlertMinIntervalMs = 2000,
    memSpikeKB = 64,
    memAlertMinIntervalMs = 2000,
    -- Optional global memory watcher
    memWatchEnabled = false,
    memWatchIntervalSec = 2,
    memWatchSpikeKB = 256,

    -- Monitoring window (UI/Monitor.lua)
    monitorRefreshSec = 1.0,
    monitorTopN = 20,
    monitorMinSamples = 1,

    -- UI window state (position/size) for main/monitor/export frames.
    uiFrames = {},

    -- UI (Stage 3): ScrollBox-based group list.
    -- If disabled or missing APIs/templates, the list degrades to a static message.
    uiUseScrollBoxList = true,

    -- UI (Stage 3.2): persisted GroupGrid column widths (pixels).
    -- Message column is fill-only.
    uiGroupGridCols = { kind = 90, addon = 120, count = 60, last = 70 },
    -- UI (Stage 3.1): prefer Blizzard-like window shell (ButtonFrameTemplate) when available.
    -- Fallback to the legacy BackdropTemplate shell if disabled or missing templates.
    uiUseButtonFrameShell = true,
  },
  sessions = {},
  sessionIndex = {},
  ignore = { sig = {}, addon = {} },
  groups = {},
}

local function Now() return time() end

function DB:Init()
  if self.raw and self.raw.groups then return end

  if type(_G.RothDevLibDB) ~= "table" then
    _G.RothDevLibDB = {}
  end
  local db = _G.RothDevLibDB

  -- Deep copy helper
  local function deepCopy(v, depth)
    depth = depth or 0
    if type(v) ~= "table" then return v end
    if depth > 3 then return {} end
    local t = {}
    for k2, v2 in pairs(v) do t[k2] = deepCopy(v2, depth + 1) end
    return t
  end

  local function merge(dst, src)
    if type(dst) ~= "table" then dst = {} end
    for k, v in pairs(src) do
      if type(v) == "table" then
        if type(dst[k]) ~= "table" then dst[k] = deepCopy(v)
        else dst[k] = merge(dst[k], v) end
      else
        if dst[k] == nil then dst[k] = v end
      end
    end
    return dst
  end

  -- Ensure top-level tables
  if type(db.settings) ~= "table" then db.settings = {} end
  if type(db.groups) ~= "table" then db.groups = {} end
  if type(db.sessions) ~= "table" then db.sessions = {} end
  if type(db.sessionIndex) ~= "table" then db.sessionIndex = {} end
  if type(db.ignore) ~= "table" then db.ignore = { sig = {}, addon = {} } end
  if type(db.ignore.sig) ~= "table" then db.ignore.sig = {} end
  if type(db.ignore.addon) ~= "table" then db.ignore.addon = {} end

  merge(db, DEFAULTS)
  merge(db.settings, DEFAULTS.settings)

  for k, v in pairs(DEFAULTS.settings) do
    if db.settings[k] == nil then db.settings[k] = v end
  end

  -- Schema version
  db._schema = db._schema or 1

  -- Migration: schema 2 (error handler strategy + ownership maintenance)
  if (tonumber(db._schema) or 1) < 2 then
    -- Default to chain mode for better compatibility and capture parity.
    if db.settings.errorHandlerMode == nil then db.settings.errorHandlerMode = "chain" end
    if db.settings.chainCallPrevHandler == nil then db.settings.chainCallPrevHandler = true end
    if db.settings.maintainOwnership == nil then db.settings.maintainOwnership = true end
    if db.settings.maintainOwnershipIntervalSec == nil then db.settings.maintainOwnershipIntervalSec = 4 end
    -- lockErrorHandler is only meaningful in exclusive mode; keep user value as-is.
    db._schema = 2
  end

  -- Migration: schema 3 (per-session index for BugSack-style session filtering)
  if (tonumber(db._schema) or 1) < 3 then
    if type(db.sessionIndex) ~= "table" then db.sessionIndex = {} end
    db._schema = 3
  end

  -- Migration: legacy minimap keys -> LibDBIcon table
  db.settings.minimap = db.settings.minimap or { hide = false, minimapPos = 225 }
  if db.settings.minimap.hide == nil and db.settings.minimapHide ~= nil then
    db.settings.minimap.hide = db.settings.minimapHide
  end
  if db.settings.minimap.minimapPos == nil then
    db.settings.minimap.minimapPos = db.settings.minimapAngle or 225
  end
  db.settings.minimapHide = (db.settings.minimap.hide == true)
  db.settings.minimapAngle = db.settings.minimap.minimapPos or 225

  self.raw = db

  -- Sequential session ID (gap #6 improvement)
  local lastId = 0
  for _, s in ipairs(db.sessions) do
    local id = tonumber(s.id) or 0
    if id > lastId then lastId = id end
  end
  self.sessionId = lastId + 1

  -- Character info for session
  local className, classFile = UnitClass("player")
  local specName, specID = nil, nil
  local specIndex = GetSpecialization and GetSpecialization()
  if specIndex and GetSpecializationInfo then
    specID, specName = GetSpecializationInfo(specIndex)
  end

  self.session = {
    id = self.sessionId,
    started = Now(),
    ended = nil, -- filled on PLAYER_LOGOUT
    build = select(4, GetBuildInfo()),
    character = (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?"),
    class = classFile,
    spec = specName,
    errors = 0,
    warnings = 0,
    taints = 0,
    suppressed = 0,
    alerts = 0,
    asserts = 0,
    throttledCount = 0, -- flood protection counter
  }
  table.insert(db.sessions, 1, self.session)

  -- Per-session index (BugSack-style session filtering)
  if type(db.sessionIndex) ~= "table" then db.sessionIndex = {} end
  local sid = tonumber(self.sessionId) or self.sessionId
  if type(db.sessionIndex[sid]) ~= "table" then
    db.sessionIndex[sid] = { __meta = { n = 0 } }
  else
    if type(db.sessionIndex[sid].__meta) ~= "table" then db.sessionIndex[sid].__meta = { n = 0 } end
    if type(db.sessionIndex[sid].__meta.n) ~= "number" then db.sessionIndex[sid].__meta.n = 0 end
  end

  -- Retain last 50 sessions (and purge their indexes)
  local maxSessions = 50
  while #db.sessions > maxSessions do
    local removed = table.remove(db.sessions)
    if removed and db.sessionIndex then
      db.sessionIndex[tonumber(removed.id) or removed.id] = nil
    end
  end
end

function DB:OnShutdown()
  -- FIX B4: record session end time
  if self.session then
    self.session.ended = Now()
  end
end

function DB:IsReady()
  return self.raw ~= nil and self.raw.groups ~= nil
end

function DB:EnsureReady()
  if self:IsReady() then return true end
  local ok, err = pcall(function() self:Init() end)
  if not ok then
    if RDL and RDL.Log then
      pcall(function() RDL:Log("ERROR", "DB", "DB:Init failed", { err = tostring(err) }) end)
    else
      pcall(function() print("|cffff3333RothDevLib|r DB init failed: " .. tostring(err)) end)
    end

    -- Self-diagnostics: also capture DB init failures (even pre-DB; routed to boot queue).
    if RDL and RDL.Capture and RDL.Capture.OnSuppressedError then
      local stack = ""
      local okS, s = pcall(debugstack, 2, 40, 40)
      if okS then stack = s end
      pcall(function()
        RDL.Capture:OnSuppressedError(err, stack, nil, RDL.addonName, "DB:Init", { internal = true, boot = true })
      end)
    end
  end
  if ok and self:IsReady() and RDL and RDL.Capture and RDL.Capture.FlushBootQueue then
    pcall(function() RDL.Capture:FlushBootQueue() end)
  end
  return ok and self:IsReady()
end

function DB:GetSettings()
  return self.raw and self.raw.settings
end

-- Ignore support
function DB:IsIgnored(sig, addonName, message)
  if not self.raw then return false end
  local ig = self.raw.ignore
  if not ig then return false end
  if sig and ig.sig and ig.sig[sig] then return true end
  if addonName and ig.addon and ig.addon[addonName] then return true end
  return false
end

function DB:ToggleIgnoreSig(sig)
  if not sig or not self.raw then return false end
  self.raw.ignore = self.raw.ignore or { sig = {}, addon = {} }
  self.raw.ignore.sig = self.raw.ignore.sig or {}
  local cur = self.raw.ignore.sig[sig] and true or false
  self.raw.ignore.sig[sig] = not cur
  return self.raw.ignore.sig[sig] and true or false
end

function DB:ToggleIgnoreAddon(addonName)
  if not addonName or addonName == "" or not self.raw then return false end
  self.raw.ignore = self.raw.ignore or { sig = {}, addon = {} }
  self.raw.ignore.addon = self.raw.ignore.addon or {}
  local cur = self.raw.ignore.addon[addonName] and true or false
  self.raw.ignore.addon[addonName] = not cur
  return self.raw.ignore.addon[addonName] and true or false
end

function DB:ClearIgnore()
  if not self.raw then return end
  self.raw.ignore = { sig = {}, addon = {} }
end

local function TrimToMaxGroups(db, maxGroups)
  local groups = db.groups
  local count = 0
  for _ in pairs(groups) do count = count + 1 end
  if count <= maxGroups then return nil end

  local arr = {}
  for sig, g in pairs(groups) do
    if not g.pinned then
      table.insert(arr, { sig = sig, last = g.lastSeen or 0 })
    end
  end
  table.sort(arr, function(a, b) return (a.last or 0) < (b.last or 0) end)

  local toRemove = count - maxGroups
  local removed = {}
  for i = 1, math.min(toRemove, #arr) do
    local sig = arr[i].sig
    groups[sig] = nil
    removed[#removed + 1] = sig
  end
  return removed
end

-- -----------------------------------------------------------------------------
-- Per-session index (BugSack-style session filtering)
-- -----------------------------------------------------------------------------

local function EnsureIndexMeta(idx)
  if type(idx.__meta) ~= "table" then idx.__meta = { n = 0 } end
  if type(idx.__meta.n) ~= "number" then idx.__meta.n = 0 end
  return idx.__meta
end

function DB:_EnsureSessionIndex(sessionId)
  if not self.raw then return nil end
  local db = self.raw
  if type(db.sessionIndex) ~= "table" then db.sessionIndex = {} end

  local sid = tonumber(sessionId) or sessionId
  local idx = db.sessionIndex[sid]
  if type(idx) ~= "table" then
    idx = { __meta = { n = 0 } }
    db.sessionIndex[sid] = idx
  end
  EnsureIndexMeta(idx)
  return idx
end

function DB:_TrimSessionIndex(idx, maxGroups)
  if type(idx) ~= "table" then return end
  local meta = EnsureIndexMeta(idx)

  local n = 0
  local arr = {}
  for sig, v in pairs(idx) do
    if sig ~= "__meta" and type(v) == "table" then
      n = n + 1
      arr[#arr + 1] = { sig = sig, last = tonumber(v.lastSeen or 0) }
    end
  end
  meta.n = n
  if n <= maxGroups then return end

  table.sort(arr, function(a, b) return (a.last or 0) < (b.last or 0) end)
  local toRemove = n - maxGroups
  for i = 1, math.min(toRemove, #arr) do
    idx[arr[i].sig] = nil
    meta.n = math.max(0, (meta.n or 0) - 1)
  end
end

function DB:_RemoveSigFromAllSessionIndexes(sig)
  if not sig or not self.raw or type(self.raw.sessionIndex) ~= "table" then return end
  for _, idx in pairs(self.raw.sessionIndex) do
    if type(idx) == "table" and idx[sig] ~= nil then
      idx[sig] = nil
      if type(idx.__meta) == "table" and type(idx.__meta.n) == "number" then
        idx.__meta.n = math.max(0, idx.__meta.n - 1)
      end
    end
  end
end

function DB:_UpdateSessionIndex(entry)
  if not entry or not entry.sessionId or not entry.sig or not self.raw then return end
  local settings = self:GetSettings() or {}
  local maxGroups = tonumber(settings.maxGroups) or 200

  local idx = self:_EnsureSessionIndex(entry.sessionId)
  if not idx then return end
  local meta = EnsureIndexMeta(idx)

  local sig = entry.sig
  local rec = idx[sig]
  if type(rec) ~= "table" then
    rec = {
      count = 0,
      firstSeen = entry.ts,
      lastSeen = entry.ts,
      kind = entry.kind,
      addon = entry.addon,
    }
    idx[sig] = rec
    meta.n = (meta.n or 0) + 1
  end

  rec.count = (rec.count or 0) + 1
  if not rec.firstSeen or entry.ts < rec.firstSeen then rec.firstSeen = entry.ts end
  rec.lastSeen = entry.ts
  rec.kind = entry.kind or rec.kind
  rec.addon = entry.addon or rec.addon

  if (meta.n or 0) > maxGroups then
    self:_TrimSessionIndex(idx, maxGroups)
  end
end

function DB:UpsertGroup(entry)
  if not self:EnsureReady() then return nil end
  local db = self.raw
  local settings = self:GetSettings()
  local sig = entry.sig
  local g = db.groups[sig]
  if not g then
    g = {
      sig = sig,
      count = 0,
      firstSeen = entry.ts,
      lastSeen = entry.ts,
      firstSessionId = entry.sessionId,
      lastSessionId = entry.sessionId,
      kind = entry.kind,
      addon = entry.addon,
      func = entry.func,
      message = entry.message,
      stack = entry.stack,
      locals = entry.locals, -- NEW: debuglocals output
      sys = entry.sys,
      ctx = entry.ctx,
      origin = entry.origin,
      bus = entry.bus,
      pinned = false,
      ignored = false,
      occurrences = {},
    }
    db.groups[sig] = g
  end

  g.count = (g.count or 0) + 1
  g.lastSeen = entry.ts
  g.lastSessionId = entry.sessionId
  g.kind = entry.kind or g.kind
  g.addon = entry.addon or g.addon
  g.func = entry.func or g.func
  g.message = entry.message or g.message
  g.stack = entry.stack or g.stack
  g.locals = entry.locals or g.locals
  g.sys = entry.sys or g.sys
  g.ctx = entry.ctx or g.ctx
  g.origin = entry.origin or g.origin
  g.bus = entry.bus or g.bus

  -- Occurrence ring buffer
  local occ = g.occurrences
  table.insert(occ, 1, entry)
  local maxOcc = settings.maxOccurrencesPerGroup or 10
  while #occ > maxOcc do table.remove(occ) end
  -- FIX B2+: Only fire callback, no direct UI call.
  -- IMPORTANT: callback errors are captured (Integration\Callbacks.lua) and the failing callback is disabled.
  if type(RDL.Fire) == "function" then
    RDL:Fire("RDL_CAPTURE", entry, g)
  end

  -- Update per-session index (enables BugSack-style session filtering)
  self:_UpdateSessionIndex(entry)

  -- Trim global groups and purge stale session index references for removed signatures.
  local removed = TrimToMaxGroups(db, settings.maxGroups or 200)
  if removed and #removed > 0 then
    for i = 1, #removed do
      self:_RemoveSigFromAllSessionIndexes(removed[i])
    end
  end
  return g
end

function DB:Clear()
  if not self.raw then return end
  -- Clear captured data, but KEEP settings/ignore.
  self.raw.groups = {}
  self.raw.sessions = {}
  self.raw.sessionIndex = {}
  -- Force a clean re-init to start a fresh session.
  self.raw._schema = tonumber(self.raw._schema) or 3
  self.raw = nil
  self.session = nil
  self.sessionId = nil
  self:Init()
end

function DB:IterGroups()
  if not self.raw then return function() end end
  return pairs(self.raw.groups)
end

function DB:GetGroup(sig)
  return self.raw and self.raw.groups and self.raw.groups[sig]
end

function DB:GetGroupCount()
  if not self.raw or not self.raw.groups then return 0 end
  local n = 0
  for _ in pairs(self.raw.groups) do n = n + 1 end
  return n
end

-- Active groups = groups that are not ignored.
-- Used for status indicators (e.g., minimap icon).
function DB:GetActiveGroupCount()
  if not self.raw or not self.raw.groups then return 0 end
  local n = 0
  for sig, g in pairs(self.raw.groups) do
    -- "Active" means: not ignored by the ignore table.
    -- Do NOT rely on per-group flags, because ignore rules are central and can be toggled at runtime.
    if not self:IsIgnored(sig, g and g.addon, g and g.message) then
      n = n + 1
    end
  end
  return n
end

-- Sessions API (for BugSack-style UI; implemented in Stage D)
function DB:GetSessions()
  return (self.raw and self.raw.sessions) or {}
end

function DB:GetSessionIndex(sessionId)
  if not self.raw or type(self.raw.sessionIndex) ~= "table" then return nil end
  return self.raw.sessionIndex[tonumber(sessionId) or sessionId]
end

function DB:IterSessionGroups(sessionId)
  if not self.raw then return function() end end
  local idx = self:GetSessionIndex(sessionId)
  if type(idx) ~= "table" then return function() end end
  local db = self.raw
  local k = nil
  return function()
    local sig, rec = next(idx, k)
    while sig == "__meta" do
      sig, rec = next(idx, sig)
    end
    k = sig
    if not sig then return nil end
    return sig, (db.groups and db.groups[sig]) or nil, rec
  end
end
