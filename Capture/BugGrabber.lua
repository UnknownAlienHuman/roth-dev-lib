-- !RothDevLib/Capture/BugGrabber.lua
-- Bounded fallback importer for BugGrabberDB when another addon owns the
-- global error handler.

local RDL = _G.RothDevLib
local Capture = RDL and RDL.Capture
if not Capture then return end

local Bug = {
  _enabled = false,
  _ticker = nil,
  _counterByKey = {},
  _touchByKey = {},
  _generation = 0,
  _droppedCounterKeys = 0,
  _baselineComplete = false,
  _historyMode = nil,
}
Capture.BugGrabber = Bug

local function Settings()
  if RDL.DB and type(RDL.DB.GetSettings) == "function" then
    local ok, value = pcall(RDL.DB.GetSettings, RDL.DB)
    if ok and type(value) == "table" then return value end
  end
  return {}
end

local function Scrub(value)
  local util = RDL.Util
  if util and type(util.Scrub) == "function" then
    local ok, ordinary = pcall(util.Scrub, util, value)
    if ok then return ordinary end
    return nil
  end
  return value
end

local function SafeText(value, fallback, maximum)
  local util = RDL.Util
  local text = fallback or ""
  if util and type(util.SafeToString) == "function" then
    local ok, rendered = pcall(util.SafeToString, util, value)
    if ok and type(rendered) == "string" then text = rendered end
  else
    local ordinary = Scrub(value)
    if type(ordinary) == "string" then text = ordinary end
  end
  if util and type(util.FilterSecretEscapes) == "function" then
    local ok, filtered = pcall(util.FilterSecretEscapes, util, text)
    if ok and type(filtered) == "string" then text = filtered end
  end
  maximum = tonumber(maximum) or 64 * 1024
  if #text > maximum then text = text:sub(1, maximum) .. "<truncated>" end
  return text
end

local function SafeCopy(value)
  local util = RDL.Util
  if util and type(util.CopyDiagnosticValue) == "function" then
    local ok, copy = pcall(util.CopyDiagnosticValue, util, value, {
      maxDepth = 4,
      maxEntries = 80,
      maxNodes = 500,
      maxStringBytes = 8192,
      maxTotalBytes = 128 * 1024,
    })
    if ok then return copy end
  end
  return nil
end

local function IsReadableTable(value)
  local ordinary = Scrub(value)
  if type(ordinary) ~= "table" then return nil end
  if type(_G.issecrettable) == "function" then
    local ok, secret = pcall(_G.issecrettable, ordinary)
    if not ok or secret then return nil end
  end
  if type(_G.canaccesstable) == "function" then
    local ok, accessible = pcall(_G.canaccesstable, ordinary)
    if not ok or not accessible then return nil end
  end
  return ordinary
end

local function SafeGet(tbl, key)
  tbl = IsReadableTable(tbl)
  if not tbl then return nil end
  local ok, value = pcall(rawget, tbl, key)
  if not ok then return nil end
  return Scrub(value)
end

local function First(tbl, ...)
  for index = 1, select("#", ...) do
    local value = SafeGet(tbl, select(index, ...))
    if value ~= nil then return value end
  end
  return nil
end

local function GetBugDB()
  return IsReadableTable(_G.BugGrabberDB)
end

local function GetErrorList(db)
  if not db then return nil end
  local list = IsReadableTable(First(db, "errors", "error", "errs"))
  if list then return list end
  if SafeGet(db, 1) ~= nil then return db end
  return nil
end

local function SafeNumber(value, fallback, minimum, maximum)
  local ordinary = Scrub(value)
  if type(ordinary) ~= "number" then return fallback end
  if ordinary ~= ordinary or ordinary == math.huge or ordinary == -math.huge then return fallback end
  if ordinary < minimum then return minimum end
  if ordinary > maximum then return maximum end
  return ordinary
end

-- Do not use #list: BugGrabberDB is foreign input and a hostile __len
-- metamethod must never run inside the fallback importer. Scan raw positive
-- integer keys once and cap the index window at the configured maximum.
-- Returns: count, pruneSafe, baselineSafe.
local function ListBounds(list, maximum)
  list = IsReadableTable(list)
  if not list then return 0, false, false end

  local largest, scanned, rawKey = 0, 0, nil
  while true do
    local ok, nextKey = pcall(next, list, rawKey)
    if not ok then return largest, false, false end
    if nextKey == nil then return largest, true, true end

    rawKey = nextKey
    scanned = scanned + 1
    if scanned > maximum then
      -- We can safely baseline the bounded numeric window, but cannot prove
      -- that every foreign key was observed, so stale-key pruning is unsafe.
      return maximum, false, true
    end

    local ordinaryKey = Scrub(nextKey)
    if type(ordinaryKey) == "number" and ordinaryKey >= 1
        and ordinaryKey % 1 == 0 and ordinaryKey <= maximum
        and ordinaryKey > largest then
      largest = ordinaryKey
    end
  end
end

local function NormalizeRecord(raw)
  local ordinary = Scrub(raw)
  local valueType = type(ordinary)
  if valueType == "string" then
    local message = SafeText(ordinary, "", 64 * 1024)
    if message == "" or message == "<inaccessible>" or message == "<secret>" then return nil end
    return { message = message, counter = 1 }
  end
  if valueType ~= "table" or not IsReadableTable(ordinary) then return nil end

  local message = SafeText(First(ordinary, "message", "msg", "error", 1), "", 64 * 1024)
  if message == "" or message == "nil" then return nil end

  local stack = SafeText(First(ordinary, "stack", "traceback", "trace", 2), "", 128 * 1024)
  if stack == "nil" then stack = "" end

  return {
    message = message,
    stack = stack,
    locals = SafeCopy(First(ordinary, "locals", "localVariables")),
    ts = SafeNumber(First(ordinary, "time", "ts", "when"), nil, 0, 2 ^ 53),
    counter = math.floor(SafeNumber(SafeGet(ordinary, "counter"), 1, 1, 1000000)),
    session = SafeCopy(SafeGet(ordinary, "session")),
  }
end

-- Use the same bounded logical signature family as RothDevLib grouping. Never
-- retain the complete external message+stack as a long-lived table key.
local function RecordKey(record)
  local util = RDL.Util
  if util and type(util.MakeSignature) == "function" then
    local ok, signature = pcall(util.MakeSignature, util,
      "LUA_ERROR", record.message, record.stack)
    if ok and type(signature) == "string" and signature ~= "" then
      return SafeText(signature, "", 4096)
    end
  end
  return SafeText(record.message, "", 2048)
    .. "\031" .. SafeText(record.stack, "", 4096)
end

local function ResetAttachment(self)
  self._counterByKey = {}
  self._touchByKey = {}
  self._generation = 0
  self._droppedCounterKeys = 0
  self._baselineComplete = false
  self._historyMode = nil
end

local function TouchCounter(self, key, counter, generation)
  self._counterByKey[key] = counter
  self._touchByKey[key] = generation
end

local function RemoveCounter(self, key)
  self._counterByKey[key] = nil
  self._touchByKey[key] = nil
end

local function TrimCounterState(self, maximum, protected)
  maximum = math.floor(SafeNumber(maximum, 5000, 1, 20000))
  local candidates = {}
  for key in pairs(self._counterByKey) do
    candidates[#candidates + 1] = {
      key = key,
      touched = tonumber(self._touchByKey[key]) or 0,
      protected = protected and protected[key] == true or false,
    }
  end
  local excess = #candidates - maximum
  if excess <= 0 then return 0 end

  table.sort(candidates, function(a, b)
    if a.protected ~= b.protected then return a.protected == false end
    if a.touched == b.touched then return a.key < b.key end
    return a.touched < b.touched
  end)

  local removed = 0
  for index = 1, #candidates do
    if removed >= excess then break end
    RemoveCounter(self, candidates[index].key)
    removed = removed + 1
  end
  self._droppedCounterKeys = (tonumber(self._droppedCounterKeys) or 0) + removed
  return removed
end

function Bug:IsPresent()
  if GetBugDB() ~= nil then return true end
  local direct = Scrub(_G.BugGrabber)
  return direct ~= nil and direct ~= "<inaccessible>" and direct ~= "<secret>"
end

function Bug:Disable()
  self._enabled = false
  local ticker = self._ticker
  self._ticker = nil
  if ticker and type(ticker.Cancel) == "function" then pcall(ticker.Cancel, ticker) end
  ResetAttachment(self)
end

function Bug:Enable()
  if self._enabled and self._ticker then return true end
  ResetAttachment(self)

  local timer = _G.C_Timer
  if type(timer) ~= "table" or type(timer.NewTicker) ~= "function" then
    self._enabled = false
    return false
  end

  local interval = SafeNumber(Settings().bugGrabberPollSec, 1, 0.25, 60)
  local ok, ticker = pcall(timer.NewTicker, interval, function()
    if Bug._enabled then pcall(Bug.ImportNew, Bug) end
  end)
  if not ok or not ticker then
    self._enabled = false
    self._ticker = nil
    return false
  end

  self._enabled = true
  self._ticker = ticker
  return true
end

function Bug:ImportNew()
  if Capture.ownsHandler then
    self:Disable()
    return 0
  end
  if type(Capture.BuildEntry) ~= "function" or type(Capture.StoreEntry) ~= "function" then return 0 end

  local settings = Settings()
  if settings.importBugGrabber == false then return 0 end

  local budget = math.floor(SafeNumber(settings.bugGrabberImportMaxPerPoll, 200, 1, 1000))
  local scanMaximum = math.floor(SafeNumber(settings.bugGrabberScanMax, 5000, 1, 20000))
  local importHistory = settings.importBugGrabberHistory == true

  -- A mode transition starts a fresh attachment contract. History mode imports
  -- the current counters; normal mode baselines exactly once, then imports the
  -- first occurrence of every new logical error.
  if self._historyMode ~= importHistory then
    self._historyMode = importHistory
    self._counterByKey = {}
    self._touchByKey = {}
    self._generation = 0
    self._droppedCounterKeys = 0
    self._baselineComplete = importHistory
  end

  local list = GetErrorList(GetBugDB())
  if not list then return 0 end

  self._generation = (tonumber(self._generation) or 0) + 1
  local generation = self._generation
  local count, pruneSafe, baselineSafe = ListBounds(list, scanMaximum)
  local initialBaseline = not importHistory and not self._baselineComplete
  local seen, imported = {}, 0
  local scanCompleted = true
  local throttled = false

  for index = 1, count do
    if budget <= 0 then
      scanCompleted = false
      break
    end
    local record = NormalizeRecord(SafeGet(list, index))
    if record then
      local key = RecordKey(record)
      seen[key] = true
      self._touchByKey[key] = generation

      local previousRaw = self._counterByKey[key]
      if initialBaseline then
        -- Only the initial bounded scan is history. After this scan, an unseen
        -- key is a new error and counter=1 must be imported immediately.
        TouchCounter(self, key, record.counter, generation)
        previousRaw = record.counter
      elseif previousRaw == nil and not importHistory then
        -- Unknown keys after the attach baseline are new, but a source may have
        -- incremented several times between polls. Import one occurrence instead
        -- of replaying the complete foreign counter as history.
        previousRaw = math.max(0, record.counter - 1)
        TouchCounter(self, key, previousRaw, generation)
      end

      local previous = math.floor(SafeNumber(previousRaw, 0, 0, 1000000))
      local delta = record.counter - previous
      if delta > 0 then
        local attempts = math.min(delta, budget)
        for step = 1, attempts do
          local okBuild, entry = pcall(Capture.BuildEntry, "LUA_ERROR", record.message, record.stack,
            record.locals, nil, nil, {
              source = "BugGrabber",
              imported = true,
              bugIndex = index,
              bugTs = record.ts,
              bugSession = record.session,
              bugCounter = record.counter,
              bugCounterImportedFrom = previous,
              bugCounterImportedStep = step,
            })
          if not okBuild or type(entry) ~= "table" then break end

          local okStore, status = pcall(Capture.StoreEntry, entry)
          if not okStore or status == "failed" then break end
          if status == "throttled" then
            throttled = true
            scanCompleted = false
            break
          end
          if status == "stored" or status == "queued" or status == "ignored" then
            imported = imported + 1
            budget = budget - 1
            TouchCounter(self, key, previous + step, generation)
          else
            break
          end
        end
        if throttled then break end
      elseif delta < 0 then
        -- Source rotation/reset: accept the new baseline without replaying.
        TouchCounter(self, key, record.counter, generation)
      end
    end
  end

  if initialBaseline and scanCompleted and baselineSafe then
    self._baselineComplete = true
  end

  if pruneSafe and scanCompleted then
    for key in pairs(self._counterByKey) do
      if not seen[key] then RemoveCounter(self, key) end
    end
  end
  TrimCounterState(self, scanMaximum, seen)
  return imported
end

function Bug:GetStateStats()
  local count = 0
  local maximumKeyBytes = 0
  for key in pairs(self._counterByKey) do
    count = count + 1
    if type(key) == "string" and #key > maximumKeyBytes then maximumKeyBytes = #key end
  end
  return {
    keys = count,
    dropped = tonumber(self._droppedCounterKeys) or 0,
    maximumKeyBytes = maximumKeyBytes,
    generation = tonumber(self._generation) or 0,
  }
end
