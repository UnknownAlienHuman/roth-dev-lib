-- !RothDevLib/Capture/Storm.lua
-- Bounded token-bucket flood protection for error/warning/taint/integration
-- capture. Only fixed semantic kinds own buckets; arbitrary public labels share
-- one overflow bucket and therefore cannot multiply the available burst budget.

local RDL = _G.RothDevLib
local Storm = {}
RDL.Storm = Storm

local OTHER_KIND = "@other"
local KNOWN_KINDS = {
  LUA_ERROR = true,
  SUPPRESSED = true,
  LUA_WARNING = true,
  TAINT_BLOCKED = true,
  TAINT_FORBIDDEN = true,
  TAINT_STATE = true,
  ALERT = true,
  ASSERT = true,
  INTEGRATION = true,
}
local MAX_BUCKETS = 10 -- nine semantic kinds plus the shared overflow bucket.

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
    return nil
  end
  if #text > 64 then text = text:sub(1, 64) end
  return text
end

local function CanonicalKind(rawKind)
  local kind = SafeKind(rawKind)
  if kind and KNOWN_KINDS[kind] then return kind, false end
  return OTHER_KIND, true
end

local function GetBucket(kind)
  local existing = Storm._buckets[kind]
  if existing then return existing end

  -- CanonicalKind() limits this table to the fixed semantic set above. Keep a
  -- defensive ceiling in case the table is externally corrupted at runtime.
  if (tonumber(Storm._bucketCount) or 0) >= MAX_BUCKETS then
    return Storm._buckets[OTHER_KIND]
  end

  local bucket = NewBucket()
  Storm._buckets[kind] = bucket
  Storm._bucketCount = (tonumber(Storm._bucketCount) or 0) + 1
  return bucket
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
  elseif kind == "TAINT_BLOCKED" or kind == "TAINT_FORBIDDEN" or kind == "TAINT_STATE" then
    rate = settings and settings.stormErrorsPerSec or 15
  else
    -- Alerts, assertions, explicit integration kinds and arbitrary labels use
    -- the same integration budget.
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
  local kind, collapsed = CanonicalKind(rawKind)
  if collapsed then
    self._droppedKinds = (tonumber(self._droppedKinds) or 0) + 1
  end

  local bucket = GetBucket(kind)
  local rate = GetRate(kind)
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
