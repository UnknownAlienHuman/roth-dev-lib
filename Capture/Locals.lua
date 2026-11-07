-- !RothDevLib/Capture/Locals.lua
-- Bounded locals capture and stack-level calibration.

local RDL = _G.RothDevLib
local Locals = {}
RDL.Locals = Locals

local MAX_CACHE_KEYS = 512

Locals._cache = {}
Locals._cacheCount = 0
Locals._droppedCacheKeys = 0
Locals._bucket = { t = 0, tokens = 0 }

local function Now()
  local fn = type(_G.GetTime) == "function" and _G.GetTime or _G.time
  if type(fn) ~= "function" then return 0 end
  local ok, value = pcall(fn)
  return ok and type(value) == "number" and value or 0
end

local function Settings()
  if RDL.DB and type(RDL.DB.GetSettings) == "function" then
    local ok, settings = pcall(RDL.DB.GetSettings, RDL.DB)
    if ok and type(settings) == "table" then return settings end
  end
  return {}
end

local function Option(opts, key)
  if type(opts) ~= "table" then return nil end
  local guard = RDL.SecretGuard
  if guard and type(guard.CanAccessTable) == "function" then
    local ok, accessible = pcall(guard.CanAccessTable, guard, opts)
    if not ok or accessible ~= true then return nil end
  end
  local ok, value = pcall(rawget, opts, key)
  if not ok then return nil end
  if guard and type(guard.CanAccess) == "function" then
    local okAccess, accessible = pcall(guard.CanAccess, guard, value)
    if not okAccess or accessible ~= true then return nil end
  end
  if guard and type(guard.IsSecret) == "function" then
    local okSecret, secret = pcall(guard.IsSecret, guard, value)
    if not okSecret or secret == true then return nil end
  end
  return value
end

local function SafeText(value, fallback, maximum)
  if value == nil then return fallback end
  local text
  local util = RDL.Util
  if util and type(util.SafeToString) == "function" then
    local ok, rendered = pcall(util.SafeToString, util, value)
    if ok and type(rendered) == "string" then text = rendered end
  elseif type(value) == "string" then
    text = value
  end
  if type(text) ~= "string" or text == "<inaccessible>" or text == "<secret>" then
    return fallback
  end
  if maximum and #text > maximum then text = text:sub(1, maximum) end
  return text
end

local function SafeNumber(value, fallback, minimum, maximum)
  local ordinary = value
  local util = RDL.Util
  if util and type(util.Scrub) == "function" then
    local ok, scrubbed = pcall(util.Scrub, util, value)
    if not ok then return fallback end
    ordinary = scrubbed
  end
  if type(ordinary) ~= "number" or ordinary ~= ordinary
      or ordinary == math.huge or ordinary == -math.huge then
    return fallback
  end
  if ordinary < minimum then return minimum end
  if ordinary > maximum then return maximum end
  return ordinary
end

local function FilterAndTrim(localsStr)
  if type(localsStr) ~= "string" or localsStr == "" then return nil end

  local settings = Settings()
  local maxSize = math.floor(SafeNumber(Option(settings, "maxLocalsSize"), 8192, 256, 64 * 1024))

  if RDL.SecretGuard and type(RDL.SecretGuard.FilterLocals) == "function" then
    local ok, filtered = pcall(RDL.SecretGuard.FilterLocals, RDL.SecretGuard, localsStr)
    if ok and type(filtered) == "string" then localsStr = filtered end
  end
  if RDL.Util and type(RDL.Util.FilterLocals) == "function" then
    local ok, filtered = pcall(RDL.Util.FilterLocals, RDL.Util, localsStr, maxSize)
    if ok and type(filtered) == "string" then localsStr = filtered end
  elseif #localsStr > maxSize then
    localsStr = localsStr:sub(1, maxSize) .. "\n...[truncated]"
  end

  return localsStr
end

local function FirstFrameLine(stackStr)
  if type(stackStr) ~= "string" then return "" end
  local first = stackStr:match("^([^\n]+)") or ""
  if first:find("stack traceback", 1, true) then
    first = stackStr:match("stack traceback:\n([^\n]+)") or first
  end
  return first
end

local function MakeAddonToken(addonName)
  if type(addonName) ~= "string" or addonName == "" or addonName == "<?>" then
    return nil
  end
  return "AddOns/" .. addonName .. "/"
end

local function IsInternalFrame(line)
  if not line or line == "" then return false end
  if line:find("!RothDevLib", 1, true) then return true end
  if line:find("RothDevLib", 1, true) then return true end
  return false
end

local function IsGoodLocals(localsStr)
  if type(localsStr) ~= "string" then return false end
  if localsStr == "" then return false end
  if #localsStr < 24 then return false end
  return true
end

local function CacheSet(self, key, level)
  if type(key) ~= "string" or key == "" then return false end
  if self._cache[key] ~= nil then
    self._cache[key] = level
    return true
  end
  if (tonumber(self._cacheCount) or 0) >= MAX_CACHE_KEYS then
    self._droppedCacheKeys = (tonumber(self._droppedCacheKeys) or 0) + 1
    return false
  end
  self._cache[key] = level
  self._cacheCount = (tonumber(self._cacheCount) or 0) + 1
  return true
end

function Locals:_TakeProbeTokens(n)
  n = math.floor(SafeNumber(n, 1, 1, 100))
  local settings = Settings()
  local rate = math.floor(SafeNumber(Option(settings, "localsProbesPerSec"), 30, 1, 1000))
  local cap = rate * 2

  local bucket = self._bucket
  local now = Now()
  if not bucket.t or bucket.t == 0 then
    bucket.t = now
    bucket.tokens = rate
  end

  local dt = now - bucket.t
  if dt < 0 then
    bucket.t = now
    bucket.tokens = rate
  elseif dt >= 1 then
    local refill = math.floor(dt) * rate
    bucket.tokens = math.min(cap, (bucket.tokens or 0) + refill)
    bucket.t = now
  end

  if (bucket.tokens or 0) < n then return false end
  bucket.tokens = (bucket.tokens or 0) - n
  return true
end

function Locals:_TryLevel(level)
  level = math.floor(SafeNumber(level, 0, 0, 100))
  if level < 1 then return nil, "" end

  local raw
  if type(_G.debuglocals) == "function" then
    local ok, value = pcall(_G.debuglocals, level)
    if ok then raw = value end
  end
  local localsStr = FilterAndTrim(raw)

  local frameLine = ""
  if type(_G.debugstack) == "function" then
    local ok, stack = pcall(_G.debugstack, level, 3, 3)
    if ok then frameLine = FirstFrameLine(SafeText(stack, "", 4096)) end
  end

  return localsStr, frameLine
end

function Locals:_ScoreCandidate(localsStr, frameLine, addonToken)
  if not IsGoodLocals(localsStr) then return -1 end

  local score = math.min(#localsStr / 64, 40)
  if frameLine and frameLine ~= "" then
    local normalized = frameLine:gsub("\\", "/")
    if normalized:find("[C]", 1, true) then score = score - 25 end
    if normalized:find("xpcall", 1, true) then score = score - 15 end
    if IsInternalFrame(normalized) then score = score - 100 end
    if addonToken and normalized:find(addonToken, 1, true) then score = score + 80 end
  end
  return score
end

-- Capture locals using a calibrated heuristic. External options are read only
-- through rawget and retained cache identities are bounded.
function Locals:CaptureBest(opts)
  if type(opts) ~= "table" then opts = {} end
  local settings = Settings()

  if Option(settings, "captureLocals") == false then
    return nil, { disabled = true }
  end

  local base = math.floor(SafeNumber(Option(opts, "baseLevel"), 2, 1, 100))
  local configuredProbe = Option(opts, "maxProbe")
  if configuredProbe == nil then configuredProbe = Option(settings, "localsProbeMax") end
  local maxProbe = math.floor(SafeNumber(configuredProbe, 12, 0, 30))

  local stackText = SafeText(Option(opts, "stack"), "", 128 * 1024)
  local targetAddon = SafeText(Option(opts, "addon"), nil, 128)
  if (not targetAddon or targetAddon == "<?>")
      and RDL.Util and type(RDL.Util.GuessAddonFromStack) == "function" then
    local ok, guessed = pcall(RDL.Util.GuessAddonFromStack, RDL.Util, stackText)
    if ok then targetAddon = SafeText(guessed, nil, 128) end
  end
  local addonToken = MakeAddonToken(targetAddon)

  local cacheEnabled = Option(settings, "localsProbeCache") ~= false
  local cacheKey
  local explicitCacheKey = Option(opts, "cacheKey")
  if type(explicitCacheKey) == "string" then
    cacheKey = SafeText(explicitCacheKey, nil, 384)
  elseif cacheEnabled then
    local top = stackText:match("Interface/AddOns/[^\n]+")
      or stackText:match("AddOns/[^\n]+") or ""
    if #top > 180 then top = top:sub(1, 180) end
    cacheKey = (targetAddon or "<?>") .. "|" .. top
  end

  local meta = { baseLevel = base, targetAddon = targetAddon, cacheKey = cacheKey }

  if cacheKey and self._cache[cacheKey] then
    local level = self._cache[cacheKey]
    local localsStr, frameLine = self:_TryLevel(level)
    if IsGoodLocals(localsStr) then
      meta.cacheHit = true
      meta.level = level
      meta.frame = frameLine
      meta.score = 999
      return localsStr, meta
    end
  end

  local bestLocals, bestFrame = self:_TryLevel(base)
  local bestScore = self:_ScoreCandidate(bestLocals, bestFrame, addonToken)
  local bestLevel = base

  if bestScore >= 60 then
    meta.level = bestLevel
    meta.frame = bestFrame
    meta.score = bestScore
    if cacheKey and cacheEnabled then CacheSet(self, cacheKey, bestLevel) end
    return bestLocals, meta
  end

  local probed = 0
  for level = base, base + maxProbe do
    if level ~= base then
      if not self:_TakeProbeTokens(1) then
        meta.probeBudgetExhausted = true
        break
      end
      local localsStr, frameLine = self:_TryLevel(level)
      local score = self:_ScoreCandidate(localsStr, frameLine, addonToken)
      probed = probed + 1
      if score > bestScore then
        bestScore = score
        bestLocals = localsStr
        bestFrame = frameLine
        bestLevel = level
        if bestScore >= 80 then break end
      end
    end
  end

  meta.probed = probed
  meta.level = bestLevel
  meta.frame = bestFrame
  meta.score = bestScore

  if cacheKey and cacheEnabled and bestScore >= 0 then
    CacheSet(self, cacheKey, bestLevel)
  end

  return bestLocals, meta
end

function Locals:CaptureAtLevel(level)
  return select(1, self:_TryLevel(level))
end

function Locals:ResetCache()
  for key in pairs(self._cache) do self._cache[key] = nil end
  self._cacheCount = 0
  self._droppedCacheKeys = 0
end

function Locals:GetCacheStats()
  return {
    keys = tonumber(self._cacheCount) or 0,
    maximum = MAX_CACHE_KEYS,
    dropped = tonumber(self._droppedCacheKeys) or 0,
  }
end
