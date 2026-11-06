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

-- BugGrabber counters are attached to a logical error, not to its current list
-- index. A stable content key survives list reordering and compaction.
local function RecordKey(record)
  return record.message .. "\031" .. (record.stack or "")
end

local function ResetAttachment(self)
  self._counterByKey = {}
  self._baselineComplete = false
  self._historyMode = nil
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
    self._baselineComplete = importHistory
  end

  local list = GetErrorList(GetBugDB())
  if not list then return 0 end

  local count, pruneSafe, baselineSafe = ListBounds(list, scanMaximum)
  local initialBaseline = not importHistory and not self._baselineComplete
  local seen, imported = {}, 0
  local scanCompleted = true

  for index = 1, count do
    if budget <= 0 then
      scanCompleted = false
      break
    end
    local record = NormalizeRecord(SafeGet(list, index))
    if record then
      local key = RecordKey(record)
      seen[key] = true

      local previousRaw = self._counterByKey[key]
      if initialBaseline then
        -- Only the initial bounded scan is history. After this scan, an unseen
        -- key is a new error and counter=1 must be imported immediately.
        self._counterByKey[key] = record.counter
        previousRaw = record.counter
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
          if status == "throttled" then return imported end
          if status == "stored" or status == "queued" or status == "ignored" then
            imported = imported + 1
            budget = budget - 1
            self._counterByKey[key] = previous + step
          else
            break
          end
        end
      elseif delta < 0 then
        -- Source rotation/reset: accept the new baseline without replaying.
        self._counterByKey[key] = record.counter
      end
    end
  end

  if initialBaseline and scanCompleted and baselineSafe then
    self._baselineComplete = true
  end

  if pruneSafe and scanCompleted then
    for key in pairs(self._counterByKey) do
      if not seen[key] then self._counterByKey[key] = nil end
    end
  end
  return imported
end
