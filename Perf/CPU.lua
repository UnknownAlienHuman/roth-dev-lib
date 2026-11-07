-- !RothDevLib/Perf/CPU.lua
-- Lightweight synchronous call profiling. Profiling failures never alter the
-- wrapped function's return tuple or turn a successful call into an error.

local RDL = _G.RothDevLib
if not RDL then return end

local CPU = {}
RDL.CPU = CPU

local MAX_STAT_KEYS = 1024

CPU._stats = CPU._stats or {}
CPU._lastAlert = CPU._lastAlert or {}
CPU._statsCount = 0
CPU._droppedStats = 0

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

local function Identity(addonName, funcName)
  local addon = SafeLabel(addonName, "?", 128)
  local func = SafeLabel(funcName, "?", 256)
  return addon, func, addon .. ":" .. func
end

local function ShouldSample(opts, settings)
  local configured = Option(opts, "sampleRate")
  if configured == nil and type(settings) == "table" then
    configured = rawget(settings, "cpuSampleRate")
  end

  local sampleRate = SafeNumber(configured, 1)
  if sampleRate <= 0 then return false end
  if sampleRate >= 1 then return true end
  return math.random() < sampleRate
end

local function AlertThrottleOK(key, nowMs, minimumIntervalMs)
  minimumIntervalMs = SafeNumber(minimumIntervalMs, 0)
  if minimumIntervalMs <= 0 then return true end
  local last = CPU._lastAlert[key]
  if Finite(last) then
    local elapsed = nowMs - last
    if elapsed >= 0 and elapsed < minimumIntervalMs then return false end
  end
  CPU._lastAlert[key] = nowMs
  return true
end

local function UpdateStats(key, elapsedMs)
  local stats = CPU._stats[key]
  if not stats then
    if (tonumber(CPU._statsCount) or 0) >= MAX_STAT_KEYS then
      CPU._droppedStats = (tonumber(CPU._droppedStats) or 0) + 1
      return nil
    end
    stats = { n = 0, total = 0, max = 0, ema = 0, last = 0 }
    CPU._stats[key] = stats
    CPU._statsCount = (tonumber(CPU._statsCount) or 0) + 1
  end

  stats.n = (stats.n or 0) + 1
  stats.total = (stats.total or 0) + elapsedMs
  stats.last = elapsedMs
  if elapsedMs > (stats.max or 0) then stats.max = elapsedMs end

  local alpha = 0.15
  if stats.n <= 1 then
    stats.ema = elapsedMs
  else
    stats.ema = (stats.ema or elapsedMs) * (1 - alpha) + elapsedMs * alpha
  end
  return stats
end

local function Record(addonName, funcName, elapsedMs, opts, settings)
  local addon, func, key = Identity(addonName, funcName)
  local stats = UpdateStats(key, elapsedMs)
  if not stats then return false end

  if RDL.Bus and type(RDL.Bus.Metric) == "function" then
    local minimum = Option(opts, "metricMinInterval")
      or (type(settings) == "table" and rawget(settings, "metricMinInterval"))
      or 1
    pcall(RDL.Bus.Metric, RDL.Bus, addon, "cpu_ms:" .. func,
      elapsedMs, "ms", { minInterval = SafeNumber(minimum, 1) })
  end

  local spikeMs = SafeNumber(Option(opts, "spikeMs"), nil)
    or (type(settings) == "table" and SafeNumber(rawget(settings, "cpuSpikeMs"), nil))
    or 16
  spikeMs = Clamp(spikeMs, 1, 5000)

  if elapsedMs >= spikeMs and type(RDL.Alert) == "function" then
    local alertMinimum = SafeNumber(Option(opts, "alertMinIntervalMs"), nil)
      or (type(settings) == "table" and SafeNumber(rawget(settings, "cpuAlertMinIntervalMs"), nil))
      or 2000
    local now = NowMs()
    if AlertThrottleOK(key, now, alertMinimum) then
      pcall(RDL.Alert, RDL, addon, "CPU_SPIKE",
        func .. " took " .. string.format("%.2f", elapsedMs) .. "ms", {
          ms = elapsedMs,
          ema = stats.ema,
          max = stats.max,
          n = stats.n,
        }, "WARN")
    end
  end
  return true
end

function CPU:Measure(addonName, funcName, fn, opts, ...)
  if not IsCallable(fn) then return nil end

  local settings = GetSettings()
  if settings and rawget(settings, "enablePerfProfiling") == false then
    return fn(...)
  end
  if not ShouldSample(opts, settings) then
    return fn(...)
  end

  local startedAt = NowMs()
  -- Do not catch target errors here. Profile/WrapProfiled keep the original
  -- hard-error behavior of the wrapped function.
  local result = Pack(fn(...))
  local elapsedMs = NowMs() - startedAt
  if not Finite(elapsedMs) or elapsedMs < 0 then elapsedMs = 0 end

  -- Telemetry is best-effort and cannot affect function semantics.
  pcall(Record, addonName, funcName, elapsedMs, opts, settings)
  return Unpack(result, 1, result.n)
end

function CPU:Wrap(addonName, funcName, fn, opts)
  if not IsCallable(fn) then return nil end
  return function(...)
    return CPU:Measure(addonName, funcName, fn, opts, ...)
  end
end

function CPU:ResetStats()
  if self._stats then
    for key in pairs(self._stats) do self._stats[key] = nil end
  end
  if self._lastAlert then
    for key in pairs(self._lastAlert) do self._lastAlert[key] = nil end
  end
  self._statsCount = 0
  self._droppedStats = 0
end

function CPU:GetStats()
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

function CPU:GetRegistryStats()
  return {
    keys = tonumber(self._statsCount) or 0,
    maximum = MAX_STAT_KEYS,
    dropped = tonumber(self._droppedStats) or 0,
  }
end
