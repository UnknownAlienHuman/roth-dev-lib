-- !RothDevLib/Perf/Mem.lua
-- Phase 3: Memory watcher helpers.
--
-- Goals:
--   * Track memory deltas around critical functions (per-addon/module attribution).
--   * Optionally sample global memory periodically.
--   * Emit metrics (Bus:Metric) and alerts on spikes.

local RDL = _G.RothDevLib
if not RDL then return end

local Mem = {}
RDL.Mem = Mem

Mem._stats = Mem._stats or {}
Mem._lastAlert = Mem._lastAlert or {}
Mem._lastSample = Mem._lastSample or {}
Mem._ticker = Mem._ticker or nil

local function NowMs()
  if type(debugprofilestop) == "function" then return debugprofilestop() end
  if type(GetTime) == "function" then return GetTime() * 1000 end
  return (time() or 0) * 1000
end

local function GetSettings()
  return (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or nil
end

local function Clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function Key(addonName, funcName)
  return tostring(addonName or "?") .. ":" .. tostring(funcName or "?")
end

local function AlertThrottleOK(k, nowMs, minIntervalMs)
  minIntervalMs = tonumber(minIntervalMs) or 0
  if minIntervalMs <= 0 then return true end
  local last = Mem._lastAlert[k]
  if last and (nowMs - last) < minIntervalMs then return false end
  Mem._lastAlert[k] = nowMs
  return true
end

function Mem:GetKB()
  -- WoW: collectgarbage("count") returns KB.
  if type(collectgarbage) == "function" then
    local ok, v = pcall(collectgarbage, "count")
    if ok and type(v) == "number" then return v end
  end
  -- Legacy: gcinfo() used to return KB.
  if type(gcinfo) == "function" then
    local ok, v = pcall(gcinfo)
    if ok and type(v) == "number" then return v end
  end
  return nil
end

local function UpdateStats(k, dKB)
  local s = Mem._stats[k]
  if not s then
    s = { n = 0, total = 0, max = 0, ema = 0, last = 0 }
    Mem._stats[k] = s
  end

  s.n = (s.n or 0) + 1
  s.total = (s.total or 0) + dKB
  s.last = dKB
  if dKB > (s.max or 0) then s.max = dKB end

  local a = 0.15
  if s.n <= 1 then s.ema = dKB
  else s.ema = (s.ema or dKB) * (1 - a) + dKB * a end

  return s
end

-- Measure memory delta around a call.
function Mem:Measure(addonName, funcName, fn, opts, ...)
  if type(fn) ~= "function" then return nil end

  local settings = GetSettings()
  if settings and settings.enablePerfProfiling == false then
    return fn(...)
  end

  local before = self:GetKB()
  local r1, r2, r3, r4, r5, r6 = fn(...)
  local after = self:GetKB()

  if type(before) ~= "number" or type(after) ~= "number" then
    return r1, r2, r3, r4, r5, r6
  end

  local dKB = after - before
  local k = Key(addonName, funcName)
  local s = UpdateStats(k, dKB)

  -- Metric
  if RDL.Bus and RDL.Bus.Metric then
    local mopts = { minInterval = (opts and opts.metricMinInterval) or (settings and settings.metricMinInterval) or 1 }
    RDL.Bus:Metric(addonName, "mem_kb:" .. tostring(funcName), dKB, "KB", mopts)
  end

  -- Alert on spikes
  local spikeKB = (opts and tonumber(opts.spikeKB)) or (settings and tonumber(settings.memSpikeKB)) or 64
  spikeKB = Clamp(spikeKB, 1, 1024 * 1024)

  if dKB >= spikeKB and RDL.Alert then
    local now = NowMs()
    local alertMin = (opts and tonumber(opts.alertMinIntervalMs)) or (settings and tonumber(settings.memAlertMinIntervalMs)) or 2000
    if AlertThrottleOK("mem:" .. k, now, alertMin) then
      RDL:Alert(addonName, "MEM_SPIKE", tostring(funcName) .. " +" .. string.format("%.1f", dKB) .. "KB", {
        dKB = dKB,
        ema = s and s.ema,
        max = s and s.max,
        n = s and s.n,
      }, "WARN")
    end
  end

  return r1, r2, r3, r4, r5, r6
end

function Mem:Wrap(addonName, funcName, fn, opts)
  if type(fn) ~= "function" then return fn end
  return function(...)
    return Mem:Measure(addonName, funcName, fn, opts, ...)
  end
end

-- Sample global memory for a given addon/tag and emit a delta metric.
-- This does not provide true per-addon memory; it attributes the delta to the moment the addon calls Sample.
function Mem:Sample(addonName, tag, opts)
  local settings = GetSettings()
  if settings and settings.enablePerfProfiling == false then return end

  local nowKB = self:GetKB()
  if type(nowKB) ~= "number" then return end

  local key = tostring(addonName or "?") .. ":" .. tostring(tag or "sample")
  local last = self._lastSample[key]
  self._lastSample[key] = nowKB

  if type(last) == "number" then
    local dKB = nowKB - last
    if RDL.Bus and RDL.Bus.Metric then
      local mopts = { minInterval = (opts and opts.metricMinInterval) or (settings and settings.metricMinInterval) or 1 }
      RDL.Bus:Metric(addonName, "mem_kb_delta:" .. tostring(tag), dKB, "KB", mopts)
    end
  else
    if RDL.Bus and RDL.Bus.Metric then
      local mopts = { minInterval = 0 }
      RDL.Bus:Metric(addonName, "mem_kb:" .. tostring(tag), nowKB, "KB", mopts)
    end
  end
end

-- Optional: periodic global memory sampling.
function Mem:StartWatcher()
  local settings = GetSettings() or {}
  if settings.memWatchEnabled ~= true then return end
  if type(C_Timer) ~= "table" or type(C_Timer.NewTicker) ~= "function" then return end

  if self._ticker then return end

  local interval = tonumber(settings.memWatchIntervalSec) or 2
  if interval < 0.2 then interval = 0.2 end

  local last = self:GetKB()
  self._ticker = C_Timer.NewTicker(interval, function()
    local now = Mem:GetKB()
    if type(now) ~= "number" then return end
    if type(last) ~= "number" then last = now return end

    local dKB = now - last
    last = now

    if RDL.Bus and RDL.Bus.Metric then
      RDL.Bus:Metric("RothDevLib", "mem_kb_global_delta", dKB, "KB", { minInterval = interval })
    end

    local spike = tonumber(settings.memWatchSpikeKB) or 256
    if dKB >= spike and RDL.Alert then
      local nowMs = NowMs()
      if AlertThrottleOK("memwatch:global", nowMs, tonumber(settings.memAlertMinIntervalMs) or 2000) then
        RDL:Alert("RothDevLib", "MEM_WATCH", "Global mem +" .. string.format("%.1f", dKB) .. "KB", { dKB = dKB, intervalSec = interval }, "WARN")
      end
    end
  end)
end

function Mem:StopWatcher()
  if self._ticker and type(self._ticker.Cancel) == "function" then
    pcall(function() self._ticker:Cancel() end)
  end
  self._ticker = nil
end

function Mem:ResetStats()
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
  if self._lastSample then
    for k in pairs(self._lastSample) do
      self._lastSample[k] = nil
    end
  end
end

function Mem:GetStats()
  return self._stats
end
