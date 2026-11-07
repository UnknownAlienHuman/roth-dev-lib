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

local function NowMs()
  if type(_G.debugprofilestop) == "function" then
    local ok, value = pcall(_G.debugprofilestop)
    if ok and type(value) == "number" then return value end
  end
  if type(_G.GetTime) == "function" then
    local ok, value = pcall(_G.GetTime)
    if ok and type(value) == "number" then return value * 1000 end
  end
  if type(_G.time) == "function" then
    local ok, value = pcall(_G.time)
    if ok and type(value) == "number" then return value * 1000 end
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
  if type(opts) ~= "table" then return nil end
  local ok, value = pcall(rawget, opts, key)
  if ok then return value end
  return nil
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
  else
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
  minimumIntervalMs = tonumber(minimumIntervalMs) or 0
  if minimumIntervalMs <= 0 then return true end
  local last = Mem._lastAlert[key]
  if last and (nowMs - last) < minimumIntervalMs then return false end
  Mem._lastAlert[key] = nowMs
  return true
end

function Mem:GetKB()
  if type(_G.collectgarbage) == "function" then
    local ok, value = pcall(_G.collectgarbage, "count")
    if ok and type(value) == "number" then return value end
  end
  if type(_G.gcinfo) == "function" then
    local ok, value = pcall(_G.gcinfo)
    if ok and type(value) == "number" then return value end
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
      deltaKB, "KB", { minInterval = minimum })
  end

  local spikeKB = tonumber(Option(opts, "spikeKB"))
    or (type(settings) == "table" and tonumber(rawget(settings, "memSpikeKB")))
    or 64
  spikeKB = Clamp(spikeKB, 1, 1024 * 1024)

  if deltaKB >= spikeKB and type(RDL.Alert) == "function" then
    local alertMinimum = tonumber(Option(opts, "alertMinIntervalMs"))
      or (type(settings) == "table" and tonumber(rawget(settings, "memAlertMinIntervalMs")))
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
  if type(fn) ~= "function" then return nil end

  local settings = GetSettings()
  if settings and rawget(settings, "enablePerfProfiling") == false then
    return fn(...)
  end

  local before = self:GetKB()
  -- Preserve the target's original hard-error behavior.
  local result = Pack(fn(...))
  local after = self:GetKB()

  if type(before) == "number" and type(after) == "number" then
    pcall(Record, addonName, funcName, after - before, opts, settings)
  end
  return Unpack(result, 1, result.n)
end

function Mem:Wrap(addonName, funcName, fn, opts)
  if type(fn) ~= "function" then return fn end
  return function(...)
    return Mem:Measure(addonName, funcName, fn, opts, ...)
  end
end

function Mem:Sample(addonName, tag, opts)
  local settings = GetSettings()
  if settings and rawget(settings, "enablePerfProfiling") == false then return false end

  local nowKB = self:GetKB()
  if type(nowKB) ~= "number" then return false end

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
    if type(last) == "number" then
      local minimum = Option(opts, "metricMinInterval")
        or (type(settings) == "table" and rawget(settings, "metricMinInterval"))
        or 1
      pcall(RDL.Bus.Metric, RDL.Bus, addon,
        "mem_kb_delta:" .. safeTag, nowKB - last, "KB", { minInterval = minimum })
    else
      pcall(RDL.Bus.Metric, RDL.Bus, addon,
        "mem_kb:" .. safeTag, nowKB, "KB", { minInterval = 0 })
    end
  end
  return true
end

function Mem:StartWatcher()
  local settings = GetSettings() or {}
  if rawget(settings, "memWatchEnabled") ~= true then return end
  if type(_G.C_Timer) ~= "table" or type(_G.C_Timer.NewTicker) ~= "function" then return end
  if self._ticker then return end

  local interval = tonumber(rawget(settings, "memWatchIntervalSec")) or 2
  interval = Clamp(interval, 0.2, 3600)
  local last = self:GetKB()

  local ok, ticker = pcall(_G.C_Timer.NewTicker, interval, function()
    local now = Mem:GetKB()
    if type(now) ~= "number" then return end
    if type(last) ~= "number" then
      last = now
      return
    end

    local deltaKB = now - last
    last = now

    if RDL.Bus and type(RDL.Bus.Metric) == "function" then
      pcall(RDL.Bus.Metric, RDL.Bus, "RothDevLib",
        "mem_kb_global_delta", deltaKB, "KB", { minInterval = interval })
    end

    local spikeKB = tonumber(rawget(settings, "memWatchSpikeKB")) or 256
    if deltaKB >= spikeKB and type(RDL.Alert) == "function" then
      local alertMinimum = tonumber(rawget(settings, "memAlertMinIntervalMs")) or 2000
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

  if ok then self._ticker = ticker end
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
  return self._stats
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
