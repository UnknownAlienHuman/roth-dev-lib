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
  if not IsReadableTable(tbl) then return nil end
  local ok, value = pcall(function() return tbl[key] end)
  if not ok then return nil end
  return Scrub(value)
end

local function First(tbl, ...)
  for i = 1, select("#", ...) do
    local value = SafeGet(tbl, select(i, ...))
    if value ~= nil then return value end
  end
  return nil
end

local function GetBugDB()
  return IsReadableTable(_G.BugGrabberDB)
end

local function GetErrorList(db)
  if not db then return nil end
  local list = First(db, "errors", "error", "errs")
  list = IsReadableTable(list)
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

local function ListLength(list, maximum)
  local length = 0
  local ok, value = pcall(function() return #list end)
  if ok and type(value) == "number" then
    length = math.floor(value)
  else
    for i = 1, maximum do
      if SafeGet(list, i) == nil then break end
      length = i
    end
  end
  if length < 0 then return 0 end
  if length > maximum then return maximum end
  return length
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

  local rawStack = First(ordinary, "stack", "traceback", "trace", 2)
  local stack = SafeText(rawStack, "", 128 * 1024)
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

local function RecordKey(index, record)
  return tostring(index) .. "\031" .. record.message .. "\031" .. (record.stack or "")
end

function Bug:IsPresent()
  return GetBugDB() ~= nil or Scrub(_G.BugGrabber) ~= nil
end

function Bug:Disable()
  self._enabled = false
  local ticker = self._ticker
  self._ticker = nil
  if ticker and type(ticker.Cancel) == "function" then pcall(ticker.Cancel, ticker) end
end

function Bug:Enable()
  if self._enabled then return end
  self._enabled = true

  local timer = _G.C_Timer
  if type(timer) ~= "table" or type(timer.NewTicker) ~= "function" then return end
  local interval = SafeNumber(Settings().bugGrabberPollSec, 1, 0.25, 60)
  local ok, ticker = pcall(timer.NewTicker, interval, function()
    if Bug._enabled then pcall(Bug.ImportNew, Bug) end
  end)
  if ok then self._ticker = ticker end
end

function Bug:ImportNew()
  if Capture.ownsHandler then return 0 end
  if type(Capture.BuildEntry) ~= "function" or type(Capture.StoreEntry) ~= "function" then return 0 end

  local settings = Settings()
  if settings.importBugGrabber == false then return 0 end

  local budget = math.floor(SafeNumber(settings.bugGrabberImportMaxPerPoll, 200, 1, 1000))
  local scanMaximum = math.floor(SafeNumber(settings.bugGrabberScanMax, 5000, 1, 20000))
  local list = GetErrorList(GetBugDB())
  if not list then return 0 end

  local count = ListLength(list, scanMaximum)
  local seen, imported = {}, 0
  for index = 1, count do
    if budget <= 0 then break end
    local record = NormalizeRecord(SafeGet(list, index))
    if record then
      local key = RecordKey(index, record)
      seen[key] = true
      local previous = math.floor(SafeNumber(self._counterByKey[key], 0, 0, 1000000))
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
          if status == "stored" or status == "queued" or status == "ignored" or status then
            imported = imported + 1
            budget = budget - 1
            self._counterByKey[key] = previous + step
          else
            break
          end
        end
      elseif delta < 0 then
        self._counterByKey[key] = record.counter
      end
    end
  end

  -- Remove records that disappeared only after a complete bounded scan.
  if count < scanMaximum then
    for key in pairs(self._counterByKey) do
      if not seen[key] then self._counterByKey[key] = nil end
    end
  end
  return imported
end
