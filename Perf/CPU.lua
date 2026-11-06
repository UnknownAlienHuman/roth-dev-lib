-- !RothDevLib/Perf/CPU.lua
-- Lightweight synchronous call profiling. Profiling failures never alter the
-- wrapped function's return tuple or turn a successful call into an error.

local RDL = _G.RothDevLib
if not RDL then return end

local CPU = {}
RDL.CPU = CPU

CPU._stats = CPU._stats or {}
CPU._lastAlert = CPU._lastAlert or {}

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

local function Key(addonName, funcName)
  return tostring(addonName or "?") .. ":" .. tostring(funcName or "?")
end

local function ShouldSample(opts, settings)
  local configured = Option(opts, "sampleRate")
  if configured == nil and type(settings) == "table" then
    configured = rawget(settings, "cpuSampleRate")
  end

  local sampleRate = tonumber(configured)
  if sampleRate == nil then sampleRate = 1 end
  if sampleRate <= 0 then return false end
  if sampleRate >= 1 then return true end
  return math.random() < sampleRate
end

local function AlertThrottleOK(key, nowMs, minimumIntervalMs)
  minimumIntervalMs = tonumber(minimumIntervalMs) or 0
  if minimumIntervalMs <= 0 then return true end
  local last = CPU._lastAlert[key]
  if last and (nowMs - last) < minimumIntervalMs then return false end
  CPU._lastAlert[key] = nowMs
  return true
end

local function UpdateStats(key, elapsedMs)
  local stats = CPU._stats[key]
  if not stats then
    stats = { n = 0, total = 0, max = 0, ema = 0, last = 0 }
    CPU._stats[key] = stats
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
  local key = Key(addonName, funcName)
  local stats = UpdateStats(key, elapsedMs)

  if RDL.Bus and type(RDL.Bus.Metric) == "function" then
    local minimum = Option(opts, "metricMinInterval")
      or (type(settings) == "table" and rawget(settings, "metricMinInterval"))
      or 1
    pcall(RDL.Bus.Metric, RDL.Bus, addonName, "cpu_ms:" .. tostring(funcName),
      elapsedMs, "ms", { minInterval = minimum })
  end

  local spikeMs = tonumber(Option(opts, "spikeMs"))
    or (type(settings) == "table" and tonumber(rawget(settings, "cpuSpikeMs")))
    or 16
  spikeMs = Clamp(spikeMs, 1, 5000)

  if elapsedMs >= spikeMs and type(RDL.Alert) == "function" then
    local alertMinimum = tonumber(Option(opts, "alertMinIntervalMs"))
      or (type(settings) == "table" and tonumber(rawget(settings, "cpuAlertMinIntervalMs")))
      or 2000
    local now = NowMs()
    if AlertThrottleOK("cpu:" .. key, now, alertMinimum) then
      pcall(RDL.Alert, RDL, addonName, "CPU_SPIKE",
        tostring(funcName) .. " took " .. string.format("%.2f", elapsedMs) .. "ms", {
          ms = elapsedMs,
          ema = stats.ema,
          max = stats.max,
          n = stats.n,
        }, "WARN")
    end
  end
end

function CPU:Measure(addonName, funcName, fn, opts, ...)
  if type(fn) ~= "function" then return nil end

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
  if elapsedMs < 0 then elapsedMs = 0 end

  -- Telemetry is best-effort and cannot affect function semantics.
  pcall(Record, addonName, funcName, elapsedMs, opts, settings)
  return Unpack(result, 1, result.n)
end

function CPU:Wrap(addonName, funcName, fn, opts)
  if type(fn) ~= "function" then return fn end
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
end

function CPU:GetStats()
  return self._stats
end
