-- !RothDevLib/Core/IgnoreBounds.lua
-- Bounded persisted ignore rules. Rules remain effective after their current
-- group is evicted, but malformed or unbounded maps cannot grow SavedVariables.

local RDL = _G.RothDevLib
local DB = RDL and RDL.DB
if not DB then return end

local CurrentInit = DB.Init
local CurrentEnsureReady = DB.EnsureReady
local CurrentHandlePersistenceFailure = DB.HandlePersistenceFailure

local MAX_SIG_RULES = 1000
local MAX_ADDON_RULES = 512
local FAILURE_SIG_RULES = 100
local FAILURE_ADDON_RULES = 64
local MAX_SIG_BYTES = 4096
local MAX_ADDON_BYTES = 128
local MAX_SCAN_MULTIPLIER = 4

local function Now()
  if type(_G.time) ~= "function" then return 1 end
  local ok, value = pcall(_G.time)
  if not ok or type(value) ~= "number" or value ~= value
      or value == math.huge or value == -math.huge or value <= 0 then
    return 1
  end
  return value
end

local function RuleTimestamp(value)
  if value == true then return 0 end
  if type(value) ~= "number" or value ~= value
      or value == math.huge or value == -math.huge or value < 0 then
    return nil
  end
  return value
end

local function NormalizeMap(source, maximum, maxKeyBytes)
  if type(source) ~= "table" then return {}, 0, 0 end

  local records = {}
  local scanned, dropped = 0, 0
  local rawKey = nil
  local scanMaximum = math.max(maximum, maximum * MAX_SCAN_MULTIPLIER)

  while scanned < scanMaximum do
    local ok, nextKey, nextValue = pcall(next, source, rawKey)
    if not ok or nextKey == nil then break end
    rawKey = nextKey
    scanned = scanned + 1

    local timestamp = RuleTimestamp(nextValue)
    if type(nextKey) == "string" and nextKey ~= ""
        and #nextKey <= maxKeyBytes and timestamp ~= nil then
      records[#records + 1] = { key = nextKey, timestamp = timestamp }
    else
      dropped = dropped + 1
    end
  end

  local okMore, moreKey = pcall(next, source, rawKey)
  if okMore and moreKey ~= nil then
    -- The replacement map intentionally discards the unscanned tail. Startup
    -- work stays bounded even when persisted input is corrupted or enormous.
    dropped = dropped + 1
  end

  table.sort(records, function(a, b)
    if a.timestamp == b.timestamp then return a.key < b.key end
    return a.timestamp > b.timestamp
  end)

  local out = {}
  local keep = math.min(#records, maximum)
  for index = 1, keep do
    local record = records[index]
    out[record.key] = record.timestamp > 0 and record.timestamp or true
  end
  dropped = dropped + math.max(0, #records - keep)
  return out, keep, dropped
end

local function Root(self)
  if type(self) == "table" and type(self.raw) == "table" then return self.raw end
  if type(_G.RothDevLibDB) == "table" then return _G.RothDevLibDB end
  return nil
end

local function NormalizeRoot(self, signatureMaximum, addonMaximum, force)
  local root = Root(self)
  if type(root) ~= "table" then return false end
  if not force and type(self) == "table" and self._ignoreNormalizedRoot == root then
    return true
  end

  local ignore = type(root.ignore) == "table" and root.ignore or {}
  local sig, sigCount, sigDropped = NormalizeMap(
    ignore.sig, signatureMaximum or MAX_SIG_RULES, MAX_SIG_BYTES)
  local addon, addonCount, addonDropped = NormalizeMap(
    ignore.addon, addonMaximum or MAX_ADDON_RULES, MAX_ADDON_BYTES)

  root.ignore = { sig = sig, addon = addon }
  if type(self) == "table" then
    self._ignoreNormalizedRoot = root
    self._ignoreSigCount = sigCount
    self._ignoreAddonCount = addonCount
    self._ignoreDropped = (tonumber(self._ignoreDropped) or 0)
      + sigDropped + addonDropped
  end
  return true
end

local function OldestKey(map)
  local selected, selectedTimestamp
  for key, value in pairs(map) do
    local timestamp = RuleTimestamp(value) or 0
    if selected == nil or timestamp < selectedTimestamp
        or (timestamp == selectedTimestamp and key < selected) then
      selected = key
      selectedTimestamp = timestamp
    end
  end
  return selected
end

local function ToggleRule(self, field, key, maximum, maxKeyBytes)
  if type(key) ~= "string" or key == "" or #key > maxKeyBytes then return false end
  if type(self.EnsureReady) == "function" and self:EnsureReady() ~= true then return false end
  if not NormalizeRoot(self) then return false end

  local root = Root(self)
  local map = root.ignore[field]
  if map[key] then
    map[key] = nil
    if field == "sig" then
      self._ignoreSigCount = math.max(0, (tonumber(self._ignoreSigCount) or 1) - 1)
    else
      self._ignoreAddonCount = math.max(0, (tonumber(self._ignoreAddonCount) or 1) - 1)
    end
    return false
  end

  local countKey = field == "sig" and "_ignoreSigCount" or "_ignoreAddonCount"
  local count = tonumber(self[countKey]) or 0
  if count >= maximum then
    local evicted = OldestKey(map)
    if evicted ~= nil then
      map[evicted] = nil
      count = count - 1
      self._ignoreDropped = (tonumber(self._ignoreDropped) or 0) + 1
    end
  end

  map[key] = Now()
  self[countKey] = count + 1
  return true
end

-- SavedVariables are available at file load. Normalize only the persisted maps;
-- never construct player/session state here.
NormalizeRoot(nil, MAX_SIG_RULES, MAX_ADDON_RULES, true)

function DB:Init(...)
  if type(CurrentInit) ~= "function" then return false end
  local ready = CurrentInit(self, ...)
  if ready == true then NormalizeRoot(self, MAX_SIG_RULES, MAX_ADDON_RULES, true) end
  return ready
end

function DB:EnsureReady(...)
  if type(CurrentEnsureReady) ~= "function" then return false end
  local ready = CurrentEnsureReady(self, ...)
  if ready == true then NormalizeRoot(self) end
  return ready
end

function DB:ToggleIgnoreSig(signature)
  return ToggleRule(self, "sig", signature, MAX_SIG_RULES, MAX_SIG_BYTES)
end

function DB:ToggleIgnoreAddon(addonName)
  return ToggleRule(self, "addon", addonName, MAX_ADDON_RULES, MAX_ADDON_BYTES)
end

function DB:ClearIgnore()
  local root = Root(self)
  if type(root) ~= "table" then return false end
  root.ignore = { sig = {}, addon = {} }
  self._ignoreNormalizedRoot = root
  self._ignoreSigCount = 0
  self._ignoreAddonCount = 0
  self._ignoreDropped = 0
  return true
end

if type(CurrentHandlePersistenceFailure) == "function" then
  function DB:HandlePersistenceFailure(addonName)
    local handled = CurrentHandlePersistenceFailure(self, addonName)
    if handled == true then
      NormalizeRoot(self, FAILURE_SIG_RULES, FAILURE_ADDON_RULES, true)
    end
    return handled
  end
end

function DB:GetIgnoreStats()
  NormalizeRoot(self)
  return {
    signatures = tonumber(self._ignoreSigCount) or 0,
    maxSignatures = MAX_SIG_RULES,
    addons = tonumber(self._ignoreAddonCount) or 0,
    maxAddons = MAX_ADDON_RULES,
    dropped = tonumber(self._ignoreDropped) or 0,
  }
end
