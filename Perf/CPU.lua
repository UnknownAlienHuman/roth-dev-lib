-- !RothDevLib/Perf/CPU.lua
-- Phase 3: CPU profiling helpers.
--
-- Goals:
--   * Measure cost of wrapped callbacks (events, hooks, timers, loops).
--   * Emit lightweight metrics (Bus:Metric) without chat spam.
--   * Trigger structured ALERT entries on spikes.
--
-- Notes:
--   * debugprofilestop() exists in WoW and returns milliseconds.
--   * In case it's unavailable, we fall back to GetTime() * 1000.

local RDL = _G.RothDevLib
if not RDL then return end

local CPU = {}
RDL.CPU = CPU

CPU._stats = CPU._stats or {}
CPU._lastAlert = CPU._lastAlert or {}

local function NowMs()
  if type(debugprofilestop) == "function" then
    return debugprofilestop()
  end
  if type(GetTime) == "function" then
    return GetTime() * 1000
  end
  return (time() or 0) * 1000
end

local function Clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function GetSettings()
  return (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or nil
end

local function Key(addonName, funcName)
  return tostring(addonName or "?") .. ":" .. tostring(funcName or "?")
end

local function ShouldSample(opts, settings)
  if opts and opts.sampleRate ~= nil then
    local sr = tonumber(opts.sampleRate) or 1
    if sr <= 0 then return false end
    if sr >= 1 then return true end
    return math.random() < sr
  end
  local sr = settings and tonumber(settings.cpuSampleRate)
  if sr == nil then return true end
  if sr <= 0 then return false end
  if sr >= 1 then return true end
  return math.random() < sr
end

local function AlertThrottleOK(k, nowMs, minIntervalMs)
  minIntervalMs = tonumber(minIntervalMs) or 0
  if minIntervalMs <= 0 then return true end
  local last = CPU._lastAlert[k]
  if last and (nowMs - last) < minIntervalMs then return false end
  CPU._lastAlert[k] = nowMs
  return true
end

local function UpdateStats(k, dt)
  local s = CPU._stats[k]
  if not s then
    s = { n = 0, total = 0, max = 0, ema = 0, last = 0 }
    CPU._stats[k] = s
  end

  s.n = (s.n or 0) + 1
  s.total = (s.total or 0) + dt
  s.last = dt
  if dt > (s.max or 0) then s.max = dt end

  -- Exponential moving average (fast + stable)
  local a = 0.15
  if s.n <= 1 then s.ema = dt
  else s.ema = (s.ema or dt) * (1 - a) + dt * a end

  return s
end

-- Public: Measure a function call and emit metrics/alerts.
-- Returns: fn(...) return values.
function CPU:Measure(addonName, funcName, fn, opts, ...)
  if type(fn) ~= "function" then return nil end

  local settings = GetSettings()
  if settings and settings.enablePerfProfiling == false then
    return fn(...)
  end
  if not ShouldSample(opts, settings) then
    return fn(...)
  end

  local t0 = NowMs()
  local r1, r2, r3, r4, r5, r6 = fn(...)
  local dt = NowMs() - t0
  if dt < 0 then dt = 0 end

  local k = Key(addonName, funcName)
  local s = UpdateStats(k, dt)

  -- Metric (throttled by Bus)
  if RDL.Bus and RDL.Bus.Metric then
    local mopts = { minInterval = (opts and opts.metricMinInterval) or (settings and settings.metricMinInterval) or 1 }
    RDL.Bus:Metric(addonName, "cpu_ms:" .. tostring(funcName), dt, "ms", mopts)
  end

  -- Alert on spikes
  local spikeMs = (opts and tonumber(opts.spikeMs)) or (settings and tonumber(settings.cpuSpikeMs)) or 16
  spikeMs = Clamp(spikeMs, 1, 5000)

  if dt >= spikeMs and RDL.Alert then
    local now = NowMs()
    local alertMin = (opts and tonumber(opts.alertMinIntervalMs)) or (settings and tonumber(settings.cpuAlertMinIntervalMs)) or 2000
    if AlertThrottleOK("cpu:" .. k, now, alertMin) then
      RDL:Alert(addonName, "CPU_SPIKE", tostring(funcName) .. " took " .. string.format("%.2f", dt) .. "ms", {
        ms = dt,
        ema = s and s.ema,
        max = s and s.max,
        n = s and s.n,
      }, "WARN")
    end
  end

  return r1, r2, r3, r4, r5, r6
end

-- Public: wrap a function to profile each call.
function CPU:Wrap(addonName, funcName, fn, opts)
  if type(fn) ~= "function" then return fn end
  return function(...)
    return CPU:Measure(addonName, funcName, fn, opts, ...)
  end
end

function CPU:ResetStats()
  if self._stats then
    for k in pairs(self._stats) do
      self._stats[k] = nil
    end
  end
  if self._lastAlert then
    for k in pairs(self._lastAlert) do
      self._lastAlert[k] = nil
    end
  end
end

function CPU:GetStats()
  return self._stats
end
