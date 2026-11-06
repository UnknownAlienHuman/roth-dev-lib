-- !RothDevLib/Integration/Bus.lua
-- Bounded per-addon breadcrumbs and lightweight metrics.

local RDL = _G.RothDevLib
local Bus = {}
RDL.Bus = Bus

Bus._addons = Bus._addons or {}
Bus._metrics = Bus._metrics or {}

local function NowSec()
  return time()
end

local function NowClock()
  if type(GetTime) == "function" then return GetTime() end
  return time()
end

local function Clamp(value, minimum, maximum)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function IsOrdinary(value)
  local SG = RDL.SecretGuard
  if SG and type(SG.CanAccess) == "function" and not SG:CanAccess(value) then
    return false
  end
  if SG and type(SG.IsSecret) == "function" and SG:IsSecret(value) then
    return false
  end
  return true
end

local function OrdinaryString(value, maxBytes)
  if not IsOrdinary(value) or type(value) ~= "string" or value == "" then
    return nil
  end
  if maxBytes and #value > maxBytes then
    return value:sub(1, maxBytes)
  end
  return value
end

local function OrdinaryTable(value)
  if not IsOrdinary(value) then return nil end
  if value == nil or type(value) ~= "table" then return nil end

  local SG = RDL.SecretGuard
  if SG and type(SG.CanAccessTable) == "function" and not SG:CanAccessTable(value) then
    return nil
  end
  return value
end

local function OrdinaryNumber(value)
  if not IsOrdinary(value) or type(value) ~= "number" then return nil end
  if value ~= value or value == math.huge or value == -math.huge then return nil end
  return value
end

local function Truncate(value, maximum)
  if type(value) ~= "string" then return value end
  if #value <= maximum then return value end
  return value:sub(1, maximum) .. "<truncated>"
end

local function NormalizeOptions(opts)
  opts = OrdinaryTable(opts)
  if not opts then return nil end

  local normalized = {}
  local maxBreadcrumbs = OrdinaryNumber(opts.maxBreadcrumbs)
  if maxBreadcrumbs then
    normalized.maxBreadcrumbs = Clamp(math.floor(maxBreadcrumbs), 10, 400)
  end

  local metricMinInterval = OrdinaryNumber(opts.metricMinInterval)
  if metricMinInterval == nil then
    metricMinInterval = OrdinaryNumber(opts.minInterval)
  end
  if metricMinInterval then
    normalized.metricMinInterval = Clamp(metricMinInterval, 0, 3600)
  end
  return normalized
end

local function PushRing(addon, item)
  local maximum = addon.max or 80
  local index = (addon.head or 0) + 1
  if index > maximum then index = 1 end
  addon.head = index
  addon.ring[index] = item
  if (addon.size or 0) < maximum then
    addon.size = (addon.size or 0) + 1
  end
end

local function ResizeRing(addon, newMaximum)
  local oldMaximum = tonumber(addon.max) or newMaximum
  if oldMaximum == newMaximum then
    addon.max = newMaximum
    return
  end

  local oldRing = addon.ring or {}
  local oldSize = math.min(tonumber(addon.size) or 0, oldMaximum)
  local keep = math.min(oldSize, newMaximum)
  local newestIndex = tonumber(addon.head) or 0
  local ordered = {}

  for offset = keep - 1, 0, -1 do
    local index = newestIndex - offset
    while index < 1 do index = index + oldMaximum end
    local item = oldRing[index]
    if item ~= nil then ordered[#ordered + 1] = item end
  end

  addon.max = newMaximum
  addon.head = 0
  addon.size = 0
  addon.ring = {}
  for index = 1, #ordered do
    PushRing(addon, ordered[index])
  end
end

local function DefaultMaximum()
  local settings = RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings() or nil
  local configured = settings and OrdinaryNumber(settings.maxBreadcrumbsPerAddon) or nil
  return Clamp(math.floor(configured or 80), 10, 400)
end

local function EnsureAddon(self, addonName, opts)
  addonName = OrdinaryString(addonName, 128)
  if not addonName then return nil end

  self._addons = self._addons or {}
  local addon = self._addons[addonName]
  local normalizedOpts = NormalizeOptions(opts)

  local maximum = DefaultMaximum()
  if normalizedOpts and normalizedOpts.maxBreadcrumbs then
    maximum = normalizedOpts.maxBreadcrumbs
  elseif addon and addon.opts and addon.opts.maxBreadcrumbs then
    maximum = addon.opts.maxBreadcrumbs
  end

  if not addon then
    addon = {
      name = addonName,
      opts = normalizedOpts or {},
      max = maximum,
      head = 0,
      size = 0,
      ring = {},
    }
    self._addons[addonName] = addon
  else
    addon.name = addonName
    addon.opts = normalizedOpts or addon.opts or {}
    addon.ring = addon.ring or {}
    addon.head = tonumber(addon.head) or 0
    addon.size = tonumber(addon.size) or 0
    ResizeRing(addon, maximum)
  end
  return addon
end

function Bus:Init()
  self._addons = self._addons or {}
  self._metrics = self._metrics or {}
end

function Bus:RegisterAddon(addonName, opts)
  return EnsureAddon(self, addonName, opts)
end

function Bus:Breadcrumb(addonName, category, message, data)
  local addon = EnsureAddon(self, addonName)
  if not addon then return end

  local U = RDL.Util
  local categoryText = U and U.SafeToString and U:SafeToString(category) or "<category>"
  local messageText = U and U.SafeToString and U:SafeToString(message) or "<message>"
  if U and U.FilterSecretEscapes then
    categoryText = U:FilterSecretEscapes(categoryText)
    messageText = U:FilterSecretEscapes(messageText)
  end
  categoryText = Truncate(categoryText, 128)
  messageText = Truncate(messageText, 4096)

  local payload
  local ordinaryData
  if U and U.Scrub then
    ordinaryData = U:Scrub(data)
  else
    ordinaryData = data
  end
  if ordinaryData ~= nil then
    if type(ordinaryData) == "table" and U and U.SafeSerializeTable then
      payload = U:SafeSerializeTable(ordinaryData)
    elseif U and U.SafeToString then
      payload = U:SafeToString(ordinaryData)
    else
      payload = "<unavailable>"
    end
  end

  payload = Truncate(payload, 8192)

  PushRing(addon, {
    ts = NowSec(),
    clock = NowClock(),
    cat = categoryText,
    msg = messageText,
    data = payload,
  })
end

function Bus:Metric(addonName, name, value, unit, opts)
  local addon = EnsureAddon(self, addonName)
  if not addon then return end

  if not IsOrdinary(name) then return end
  local U = RDL.Util
  local metricName = U and U.SafeToString and U:SafeToString(name) or nil
  if not metricName or metricName == "" then return end
  metricName = metricName:sub(1, 160)

  local settings = RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings() or nil
  local normalizedOpts = NormalizeOptions(opts)

  local minInterval = normalizedOpts and normalizedOpts.metricMinInterval
    or addon.opts and addon.opts.metricMinInterval
    or settings and OrdinaryNumber(settings.metricMinInterval)
    or 1
  minInterval = Clamp(minInterval, 0, 3600)

  local key = addon.name .. "\031" .. metricName
  local now = NowClock()
  local last = self._metrics[key]
  if last and (now - last) < minInterval then return end
  self._metrics[key] = now

  self:Breadcrumb(addon.name, "metric", metricName, { value = value, unit = unit })
end

function Bus:GetBreadcrumbSnapshot(addonName, count)
  addonName = OrdinaryString(addonName, 128)
  if not addonName then return nil end

  local addon = self._addons and self._addons[addonName]
  if not addon or not addon.ring or (addon.size or 0) == 0 then return nil end

  count = OrdinaryNumber(count) or 12
  count = math.floor(count)
  if count <= 0 then return nil end
  count = math.min(count, addon.size, addon.max)

  local out = {}
  local index = addon.head
  for position = 1, count do
    local item = addon.ring[index]
    if item ~= nil then out[#out + 1] = item end
    index = index - 1
    if index < 1 then index = addon.max end
  end
  return out
end

function Bus:GetErrorContext(addonName)
  local settings = RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings() or nil
  if not settings or settings.includeBreadcrumbsInErrors == false then return nil end
  local count = OrdinaryNumber(settings.breadcrumbsPerError) or 12
  return self:GetBreadcrumbSnapshot(addonName, count)
end

function Bus:Alert(addonName, code, message, data, level)
  local U = RDL.Util
  local codeText = U and U.SafeToString and U:SafeToString(code) or "alert"
  if codeText == "nil" or codeText == "" then codeText = "alert" end
  self:Breadcrumb(addonName, "alert", codeText, {
    message = message,
    level = level,
    data = data,
  })
end

function Bus:GetAllAddonNames()
  local out = {}
  if self._addons then
    for name in pairs(self._addons) do
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

function Bus:GetAddonStats(addonName)
  addonName = OrdinaryString(addonName, 128)
  if not addonName then return nil end

  local addon = self._addons and self._addons[addonName]
  if not addon then return nil end
  return {
    name = addon.name,
    size = addon.size or 0,
    max = addon.max or 80,
    head = addon.head or 0,
  }
end

function Bus:ResetAll()
  if self._addons then
    for _, addon in pairs(self._addons) do
      addon.head = 0
      addon.size = 0
      if addon.ring then wipe(addon.ring) end
    end
  end
  if self._metrics then wipe(self._metrics) end
end
