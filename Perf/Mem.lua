-- !RothDevLib/Perf/Mem.lua
-- Memory-delta observations that preserve the wrapped function's complete
-- return tuple. Measurements are diagnostic traffic, not retained-memory proof.

local RDL = _G.RothDevLib
if not RDL then return end

local Mem = {}
RDL.Mem = Mem

Mem._stats = Mem._stats or {}
Mem._lastAlert = Mem._lastAlert or {}
Mem._lastSample = Mem._lastSample or {}
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

local function Key(addonName, funcName)
  return tostring(addonName or "?") .. ":" .. tostring(funcName or "?")
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
    stats = { n = 0, total = 0, max = 0, ema = 0, last = 0 }
    Mem._stats[key] = stats
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
  local key = Key(addonName, funcName)
  local stats = UpdateStats(key, deltaKB)

  if RDL.Bus and type(RDL.Bus.Metric) == "function" then
    local minimum = Option(opts, "metricMinInterval")
      or (type(settings) == "table" and rawget(settings, "metricMinInterval"))
      or 1
    pcall(RDL.Bus.Metric, RDL.Bus, addonName, "mem_kb:" .. tostring(funcName),
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
    if AlertThrottleOK("mem:" .. key, now, alertMinimum) then
      pcall(RDL.Alert, RDL, addonName, "MEM_SPIKE",
        tostring(funcName) .. " +" .. string.format("%.1f", deltaKB) .. "KB", {
          dKB = deltaKB,
          ema = stats.ema,
          max = stats.max,
          n = stats.n,
        }, "WARN")
    end
  end
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
  if settings and rawget(settings, "enablePerfProfiling") == false then return end

  local nowKB = self:GetKB()
  if type(nowKB) ~= "number" then return end

  local key = tostring(addonName or "?") .. ":" .. tostring(tag or "sample")
  local last = self._lastSample[key]
  self._lastSample[key] = nowKB

  if RDL.Bus and type(RDL.Bus.Metric) == "function" then
    if type(last) == "number" then
      local minimum = Option(opts, "metricMinInterval")
        or (type(settings) == "table" and rawget(settings, "metricMinInterval"))
        or 1
      pcall(RDL.Bus.Metric, RDL.Bus, addonName,
        "mem_kb_delta:" .. tostring(tag), nowKB - last, "KB", { minInterval = minimum })
    else
      pcall(RDL.Bus.Metric, RDL.Bus, addonName,
        "mem_kb:" .. tostring(tag), nowKB, "KB", { minInterval = 0 })
    end
  end
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
      if AlertThrottleOK("memwatch:global", nowMs, alertMinimum) then
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
end

function Mem:GetStats()
  return self._stats
end
