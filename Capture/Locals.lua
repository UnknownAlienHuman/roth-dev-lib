-- !RothDevLib/Capture/Locals.lua
-- Locals capture and stack-level calibration.
--
-- Problem:
--   `debuglocals(level)` is very sensitive to call-path differences:
--   * hard errors via global errorhandler
--   * suppressed errors via xpcall wrappers
--   * explicit reports via RDL:Report()
--   Depending on wrappers, the correct `level` may shift.
--
-- Goal:
--   Best-effort capture of locals from the most relevant stack frame,
--   with bounded overhead and Secret Value filtering.

local RDL = _G.RothDevLib
local Locals = {}
RDL.Locals = Locals

Locals._cache = {}
Locals._bucket = { t = 0, tokens = 0 }

local function Now()
  if type(GetTime) == "function" then return GetTime() end
  return time()
end

local function Settings()
  return (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or {}
end

local function FilterAndTrim(localsStr)
  if type(localsStr) ~= "string" or localsStr == "" then return nil end

  local s = Settings()
  local maxSize = tonumber(s.maxLocalsSize) or 8192

  -- Secret escape filtering (12.x |K...|k)
  if RDL.SecretGuard and RDL.SecretGuard.FilterLocals then
    localsStr = RDL.SecretGuard:FilterLocals(localsStr)
  end
  if RDL.Util and RDL.Util.FilterLocals then
    localsStr = RDL.Util:FilterLocals(localsStr, maxSize)
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
  return "AddOns[\\/]" .. addonName .. "[\\/]"
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

function Locals:_TakeProbeTokens(n)
  n = n or 1
  local s = Settings()
  local rate = tonumber(s.localsProbesPerSec) or 30
  local cap = rate * 2

  local b = self._bucket
  local now = Now()
  if not b.t or b.t == 0 then
    b.t = now
    b.tokens = rate
  end

  local dt = now - b.t
  if dt >= 1 then
    local refill = math.floor(dt) * rate
    b.tokens = math.min(cap, (b.tokens or 0) + refill)
    b.t = now
  end

  if (b.tokens or 0) < n then return false end
  b.tokens = (b.tokens or 0) - n
  return true
end

function Locals:_TryLevel(level)
  level = tonumber(level)
  if not level or level < 1 then return nil, "" end

  local okL, raw = pcall(debuglocals, level)
  local localsStr = okL and raw or nil
  localsStr = FilterAndTrim(localsStr)

  local okS, st = pcall(function()
    return debugstack(level, 3, 3)
  end)
  local frameLine = okS and FirstFrameLine(st) or ""

  return localsStr, frameLine
end

function Locals:_ScoreCandidate(localsStr, frameLine, addonToken)
  if not IsGoodLocals(localsStr) then return -1 end

  local score = 0
  score = score + math.min(#localsStr / 64, 40)

  if frameLine and frameLine ~= "" then
    if frameLine:find("%[C%]", 1, false) then score = score - 25 end
    if frameLine:find("xpcall", 1, true) then score = score - 15 end
    if IsInternalFrame(frameLine) then score = score - 100 end
    if addonToken and frameLine:find(addonToken) then
      score = score + 80
    end
  end

  return score
end

-- Capture locals using a calibrated heuristic.
--
-- opts:
--   addon: string (preferred addon name)
--   stack: string (traceback/stack; used to guess addon/origin)
--   baseLevel: number (starting debuglocals level)
--   maxProbe: number (levels to probe beyond base)
--   cacheKey: string (optional)
--
-- returns localsStr, meta
function Locals:CaptureBest(opts)
  opts = opts or {}
  local s = Settings()

  if s.captureLocals == false then
    return nil, { disabled = true }
  end

  local base = tonumber(opts.baseLevel) or 2
  local maxProbe = tonumber(opts.maxProbe) or tonumber(s.localsProbeMax) or 12
  if maxProbe < 0 then maxProbe = 0 end
  if maxProbe > 30 then maxProbe = 30 end

  -- Determine addon matching token.
  local targetAddon = opts.addon
  if (not targetAddon or targetAddon == "<?>" or targetAddon == "") and RDL.Util and RDL.Util.GuessAddonFromStack then
    targetAddon = RDL.Util:GuessAddonFromStack(opts.stack)
  end
  local addonToken = MakeAddonToken(targetAddon)

  -- Cache key by addon + first stack origin line (normalized).
  local cacheKey = opts.cacheKey
  if cacheKey == nil and s.localsProbeCache ~= false then
    local top = ""
    if type(opts.stack) == "string" then
      top = (opts.stack:match("Interface/AddOns/[^\n]+") or opts.stack:match("AddOns/[^\n]+") or "")
      if #top > 180 then top = top:sub(1, 180) end
    end
    cacheKey = tostring(targetAddon or "<?>") .. "|" .. tostring(top)
  end

  local meta = { baseLevel = base, targetAddon = targetAddon, cacheKey = cacheKey }

  if cacheKey and self._cache[cacheKey] then
    local lvl = self._cache[cacheKey]
    local localsStr, frameLine = self:_TryLevel(lvl)
    if IsGoodLocals(localsStr) then
      meta.cacheHit = true
      meta.level = lvl
      meta.frame = frameLine
      meta.score = 999
      return localsStr, meta
    end
  end

  -- Fast path: try base level first.
  local bestLocals, bestFrame = self:_TryLevel(base)
  local bestScore = self:_ScoreCandidate(bestLocals, bestFrame, addonToken)
  local bestLevel = base

  if bestScore >= 60 then
    meta.level = bestLevel
    meta.frame = bestFrame
    meta.score = bestScore
    if cacheKey and s.localsProbeCache ~= false then self._cache[cacheKey] = bestLevel end
    return bestLocals, meta
  end

  local probed = 0
  for lvl = base, base + maxProbe do
    if lvl ~= base then
      if not self:_TakeProbeTokens(1) then
        meta.probeBudgetExhausted = true
        break
      end
      local localsStr, frameLine = self:_TryLevel(lvl)
      local score = self:_ScoreCandidate(localsStr, frameLine, addonToken)
      probed = probed + 1
      if score > bestScore then
        bestScore = score
        bestLocals = localsStr
        bestFrame = frameLine
        bestLevel = lvl
        if bestScore >= 80 then break end
      end
    end
  end

  meta.probed = probed
  meta.level = bestLevel
  meta.frame = bestFrame
  meta.score = bestScore

  if cacheKey and s.localsProbeCache ~= false and bestScore >= 0 then
    self._cache[cacheKey] = bestLevel
  end

  return bestLocals, meta
end

-- Explicit level capture (backward-compat helper).
function Locals:CaptureAtLevel(level)
  local localsStr = select(1, self:_TryLevel(level))
  return localsStr
end
