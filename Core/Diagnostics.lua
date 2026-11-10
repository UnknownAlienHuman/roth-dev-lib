-- Session evidence for offline agents. Sampling never changes profiling CVars,
-- inspects protected frames, or runs from the Lua error handler.
local RDL = _G.RothDevLib
if not RDL then return end
local Diagnostics = {}
RDL.Diagnostics = Diagnostics

local INTERVAL = 30
local TOP_STATS, TOP_NATIVE, MAX_ADDONS = 32, 20, 128
local MAX_BUS_ADDONS, CRUMBS_PER_ADDON = 12, 4
local COPY = { maxDepth = 8, maxEntries = 256, maxNodes = 6000,
  maxStringBytes = 8192, maxTotalBytes = 256 * 1024 }
local SCALAR = { maxDepth = 1, maxEntries = 4, maxNodes = 8,
  maxStringBytes = 512, maxTotalBytes = 2048 }

local function Copy(value, options)
  local util = RDL.Util
  if not (util and type(util.CopyDiagnosticValue) == "function") then return nil end
  local ok, result = pcall(util.CopyDiagnosticValue, util, value, options or COPY)
  if ok then return result end
end

local function Read(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return Copy(value, SCALAR) end
end

local function Number(value)
  if type(value) == "number" and value == value
      and value ~= math.huge and value ~= -math.huge then return value end
end

local function Clock()
  return Number(Read(_G.GetTimePreciseSec)) or Number(Read(_G.GetTime)) or 0
end

local function Text(value, maximum)
  if type(value) ~= "string" then return nil end
  return value:sub(1, maximum or 128)
end

local function ModuleSnapshot(module, method, options, ...)
  if not module or type(module[method]) ~= "function" then return nil end
  local ok, result = pcall(module[method], module, ...)
  if ok then return Copy(result, options) end
end

local function TopStats(module)
  local source = ModuleSnapshot(module, "GetStats", {
    maxDepth = 3, maxEntries = 1024, maxNodes = 10000,
    maxStringBytes = 512, maxTotalBytes = 768 * 1024,
  })
  local rows = {}
  if type(source) ~= "table" then return { status = "unavailable", rows = rows } end
  for key, stat in pairs(source) do
    if type(key) == "string" and type(stat) == "table" then
      rows[#rows + 1] = { key = Text(key, 512), n = Number(stat.n),
        total = Number(stat.total), max = Number(stat.max),
        ema = Number(stat.ema), last = Number(stat.last) }
    end
  end
  table.sort(rows, function(a, b)
    if (a.total or 0) == (b.total or 0) then return a.key < b.key end
    return (a.total or 0) > (b.total or 0)
  end)
  local count = #rows
  for index = count, TOP_STATS + 1, -1 do rows[index] = nil end
  return { status = "available", observedKeys = count, omitted = math.max(0, count - #rows),
    sourceTruncated = source.__rdl_truncated, rows = rows }
end

local function NativeProfiler()
  local output = { backend = "C_AddOnProfiler", timeUnit = "ms", countUnit = "ticks",
    scope = "top-recent-addons", limit = TOP_NATIVE, status = "unavailable",
    recentWindow = "60-profiler-ticks-not-seconds", cumulativeWindow = "application-session",
    interpretation = "ranking-not-causality; missing-metrics-are-unavailable-not-zero" }
  local api = _G.C_AddOnProfiler
  local metrics = _G.Enum and _G.Enum.AddOnProfilerMetric
  if type(api) ~= "table" or type(metrics) ~= "table"
      or type(api.GetTopKAddOnsForMetric) ~= "function" then return output end
  local enabled = Read(api.IsEnabled)
  if enabled ~= true then
    output.status = enabled == false and "disabled" or "inaccessible"
    return output
  end
  if type(metrics.RecentAverageTime) ~= "number" then return output end
  local ok, raw = pcall(api.GetTopKAddOnsForMetric, metrics.RecentAverageTime, TOP_NATIVE)
  if not ok then return output end
  local rows = Copy(raw, { maxDepth = 3, maxEntries = TOP_NATIVE, maxNodes = 200,
    maxStringBytes = 128, maxTotalBytes = 16 * 1024 })
  if type(rows) ~= "table" then output.status = "inaccessible"; return output end
  output.status, output.rows = "available", {}
  output.overallRecentMs = Number(Read(api.GetOverallMetric, metrics.RecentAverageTime))
  output.sourceTruncated = rows.__rdl_truncated
  local metricNames = { "SessionAverageTime", "PeakTime", "CountTimeOver5Ms", "CountTimeOver50Ms" }
  for index = 1, TOP_NATIVE do
    local row = rows[index]
    if type(row) == "table" and type(row.addOnName) == "string"
        and row.addOnName ~= "<inaccessible>" and row.addOnName ~= "<secret>"
        and not row.addOnName:find("<truncated>", 1, true) then
      local item = { addon = row.addOnName, RecentAverageTime = Number(row.metricValue) }
      for _, name in ipairs(metricNames) do
        if type(metrics[name]) == "number" then
          item[name] = Number(Read(api.GetAddOnMetric, row.addOnName, metrics[name]))
        end
      end
      output.rows[#output.rows + 1] = item
    end
  end
  output.atLimit = #output.rows == TOP_NATIVE
  return output
end

local function AddonInventory()
  local api = _G.C_AddOns
  local output = { status = "unavailable", limit = MAX_ADDONS, rows = {} }
  if type(api) ~= "table" then return output end
  local count = Number(Read(api.GetNumAddOns))
  if not count or count < 0 then return output end
  count = math.floor(count)
  output.status, output.totalInstalled = "available", count
  output.omitted = math.max(0, count - MAX_ADDONS)
  for index = 1, math.min(count, MAX_ADDONS) do
    local name = Read(api.GetAddOnInfo, index)
    if type(name) == "string" and name ~= "<inaccessible>" and name ~= "<secret>"
        and #name <= 128 then
      -- IsAddOnLoaded returns loadedOrLoading, loaded. Preserve that distinction.
      local loaded
      if type(api.IsAddOnLoaded) == "function" then
        local ok, _, value = pcall(api.IsAddOnLoaded, index)
        if ok then loaded = Copy(value, SCALAR) end
      end
      if type(loaded) ~= "boolean" then loaded = nil end
      output.rows[#output.rows + 1] = { name = name,
        loaded = loaded,
        version = Text(Read(api.GetAddOnMetadata, index, "Version"), 128) }
    end
  end
  return output
end

local function Breadcrumbs()
  local names = ModuleSnapshot(RDL.Bus, "GetAllAddonNames")
  local output = { rows = {}, limit = MAX_BUS_ADDONS, perAddon = CRUMBS_PER_ADDON }
  if type(names) ~= "table" then output.status = "unavailable"; return output end
  output.status = "available"
  output.omittedAddons = math.max(0, #names - MAX_BUS_ADDONS)
  for index = 1, math.min(#names, MAX_BUS_ADDONS) do
    local crumbs = ModuleSnapshot(RDL.Bus, "GetBreadcrumbSnapshot", {
      maxDepth = 3, maxEntries = 8, maxNodes = 80,
      maxStringBytes = 512, maxTotalBytes = 4096,
    }, names[index], CRUMBS_PER_ADDON)
    output.rows[#output.rows + 1] = { addon = names[index], breadcrumbs = crumbs }
  end
  return output
end

function Diagnostics:Checkpoint(reason)
  local db = RDL.DB
  if not db or type(db.SaveDiagnostics) ~= "function" or not db:IsReady()
      or db:IsWriteSuspended() then return false end
  local settings = db:GetSettings() or {}
  if settings.persistDiagnostics == false then return false end
  if self._sampling then return false end
  self._sampling = true
  local started = Clock()
  local ok, saved = pcall(function()
    if self._inventoryDirty or not self._inventory then
      self._inventory = AddonInventory()
      self._inventoryDirty = false
    end
    local capture = RDL.Capture or {}
    local fallback = capture._fallback or {}
    local evidence = {
      schema = 1, ts = Number(Read(_G.time)), clock = started,
      reason = Text(Copy(reason, SCALAR), 64), addonVersion = RDL.version,
      system = ModuleSnapshot(RDL.Util, "SnapshotSys"), addons = self._inventory,
      coverage = {
        handlerOwned = capture.ownsHandler == true,
        hardErrorFallback = fallback.kind or "unavailable",
        chatTapHooked = fallback.chatTapHooked == true,
        bootQueueSize = type(capture._bootQueue) == "table" and #capture._bootQueue or 0,
        intakeAttempts = Copy(capture._intakeStats),
        counterScope = "intake-attempts-including-boot-retries-not-unique-errors",
        registrationErrors = Copy(RDL._eventRegErrors), initWarnings = Copy(RDL._initWarnings),
      },
      wrappedCPU = TopStats(RDL.CPU), wrappedMemory = TopStats(RDL.Mem),
      wrappedWindow = "since-ui-load-or-explicit-profiler-reset",
      cpuSampleRate = Number(settings.cpuSampleRate),
      wrappedCoverage = "instrumented-synchronous-calls-only; CPU samples may be probabilistic",
      wrappedCPUUnit = "ms", wrappedMemoryUnit = "global-Lua-heap-delta-KB-not-addon-retained-memory",
      nativeProfiler = settings.enablePerfProfiling == false
        and { status = "disabled-by-setting" } or NativeProfiler(),
      breadcrumbs = Breadcrumbs(),
      limits = { checkpointIntervalSec = INTERVAL, retainedSessions = 5,
        maxSnapshotBytes = 256 * 1024, wrappedKeysPerKind = TOP_STATS },
    }
    if RDL.Logger and type(RDL.Logger.GetText) == "function" then
      local logOK, text = pcall(RDL.Logger.GetText, RDL.Logger)
      if logOK then
        text = RDL.Util:Scrub(text)
        if type(text) == "string" then evidence.log = text:sub(-8192) end
      end
    end
    if self._session ~= db.session then self._session, self._samples = db.session, {} end
    local sample = { ts = evidence.ts, clock = started,
      fps = Number(Read(_G.GetFramerate)),
      globalLuaHeapKB = Number(ModuleSnapshot(RDL.Mem, "GetKB", SCALAR)),
      nativeOverallRecentMs = evidence.nativeProfiler.overallRecentMs }
    self._samples[#self._samples + 1] = sample
    if #self._samples > 60 then table.remove(self._samples, 1) end
    evidence.samples = self._samples
    evidence.collectionBeforePersistenceMs = math.max(0, Clock() - started) * 1000
    return db:SaveDiagnostics(evidence)
  end)
  self._sampling = false
  self._lastCheckpointOK = ok and saved == true
  if not ok and type(RDL.Log) == "function" then
    pcall(RDL.Log, RDL, "ERROR", "DIAGNOSTICS", "Checkpoint failed", Copy(saved, SCALAR))
  end
  return self._lastCheckpointOK
end

function Diagnostics:Init()
  self:Stop()
  self._inventoryDirty = true
  if RDL.DB and (RDL.DB:GetSettings() or {}).persistDiagnostics == false then return end
  self:Checkpoint("login")
  local timers = _G.C_Timer
  if type(timers) ~= "table" or type(timers.NewTicker) ~= "function" then return end
  local generation = self._generation
  local ok, ticker = pcall(timers.NewTicker, INTERVAL, function()
    if self._generation == generation then self:Checkpoint("periodic") end
  end)
  if ok then self._ticker = ticker end
end

function Diagnostics:Stop()
  self._generation = (self._generation or 0) + 1
  local ticker = self._ticker
  self._ticker = nil
  if ticker and type(ticker.Cancel) == "function" then pcall(ticker.Cancel, ticker) end
end
