-- Public Screenshot() only: opt-in, one pending request, no UI manipulation,
-- no filesystem access, no filename guesses, and no protected-action retries.
local RDL = _G.RothDevLib
if not RDL then return end
local Screenshots = { _records = {}, _seen = {}, _attempts = 0, _generation = 0, _stopped = true }
RDL.Screenshots = Screenshots
local LIMIT, COOLDOWN, TIMEOUT = 20, 30, 10
local CALLBACK_KEY = "RothDevLib:Screenshots"
local AUTO_KINDS = { LUA_ERROR = true, SUPPRESSED = true, ASSERT = true,
  TAINT_BLOCKED = true, TAINT_FORBIDDEN = true, ANOMALY = true }

local function Copy(value)
  local util = RDL.Util
  if not util or type(util.CopyDiagnosticValue) ~= "function" then return nil end
  local ok, result = pcall(util.CopyDiagnosticValue, util, value, {
    maxDepth = 4, maxEntries = 32, maxNodes = 600,
    maxStringBytes = 4096, maxTotalBytes = 128 * 1024,
  })
  if ok then return result end
end

local function Now(fn)
  if type(fn) ~= "function" then return 0 end
  local ok, value = pcall(fn)
  if not ok then return 0 end
  value = Copy(value)
  if type(value) == "number" and value == value and value ~= math.huge
      and value ~= -math.huge then return value end
  return 0
end

local function Settings()
  return RDL.DB and RDL.DB:GetSettings() or {}
end

local function Ready()
  local db = RDL.DB
  return db and db:IsReady() and not db:IsWriteSuspended()
end

local function SaveEvidence()
  -- Persist only this small outcome ledger. Never sample native profiling
  -- or dispatch another error while processing a synchronous screenshot event.
  local db = RDL.DB
  if Ready() and type(db.SaveScreenshotEvidence) == "function" then
    db:SaveScreenshotEvidence(Screenshots:GetSnapshot())
  end
end

local function Finish(record, status)
  record.status = status
  record.completedAt = Now(_G.time)
  if Screenshots._pending == record then Screenshots._pending = nil end
  SaveEvidence()
end

function Screenshots:Request(reason, signature, automatic)
  automatic = Copy(automatic) == true
  if self._stopped or not Ready() then return false, "not-ready" end
  if automatic and Settings().autoScreenshots ~= true then return false, "disabled" end
  if self._pending then return false, "busy" end
  if self._attempts >= LIMIT then return false, "session-limit" end
  if type(_G.Screenshot) ~= "function" or type(_G.C_Timer) ~= "table"
      or type(_G.C_Timer.After) ~= "function" then return false, "unavailable" end
  local clock = Now(_G.GetTime)
  if self._lastRequest and clock - self._lastRequest < COOLDOWN then return false, "cooldown" end

  reason, signature = Copy(reason), Copy(signature)
  if type(reason) ~= "string" then reason = "manual" end
  if type(signature) ~= "string" then signature = nil end
  if signature and self._seen[signature] then return false, "already-requested" end

  self._attempts = self._attempts + 1
  self._lastRequest = clock
  local record = { id = self._attempts, sessionId = RDL.DB.sessionId,
    requestedAt = Now(_G.time), clock = clock, reason = reason:sub(1, 128),
    signature = signature, automatic = automatic == true, status = "queued",
    correlation = "global-events-have-no-request-id-or-filename" }
  self._records[#self._records + 1] = record
  self._pending = record
  if signature then self._seen[signature] = true end
  local generation = self._generation
  SaveEvidence()

  local ok = pcall(_G.C_Timer.After, 0.1, function()
    if self._generation ~= generation or self._pending ~= record then return end
    if self._stopped or not Ready() or (automatic and Settings().autoScreenshots ~= true) then
      Finish(record, "cancelled-before-request")
      return
    end
    record.status = "requested"
    record.invokedAt = Now(_G.time)
    local called = pcall(_G.Screenshot)
    if not called then Finish(record, "call-failed"); return end
    -- Completion events may fire synchronously inside Screenshot().
    if self._pending ~= record then return end
    SaveEvidence()
    local timed = pcall(_G.C_Timer.After, TIMEOUT, function()
      if self._generation == generation and self._pending == record then
        Finish(record, "completion-unconfirmed")
      end
    end)
    if not timed then Finish(record, "completion-unconfirmed") end
  end)
  if not ok then Finish(record, "timer-unavailable"); return false, "timer-unavailable" end
  return true, record.id
end

function Screenshots:OnEvent(event)
  local record = self._pending
  if not record or record.status ~= "requested" then return end
  if event == "SCREENSHOT_SUCCEEDED" then
    Finish(record, "success-event-observed")
  elseif event == "SCREENSHOT_FAILED" then
    Finish(record, "failure-event-observed")
  end
end

function Screenshots:SetEnabled(enabled)
  enabled = Copy(enabled) == true
  local settings = Settings()
  settings.autoScreenshots = enabled == true
  if type(RDL.UnregisterCallback) == "function" then
    RDL:UnregisterCallback("RDL_CAPTURE", CALLBACK_KEY)
  end
  local registered = not enabled
  if enabled == true and not self._stopped and type(RDL.RegisterCallback) == "function" then
    registered = RDL:RegisterCallback("RDL_CAPTURE", CALLBACK_KEY, function(entry)
      if type(entry) == "table" and AUTO_KINDS[entry.kind] then
        self:Request(entry.kind, entry.sig, true)
      end
    end)
  end
  if enabled and not registered then settings.autoScreenshots = false end
  if not settings.autoScreenshots and self._pending and self._pending.status == "queued" then
    Finish(self._pending, "cancelled-before-request")
  end
  SaveEvidence()
  return registered == true
end

function Screenshots:Init()
  self._stopped = false
  return self:SetEnabled(Settings().autoScreenshots == true)
end

function Screenshots:Stop()
  self._stopped = true
  self._generation = self._generation + 1
  if type(RDL.UnregisterCallback) == "function" then
    RDL:UnregisterCallback("RDL_CAPTURE", CALLBACK_KEY)
  end
  if self._pending then Finish(self._pending, "interrupted") end
end

function Screenshots:ClearSession()
  self:Stop()
  self._records, self._seen = {}, {}
  -- Keep the UI-session rate/attempt budget even after /rdev clear.
  self:Init()
  SaveEvidence()
end

function Screenshots:GetSnapshot()
  return Copy({ enabled = Settings().autoScreenshots == true, active = not self._stopped,
    attempts = self._attempts,
    limit = LIMIT, cooldownSec = COOLDOWN, records = self._records })
end
