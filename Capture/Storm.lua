-- !RothDevLib/Capture/Storm.lua
-- Bounded token-bucket flood protection for error/warning/taint/integration
-- capture. Dynamic kinds share one overflow bucket instead of bypassing limits.

local RDL = _G.RothDevLib
local Storm = {}
RDL.Storm = Storm

local MAX_BUCKETS = 64
local OTHER_KIND = "@other"

local function NewBucket()
  return {
    -- Lazy-init in Allow(): the first burst must pass.
    tokens = nil,
    lastRefill = nil,
  }
end

Storm._buckets = { [OTHER_KIND] = NewBucket() }
Storm._bucketCount = 1
Storm._droppedKinds = 0
Storm._stats = { total = 0, throttled = 0 }

local function SafeKind(value)
  local text
  local util = RDL.Util
  if util and type(util.SafeToString) == "function" then
    local ok, rendered = pcall(util.SafeToString, util, value)
    if ok and type(rendered) == "string" then text = rendered end
  elseif type(value) == "string" then
    text = value
  end
  if type(text) ~= "string" or text == "" or text == "<inaccessible>"
      or text == "<secret>" then
    return "INTEGRATION"
  end
  if #text > 64 then text = text:sub(1, 64) end
  return text
end

local function GetBucket(kind)
  local existing = Storm._buckets[kind]
  if existing then return existing, kind end

  if (tonumber(Storm._bucketCount) or 0) >= MAX_BUCKETS then
    Storm._droppedKinds = (tonumber(Storm._droppedKinds) or 0) + 1
    return Storm._buckets[OTHER_KIND], OTHER_KIND
  end

  local bucket = NewBucket()
  Storm._buckets[kind] = bucket
  Storm._bucketCount = (tonumber(Storm._bucketCount) or 0) + 1
  return bucket, kind
end

local function Settings()
  if RDL.DB and type(RDL.DB.GetSettings) == "function" then
    local ok, settings = pcall(RDL.DB.GetSettings, RDL.DB)
    if ok and type(settings) == "table" then return settings end
  end
  return nil
end

local function GetRate(kind)
  local settings = Settings()
  local rate
  if kind == "LUA_ERROR" or kind == "SUPPRESSED" then
    rate = settings and settings.stormErrorsPerSec or 15
  elseif kind == "LUA_WARNING" then
    rate = settings and settings.stormWarningsPerSec or 30
  elseif kind == "TAINT_BLOCKED" or kind == "TAINT_FORBIDDEN" then
    rate = settings and settings.stormErrorsPerSec or 15
  else
    -- Integration events share a generous default rate.
    rate = 30
  end

  rate = tonumber(rate) or 1
  if rate ~= rate or rate == math.huge or rate == -math.huge then rate = 1 end
  if rate < 1 then rate = 1 elseif rate > 10000 then rate = 10000 end
  return rate
end

local function Now()
  local fn = type(_G.GetTime) == "function" and _G.GetTime or _G.time
  if type(fn) ~= "function" then return 0 end
  local ok, value = pcall(fn)
  if not ok or type(value) ~= "number" or value ~= value
      or value == math.huge or value == -math.huge then
    return 0
  end
  return value
end

-- Check whether an event of the given kind may pass.
function Storm:Allow(rawKind)
  local kind = SafeKind(rawKind)
  local bucket, bucketKind = GetBucket(kind)
  local rate = GetRate(bucketKind == OTHER_KIND and "INTEGRATION" or kind)
  local now = Now()

  if type(bucket.tokens) ~= "number" then bucket.tokens = rate * 2 end
  if type(bucket.lastRefill) ~= "number" then bucket.lastRefill = now end

  local elapsed = now - bucket.lastRefill
  if elapsed < 0 then elapsed = 0 end
  bucket.tokens = math.min(rate * 2, bucket.tokens + elapsed * rate)
  bucket.lastRefill = now

  self._stats.total = (tonumber(self._stats.total) or 0) + 1
  if bucket.tokens >= 1 then
    bucket.tokens = bucket.tokens - 1
    return true
  end

  self._stats.throttled = (tonumber(self._stats.throttled) or 0) + 1
  return false
end

function Storm:GetStats()
  local buckets = {}
  for kind, bucket in pairs(self._buckets) do
    buckets[kind] = {
      tokens = tonumber(bucket.tokens),
      lastRefill = tonumber(bucket.lastRefill),
    }
  end
  return {
    total = tonumber(self._stats.total) or 0,
    throttled = tonumber(self._stats.throttled) or 0,
    bucketCount = tonumber(self._bucketCount) or 0,
    maxBuckets = MAX_BUCKETS,
    droppedKinds = tonumber(self._droppedKinds) or 0,
    buckets = buckets,
  }
end

function Storm:Reset()
  self._buckets = { [OTHER_KIND] = NewBucket() }
  self._bucketCount = 1
  self._droppedKinds = 0
  self._stats = { total = 0, throttled = 0 }
end
