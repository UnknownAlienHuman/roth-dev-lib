-- !RothDevLib/Perf/Mem.lua
-- Memory-delta observations that preserve the wrapped function's complete
-- return tuple. Measurements are diagnostic traffic, not retained-memory proof.

local RDL = _G.RothDevLib
if not RDL then return end

local Mem = {}
RDL.Mem = Mem

local MAX_STAT_KEYS = 1024
local MAX_SAMPLE_KEYS = 1024

Mem._stats = Mem._stats or {}
Mem._lastAlert = Mem._lastAlert or {}
Mem._lastSample = Mem._lastSample or {}
Mem._statsCount = 0
Mem._sampleCount = 0
Mem._droppedStats = 0
Mem._droppedSamples = 0
Mem._ticker = Mem._ticker or nil

local Unpack = table.unpack or unpack

local function Pack(...)
  return { n = select("#", ...), ... }
end

local function CanAccess(value)
  local guard = RDL.SecretGuard
  if guard and type(guard.CanAccess) == "function" then
    local ok, allowed = pcall(guard.CanAccess, guard, value)
    if not ok or allowed ~= true then return false end
  elseif type(_G.canaccessvalue) == "function" then
    local ok, allowed = pcall(_G.canaccessvalue, value)
    if not ok or allowed ~= true then return false end
  end
  if guard and type(guard.IsSecret) == "function" then
    local ok, secret = pcall(guard.IsSecret, guard, value)
    if not ok or secret == true then return false end
  elseif type(_G.issecretvalue) == "function" then
    local ok, secret = pcall(_G.issecretvalue, value)
    if not ok or secret == true then return false end
  end
  return true
end

local function IsCallable(value)
  return CanAccess(value) and type(value) == "function"
end

local function Finite(value)
  return CanAccess(value) and type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
end

local function SafeNumber(value, fallback)
  return Finite(value) and value or fallback
end

local function NowMs()
  if type(_G.debugprofilestop) == "function" then
    local ok, value = pcall(_G.debugprofilestop)
    if ok and Finite(value) then return value end
  end
  if type(_G.GetTime) == "function" then
    local ok, value = pcall(_G.GetTime)
    if ok and Finite(value) then return value * 1000 end
  end
  if type(_G.time) == "function" then
    local ok, value = pcall(_G.time)
    if ok and Finite(value) then return value * 1000 end
  end
  return 0
end

local function GetSettings()
  if RDL.DB and type(RDL.DB.GetSettings) == "function" then
    local ok, settings = pcall(RDL.DB.GetSettings, RDL.DB)
    if ok and type(settings) == "table" then return settings end
  end
  return nil
end

local function Option(opts, key)
  if not CanAccess(opts) or type(opts) ~= "table" then return nil end
  local guard = RDL.SecretGuard
  if guard and type(guard.CanAccessTable) == "function" then
    local ok, allowed = pcall(guard.CanAccessTable, guard, opts)
    if not ok or allowed ~= true then return nil end
  elseif type(_G.canaccesstable) == "function" then
    local ok, allowed = pcall(_G.canaccesstable, opts)
    if not ok or allowed ~= true then return nil end
  end
  local ok, value = pcall(rawget, opts, key)
  if not ok or not CanAccess(value) then return nil end
  return value
end

local function Clamp(value, minimum, maximum)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function SafeLabel(value, fallback, maximum)
  local text
  local util = RDL.Util
  if util and type(util.SafeToString) == "function" then
    local ok, rendered = pcall(util.SafeToString, util, value)
    if ok and type(rendered) == "string" then text = rendered end
  elseif CanAccess(value) then
    local valueType = type(value)
    if valueType == "string" then
      text = value
    elseif valueType == "number" or valueType == "boolean" then
      text = tostring(value)
    end
  end

  if type(text) ~= "string" or text == "" then text = fallback end
  if #text > maximum then text = text:sub(1, maximum) end
  return text
end

local function Identity(addonName, label)
  local addon = SafeLabel(addonName, "?", 128)
  local name = SafeLabel(label, "?", 256)
  return addon, name, addon .. ":" .. name
end

local function AlertThrottleOK(key, nowMs, minimumIntervalMs)
  minimumIntervalMs = SafeNumber(minimumIntervalMs, 0)
  if minimumIntervalMs <= 0 then return true end
  local last = Mem._lastAlert[key]
  if Finite(last) then
    local elapsed = nowMs - last
    if elapsed >= 0 and elapsed < minimumIntervalMs then return false end
  end
  Mem._lastAlert[key] = nowMs
  return true
end

function Mem:GetKB()
  if type(_G.collectgarbage) == "function" then
    local ok, value = pcall(_G.collectgarbage, "count")
    if ok and Finite(value) then return value end
  end
  if type(_G.gcinfo) == "function" then
    local ok, value = pcall(_G.gcinfo)
    if ok and Finite(value) then return value end
  end
  return nil
end

local function UpdateStats(key, deltaKB)
  local stats = Mem._stats[key]
  if not stats then
    if (tonumber(Mem._statsCount) or 0) >= MAX_STAT_KEYS then
      Mem._droppedStats = (tonumber(Mem._droppedStats) or 0) + 1
      return nil
    end
    stats = { n = 0, total = 0, max = 0, ema = 0, last = 0 }
    Mem._stats[key] = stats
    Mem._statsCount = (tonumber(Mem._statsCount) or 0) + 1
  end

  stats.n = (stats.n or 0) + 1
  stats.total = (stats.total or 0) + deltaKB
  stats.last = deltaKB
  if deltaKB > (stats.max or 0) then stats.max = deltaKB end

  local alpha = 0.15
  if stats.n <= 1 then
    stats.ema = deltaKB
  else
    stats.ema = (stats.ema or deltaKB) * (1 - alpha) + deltaKB * alpha
  end
  return stats
end

local function Record(addonName, funcName, deltaKB, opts, settings)
  local addon, func, key = Identity(addonName, funcName)
  local stats = UpdateStats(key, deltaKB)
  if not stats then return false end

  if RDL.Bus and type(RDL.Bus.Metric) == "function" then
    local minimum = Option(opts, "metricMinInterval")
      or (type(settings) == "table" and rawget(settings, "metricMinInterval"))
      or 1
    pcall(RDL.Bus.Metric, RDL.Bus, addon, "mem_kb:" .. func,
      deltaKB, "KB", { minInterval = SafeNumber(minimum, 1) })
  end

  local spikeKB = SafeNumber(Option(opts, "spikeKB"), nil)
    or (type(settings) == "table" and SafeNumber(rawget(settings, "memSpikeKB"), nil))
    or 64
  spikeKB = Clamp(spikeKB, 1, 1024 * 1024)

  if deltaKB >= spikeKB and type(RDL.Alert) == "function" then
    local alertMinimum = SafeNumber(Option(opts, "alertMinIntervalMs"), nil)
      or (type(settings) == "table" and SafeNumber(rawget(settings, "memAlertMinIntervalMs"), nil))
      or 2000
    local now = NowMs()
    if AlertThrottleOK(key, now, alertMinimum) then
      pcall(RDL.Alert, RDL, addon, "MEM_SPIKE",
        func .. " +" .. string.format("%.1f", deltaKB) .. "KB", {
          dKB = deltaKB,
          ema = stats.ema,
          max = stats.max,
          n = stats.n,
        }, "WARN")
    end
  end
  return true
end

function Mem:Measure(addonName, funcName, fn, opts, ...)
  if not IsCallable(fn) then return nil end

  local settings = GetSettings()
  if settings and rawget(settings, "enablePerfProfiling") == false then
    return fn(...)
  end

  local before = self:GetKB()
  -- Preserve the target's original hard-error behavior.
  local result = Pack(fn(...))
  local after = self:GetKB()

  if Finite(before) and Finite(after) then
    pcall(Record, addonName, funcName, after - before, opts, settings)
  end
  return Unpack(result, 1, result.n)
end

function Mem:Wrap(addonName, funcName, fn, opts)
  if not IsCallable(fn) then return nil end
  return function(...)
    return Mem:Measure(addonName, funcName, fn, opts, ...)
  end
end

function Mem:Sample(addonName, tag, opts)
  local settings = GetSettings()
  if settings and rawget(settings, "enablePerfProfiling") == false then return false end

  local nowKB = self:GetKB()
  if not Finite(nowKB) then return false end

  local addon, safeTag, key = Identity(addonName, tag or "sample")
  local last = self._lastSample[key]
  if last == nil then
    if (tonumber(self._sampleCount) or 0) >= MAX_SAMPLE_KEYS then
      self._droppedSamples = (tonumber(self._droppedSamples) or 0) + 1
      return false
    end
    self._sampleCount = (tonumber(self._sampleCount) or 0) + 1
  end
  self._lastSample[key] = nowKB

  if RDL.Bus and type(RDL.Bus.Metric) == "function" then
    if Finite(last) then
      local minimum = Option(opts, "metricMinInterval")
        or (type(settings) == "table" and rawget(settings, "metricMinInterval"))
        or 1
      pcall(RDL.Bus.Metric, RDL.Bus, addon,
        "mem_kb_delta:" .. safeTag, nowKB - last, "KB", { minInterval = SafeNumber(minimum, 1) })
    else
      pcall(RDL.Bus.Metric, RDL.Bus, addon,
        "mem_kb:" .. safeTag, nowKB, "KB", { minInterval = 0 })
    end
  end
  return true
end

function Mem:StartWatcher()
  local settings = GetSettings() or {}
  if rawget(settings, "memWatchEnabled") ~= true then return false end
  if type(_G.C_Timer) ~= "table" or type(_G.C_Timer.NewTicker) ~= "function" then return false end
  if self._ticker then return true end

  local interval = SafeNumber(rawget(settings, "memWatchIntervalSec"), 2)
  interval = Clamp(interval, 0.2, 3600)
  local last = self:GetKB()

  local ok, ticker = pcall(_G.C_Timer.NewTicker, interval, function()
    local now = Mem:GetKB()
    if not Finite(now) then return end
    if not Finite(last) then
      last = now
      return
    end

    local deltaKB = now - last
    last = now

    if RDL.Bus and type(RDL.Bus.Metric) == "function" then
      pcall(RDL.Bus.Metric, RDL.Bus, "RothDevLib",
        "mem_kb_global_delta", deltaKB, "KB", { minInterval = interval })
    end

    local spikeKB = SafeNumber(rawget(settings, "memWatchSpikeKB"), 256)
    if deltaKB >= spikeKB and type(RDL.Alert) == "function" then
      local alertMinimum = SafeNumber(rawget(settings, "memAlertMinIntervalMs"), 2000)
      local nowMs = NowMs()
      if AlertThrottleOK("@watcher", nowMs, alertMinimum) then
        pcall(RDL.Alert, RDL, "RothDevLib", "MEM_WATCH",
          "Global mem +" .. string.format("%.1f", deltaKB) .. "KB", {
            dKB = deltaKB,
            intervalSec = interval,
          }, "WARN")
      end
    end
  end)

  if ok and ticker then
    self._ticker = ticker
    return true
  end
  return false
end

function Mem:StopWatcher()
  local ticker = self._ticker
  self._ticker = nil
  if ticker and type(ticker.Cancel) == "function" then
    pcall(ticker.Cancel, ticker)
  end
end

function Mem:ResetStats()
  if self._stats then
    for key in pairs(self._stats) do self._stats[key] = nil end
  end
  if self._lastAlert then
    for key in pairs(self._lastAlert) do self._lastAlert[key] = nil end
  end
  if self._lastSample then
    for key in pairs(self._lastSample) do self._lastSample[key] = nil end
  end
  self._statsCount = 0
  self._sampleCount = 0
  self._droppedStats = 0
  self._droppedSamples = 0
end

function Mem:GetStats()
  local output = {}
  for key, stats in pairs(self._stats or {}) do
    if type(key) == "string" and type(stats) == "table" then
      output[key] = {
        n = SafeNumber(stats.n, 0),
        total = SafeNumber(stats.total, 0),
        max = SafeNumber(stats.max, 0),
        ema = SafeNumber(stats.ema, 0),
        last = SafeNumber(stats.last, 0),
      }
    end
  end
  return output
end

function Mem:GetRegistryStats()
  return {
    stats = tonumber(self._statsCount) or 0,
    maxStats = MAX_STAT_KEYS,
    samples = tonumber(self._sampleCount) or 0,
    maxSamples = MAX_SAMPLE_KEYS,
    droppedStats = tonumber(self._droppedStats) or 0,
    droppedSamples = tonumber(self._droppedSamples) or 0,
  }
end
