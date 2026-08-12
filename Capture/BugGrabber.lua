-- !RothDevLib/Capture/BugGrabber.lua
-- Optional importer for BugGrabberDB when RothDevLib does NOT own the global errorhandler.
--
-- Rationale:
--   * Some users keep BugGrabber/BugSack enabled (or another addon owns the handler).
--   * In that case, RothDevLib cannot see hard Lua errors via seterrorhandler().
--   * BugGrabber still records them into BugGrabberDB. We can poll and import.
--
-- Safety/perf:
--   * Poll is OFF unless enabled in settings AND we don't own the handler.
--   * Poll interval is low (default 1s).
--   * Import is counter-delta aware (BugGrabber can update counter without growing #errors).

local RDL = _G.RothDevLib
if not RDL or not RDL.Capture then return end

local Capture = RDL.Capture
local Bug = {}
Capture.BugGrabber = Bug

Bug._enabled = false
Bug._ticker = nil
Bug._lastCount = 0
Bug._lastSeenSession = nil
Bug._counterByKey = {}

local function GetSettings()
  return (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or {}
end

local function GetBugDB()
  local db = _G.BugGrabberDB
  if type(db) == 'table' then return db end
  return nil
end

local function GetErrorList(db)
  if type(db) ~= 'table' then return nil end
  local errs = db.errors or db.error or db.errs
  if type(errs) == 'table' then return errs end
  -- Some variants store errors at the top-level.
  if type(db[1]) == 'table' or type(db[1]) == 'string' then return db end
  return nil
end

local function NormalizeErrorRecord(rec)
  if rec == nil then return nil end
  if type(rec) == 'string' then
    return { message = rec, stack = nil, locals = nil, ts = nil, counter = 1, session = nil }
  end
  if type(rec) ~= 'table' then
    return { message = tostring(rec), stack = nil, locals = nil, ts = nil, counter = 1, session = nil }
  end

  local msg = rec.message or rec.msg or rec.error or rec[1]
  local stack = rec.stack or rec.traceback or rec.trace or rec[2]
  local locals = rec.locals or rec.localVariables
  local ts = rec.time or rec.ts or rec.when
  local counter = rec.counter
  local session = rec.session

  if msg == nil and rec[2] and type(rec[2]) == 'string' then msg = rec[2] end
  if msg == nil then msg = tostring(rec) end

  local c = tonumber(counter) or 1
  if c < 1 then c = 1 end

  return {
    message = tostring(msg or ''),
    stack = (type(stack) == 'string' and stack ~= '' and stack) or nil,
    locals = (type(locals) == 'string' or type(locals) == 'table') and locals or nil,
    ts = tonumber(ts) or nil,
    counter = c,
    session = tonumber(session) or session,
  }
end

local function MakeRecordKey(rawRec, rec)
  if type(rawRec) == "table" then
    return "tbl:" .. tostring(rawRec)
  end

  local msg = tostring((rec and rec.message) or rawRec or "")
  local stack = tostring((rec and rec.stack) or "")
  return "str:" .. msg .. "\031" .. stack
end

function Bug:IsPresent()
  local db = GetBugDB()
  if db then return true end
  if _G.BugGrabber ~= nil then return true end
  return false
end

function Bug:Disable()
  self._enabled = false
  if self._ticker and self._ticker.Cancel then
    pcall(function() self._ticker:Cancel() end)
  end
  self._ticker = nil
end

function Bug:Enable()
  if self._enabled then return end
  self._enabled = true

  if not C_Timer or type(C_Timer.NewTicker) ~= 'function' then
    return
  end

  local settings = GetSettings()
  local interval = tonumber(settings.bugGrabberPollSec) or 1.0
  if interval < 0.25 then interval = 0.25 end

  self._ticker = C_Timer.NewTicker(interval, function()
    if not Capture or not Bug or not Bug._enabled then return end
    pcall(function() Bug:ImportNew() end)
  end)
end

function Bug:ImportNew()
  if not (Capture and Capture.BuildEntry and Capture.StoreEntry) then return end
  if Capture.ownsHandler then return end

  local settings = GetSettings()
  if settings.importBugGrabber == false then return end
  local maxPerPoll = tonumber(settings.bugGrabberImportMaxPerPoll) or 200
  if maxPerPoll < 1 then maxPerPoll = 1 end

  local db = GetBugDB()
  local errs = GetErrorList(db)
  if not errs then return end

  if type(self._counterByKey) ~= "table" then
    self._counterByKey = {}
  end

  local n = #errs

  -- Detect session reset (BugGrabber can wipe/rotate errors).
  if self._lastCount and n < (self._lastCount or 0) then
    self._counterByKey = {}
  end
  self._lastCount = n

  self._lastSeenSession = db and db.session or self._lastSeenSession

  local seenKeys = {}
  local budget = maxPerPoll
  local stopImport = false
  local interrupted = false
  for i = 1, n do
    if budget <= 0 or stopImport then
      interrupted = true
      break
    end
    local rawRec = errs[i]
    local rec = NormalizeErrorRecord(rawRec)
    if rec and rec.message and rec.message ~= '' then
      local key = MakeRecordKey(rawRec, rec)
      seenKeys[key] = true

      local importedCounter = tonumber(self._counterByKey[key]) or 0
      local sourceCounter = tonumber(rec.counter) or 1
      if sourceCounter < 1 then sourceCounter = 1 end

      if sourceCounter > importedCounter then
        local delta = sourceCounter - importedCounter

        local importedNow = 0
        for j = 1, delta do
          if budget <= 0 then break end
          local stack = rec.stack or ''
          local entry = nil
          local ok, built = pcall(Capture.BuildEntry, 'LUA_ERROR', rec.message, stack, rec.locals, nil, nil, {
            source = 'BugGrabber',
            imported = true,
            bugIndex = i,
            bugTs = rec.ts,
            bugSession = rec.session,
            bugCounter = sourceCounter,
            bugCounterImportedFrom = importedCounter,
            bugCounterImportedStep = j,
          })
          if ok then entry = built end
          if entry then
            local status = Capture.StoreEntry(entry)
            if status == "throttled" then
              stopImport = true
              break
            end
            if status == "stored" or status == "queued" or status == "ignored" then
              importedNow = importedNow + 1
              budget = budget - 1
            elseif status == "failed" then
              break
            else
              -- Backward/edge compatibility: treat unknown truthy status as success.
              if status then
                importedNow = importedNow + 1
                budget = budget - 1
              else
                break
              end
            end
          else
            break
          end
        end

        if importedNow > 0 then
          self._counterByKey[key] = importedCounter + importedNow
        end
      elseif sourceCounter < importedCounter then
        -- BugGrabber rotated/wiped this record and reused the slot; resync baseline.
        self._counterByKey[key] = sourceCounter
      end
    end
  end

  -- Cleanup removed records so the key map does not grow forever.
  -- Only safe after a full scan; partial scans would incorrectly drop unseen keys.
  if not interrupted then
    for key in pairs(self._counterByKey) do
      if not seenKeys[key] then
        self._counterByKey[key] = nil
      end
    end
  end
end
