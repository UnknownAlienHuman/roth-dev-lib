-- !RothDevLib/Integration/Bus.lua
-- Integration bus: per-addon breadcrumbs + lightweight metrics.
-- Ported from !RothGrabber/Modules/Bus.lua.
--
-- Design goals:
--   * Safe under Secret Values (12.0+): only stringify after scrub.
--   * Fast: bounded ring buffers, no SavedVariables writes.
--   * UI-agnostic: can be used from any addon without UI present.

local RDL = _G.RothDevLib
local Bus = {}
RDL.Bus = Bus

Bus._addons = Bus._addons or {}
Bus._metrics = Bus._metrics or {}

local function NowSec() return time() end
local function NowMs()
  if type(GetTime) == "function" then return GetTime() end
  return time()
end

local function Clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function EnsureAddon(self, addonName, opts)
  if type(addonName) ~= "string" or addonName == "" then return nil end

  self._addons = self._addons or {}
  local a = self._addons[addonName]

  local settings = RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings() or nil
  local maxDefault = (settings and settings.maxBreadcrumbsPerAddon) or 80

  local max = maxDefault
  if opts and type(opts.maxBreadcrumbs) == "number" then max = opts.maxBreadcrumbs end
  max = Clamp(math.floor(max), 10, 400)

  if not a then
    a = { name = addonName, opts = opts or {}, max = max, head = 0, size = 0, ring = {} }
    self._addons[addonName] = a
  else
    a.opts = opts or a.opts or {}
    a.max = max
    a.ring = a.ring or {}
    a.head = a.head or 0
    a.size = a.size or 0
  end
  return a
end

local function PushRing(a, item)
  local max = a.max or 80
  local idx = (a.head or 0) + 1
  if idx > max then idx = 1 end
  a.head = idx
  a.ring[idx] = item
  if (a.size or 0) < max then a.size = (a.size or 0) + 1 end
end

function Bus:Init()
  self._addons = self._addons or {}
  self._metrics = self._metrics or {}
end

function Bus:RegisterAddon(addonName, opts)
  return EnsureAddon(self, addonName, opts)
end

function Bus:Breadcrumb(addonName, category, message, data)
  local a = EnsureAddon(self, addonName)
  if not a then return end

  local U = RDL.Util
  local cat = (U and U.SafeToString) and U:SafeToString(category) or tostring(category)
  local msg = (U and U.SafeToString) and U:SafeToString(message) or tostring(message)

  local payload = nil
  if data ~= nil then
    if type(data) == "table" and U and U.SafeSerializeTable then
      payload = U:SafeSerializeTable(data)
    elseif U and U.SafeToString then
      payload = U:SafeToString(data)
    else
      payload = tostring(data)
    end
  end

  PushRing(a, { ts = NowSec(), ms = NowMs(), cat = cat, msg = msg, data = payload })
end

function Bus:Metric(addonName, name, value, unit, opts)
  local a = EnsureAddon(self, addonName)
  if not a then return end

  local settings = RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings() or nil

  local minInterval = 1
  if opts and type(opts.minInterval) == "number" then
    minInterval = opts.minInterval
  elseif a.opts and type(a.opts.metricMinInterval) == "number" then
    minInterval = a.opts.metricMinInterval
  elseif settings and type(settings.metricMinInterval) == "number" then
    minInterval = settings.metricMinInterval
  end
  minInterval = math.max(0, minInterval)

  local key = addonName .. ":" .. tostring(name)
  local now = NowMs()
  local last = self._metrics[key]
  if last and (now - last) < minInterval then return end
  self._metrics[key] = now

  self:Breadcrumb(addonName, "metric", name, { value = value, unit = unit })
end

function Bus:GetBreadcrumbSnapshot(addonName, n)
  local a = self._addons and self._addons[addonName]
  if not a or not a.ring or (a.size or 0) == 0 then return nil end

  n = tonumber(n) or 12
  if n <= 0 then return nil end
  n = math.min(n, a.size)

  local out = {}
  local idx = a.head
  for i = 1, n do
    out[i] = a.ring[idx]
    idx = idx - 1
    if idx < 1 then idx = a.max end
  end
  return out
end

function Bus:GetErrorContext(addonName)
  local settings = RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings() or nil
  if not settings or settings.includeBreadcrumbsInErrors == false then return nil end
  local n = tonumber(settings.breadcrumbsPerError) or 12
  return self:GetBreadcrumbSnapshot(addonName, n)
end

function Bus:Alert(addonName, code, message, data, level)
  self:Breadcrumb(addonName, "alert", code or "alert", { message = message, level = level, data = data })
end

function Bus:GetAllAddonNames()
  local out = {}
  if self._addons then
    for name in pairs(self._addons) do
      out[#out + 1] = name
    end
  end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

function Bus:GetAddonStats(addonName)
  local a = self._addons and self._addons[addonName]
  if not a then return nil end
  return {
    name = a.name or addonName,
    size = a.size or 0,
    max = a.max or 80,
    head = a.head or 0,
  }
end

function Bus:ResetAll()
  if self._addons then
    for _, a in pairs(self._addons) do
      a.head = 0
      a.size = 0
      if a.ring then for k in pairs(a.ring) do a.ring[k] = nil end end
    end
  end
  if self._metrics then for k in pairs(self._metrics) do self._metrics[k] = nil end end
end
