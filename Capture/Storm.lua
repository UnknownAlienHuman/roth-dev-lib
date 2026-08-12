-- !RothDevLib/Capture/Storm.lua
-- Flood protection: rate-limits error/warning/taint capture.
-- Token bucket algorithm (inspired by BugGrabber's BUGGRABBER_ERRORS_PER_SEC_BEFORE_THROTTLE).

local RDL = _G.RothDevLib
local Storm = {}
RDL.Storm = Storm

Storm._buckets = {}
Storm._stats = { total = 0, throttled = 0 }

local function GetBucket(kind)
  if not Storm._buckets[kind] then
    Storm._buckets[kind] = {
      -- Lazy-init in Allow(): initial burst must pass (BugGrabber parity).
      tokens = nil,
      lastRefill = nil,
    }
  end
  return Storm._buckets[kind]
end

local function GetRate(kind)
  local settings = RDL.DB and RDL.DB:GetSettings()
  if not settings then return 15 end

  if kind == "LUA_ERROR" or kind == "SUPPRESSED" then
    return settings.stormErrorsPerSec or 15
  elseif kind == "LUA_WARNING" then
    return settings.stormWarningsPerSec or 30
  elseif kind == "TAINT_BLOCKED" or kind == "TAINT_FORBIDDEN" then
    return settings.stormErrorsPerSec or 15
  end
  -- Integration events (ALERT, ASSERT) — generous limit
  return 30
end

-- Check if an event of the given kind is allowed through.
-- Returns true if allowed, false if throttled.
function Storm:Allow(kind)
  local bucket = GetBucket(kind)
  local rate = GetRate(kind)
  if type(rate) ~= "number" or rate <= 0 then
    rate = 1
  end
  local now = GetTime()

  -- Do not drop the first captured errors: start with a full burst budget.
  if type(bucket.tokens) ~= "number" then
    bucket.tokens = rate * 2
  end
  if type(bucket.lastRefill) ~= "number" then
    bucket.lastRefill = now
  end

  -- Refill tokens based on elapsed time
  local elapsed = now - bucket.lastRefill
  bucket.tokens = bucket.tokens + (elapsed * rate)
  bucket.lastRefill = now

  -- Cap at burst size (2x rate allows short bursts)
  if bucket.tokens > rate * 2 then
    bucket.tokens = rate * 2
  end

  self._stats.total = (self._stats.total or 0) + 1

  if bucket.tokens >= 1 then
    bucket.tokens = bucket.tokens - 1
    return true
  end

  -- Throttled
  self._stats.throttled = (self._stats.throttled or 0) + 1
  return false
end

function Storm:GetStats()
  return {
    total = self._stats.total or 0,
    throttled = self._stats.throttled or 0,
    buckets = self._buckets,
  }
end

function Storm:Reset()
  self._buckets = {}
  self._stats = { total = 0, throttled = 0 }
end
