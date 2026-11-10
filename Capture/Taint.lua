-- !RothDevLib/Capture/Taint.lua
-- Bounded restricted-action and restriction-state intake.

local RDL = _G.RothDevLib
local Capture = RDL and RDL.Capture
if not Capture then return end

local ACCEPTED_STATUS = { stored = true, queued = true, ignored = true }

local function SafeCopy(value, options)
  local util = RDL.Util
  if util and type(util.CopyDiagnosticValue) == "function" then
    local ok, copy = pcall(util.CopyDiagnosticValue, util, value, options or {
      maxDepth = 4,
      maxEntries = 80,
      maxNodes = 400,
      maxStringBytes = 4096,
    })
    if ok then return copy end
  end
  return nil
end

local function SafeText(value, fallback, maximum)
  local util = RDL.Util
  local text = type(fallback) == "string" and fallback or ""
  if util and type(util.SafeToString) == "function" then
    local ok, rendered = pcall(util.SafeToString, util, value)
    if ok and type(rendered) == "string" then text = rendered end
  elseif type(value) == "string" then
    text = value
  end
  if util and type(util.FilterSecretEscapes) == "function" then
    local ok, filtered = pcall(util.FilterSecretEscapes, util, text)
    if ok and type(filtered) == "string" then text = filtered end
  end
  maximum = tonumber(maximum) or 4096
  if #text > maximum then text = text:sub(1, maximum) .. "<truncated>" end
  return text
end

local function SafeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if not ok then return nil end
  return SafeCopy(value, { maxDepth = 1, maxEntries = 4, maxNodes = 8, maxStringBytes = 256 })
end

local function Stack()
  if type(_G.debugstack) ~= "function" then return "" end
  local ok, value = pcall(_G.debugstack, 3, 40, 40)
  return ok and SafeText(value, "", 128 * 1024) or ""
end

local function EnumName(enumTable, value, names)
  local ordinary = SafeCopy(value, { maxDepth = 1, maxEntries = 1, maxNodes = 2, maxStringBytes = 64 })
  if type(enumTable) == "table" then
    for index = 1, #names do
      local name = names[index]
      local ok, enumValue = pcall(rawget, enumTable, name)
      if ok and enumValue ~= nil and ordinary == enumValue then return name end
    end
  end
  return SafeText(ordinary, "<?>" , 64)
end

local function RestrictionTypeName(value)
  return EnumName(_G.Enum and _G.Enum.AddOnRestrictionType, value, {
    "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map",
  })
end

local function RestrictionStateName(value)
  return EnumName(_G.Enum and _G.Enum.AddOnRestrictionState, value, {
    "Inactive", "Activating", "Active",
  })
end

local function RestrictionSnapshot()
  local snapshot = {
    inCombat = SafeCall(_G.InCombatLockdown),
  }

  local restricted = _G.C_RestrictedActions
  local enumType = _G.Enum and _G.Enum.AddOnRestrictionType
  if type(restricted) ~= "table" or type(enumType) ~= "table" then return snapshot end

  local getState = restricted.GetAddOnRestrictionState
  local isActive = restricted.IsAddOnRestrictionActive
  if type(getState) ~= "function" and type(isActive) ~= "function" then return snapshot end

  snapshot.restrictions = {}
  local names = { "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }
  for index = 1, #names do
    local name = names[index]
    local okValue, enumValue = pcall(rawget, enumType, name)
    if okValue and enumValue ~= nil then
      local record = {}
      if type(getState) == "function" then
        local state = SafeCall(getState, enumValue)
        if state ~= nil then
          record.state = state
          record.stateName = RestrictionStateName(state)
        end
      end
      if type(isActive) == "function" then
        local active = SafeCall(isActive, enumValue)
        if active ~= nil then record.active = active end
      end
      snapshot.restrictions[name] = record
    end
  end
  return snapshot
end

local function BuildAndStore(kind, message, addonName, extra)
  if type(Capture.BuildEntry) ~= "function" or type(Capture.StoreEntry) ~= "function" then
    return nil, "unavailable"
  end
  local okBuild, entry = pcall(Capture.BuildEntry, kind, message, Stack(), nil,
    addonName, nil, SafeCopy(extra))
  if not okBuild or type(entry) ~= "table" then return nil, "build-failed" end
  local okStore, status = pcall(Capture.StoreEntry, entry)
  if not okStore or not ACCEPTED_STATUS[status] then return nil, status or "store-failed" end
  return entry, status
end

function Capture:OnTaintEvent(event, addonName, blockedText)
  if self._disabled then return nil end

  local safeEvent = SafeText(event, "<?>" , 64)
  local source = "addon"
  local addon = SafeText(addonName, "<?>" , 128)
  local blocked = SafeText(blockedText, "<?>" , 512)
  if safeEvent == "MACRO_ACTION_BLOCKED" or safeEvent == "MACRO_ACTION_FORBIDDEN" then
    source = "macro"
    blocked = SafeText(addonName, "<?>" , 512)
    addon = "BlizzardMacro"
  end

  local blockedKind = safeEvent == "ADDON_ACTION_BLOCKED" or safeEvent == "MACRO_ACTION_BLOCKED"
  local kind = blockedKind and "TAINT_BLOCKED" or "TAINT_FORBIDDEN"
  local message = kind .. ": source=" .. source .. " addon=" .. addon .. " func=" .. blocked
  local entry, status = BuildAndStore(kind, message, addon, {
    event = safeEvent,
    source = source,
    blocked = blocked,
    stackProvenance = "event-observer",
    attribution = "client-reported-blocked-addon-not-original-taint-source",
    restriction = RestrictionSnapshot(),
  })

  if entry and (status == "stored" or status == "queued") and type(RDL.Log) == "function" then
    pcall(RDL.Log, RDL, "WARN", "TAINT", "Restricted action event captured", {
      event = safeEvent,
      source = source,
      addon = addon,
    })
  end
  return entry, status
end

function Capture:OnRestrictionStateChanged(event, restrictionType, state)
  if self._disabled then return nil end

  local safeEvent = SafeText(event, "ADDON_RESTRICTION_STATE_CHANGED", 64)
  local typeValue = SafeCopy(restrictionType, { maxDepth = 1, maxEntries = 1, maxNodes = 2, maxStringBytes = 64 })
  local stateValue = SafeCopy(state, { maxDepth = 1, maxEntries = 1, maxNodes = 2, maxStringBytes = 64 })
  local typeName = RestrictionTypeName(typeValue)
  local stateName = RestrictionStateName(stateValue)
  local message = safeEvent .. ": type=" .. typeName .. " state=" .. stateName

  local entry, status = BuildAndStore("TAINT_STATE", message, "BlizzardRestrictedActions", {
    event = safeEvent,
    restrictionType = typeValue,
    restrictionTypeName = typeName,
    state = stateValue,
    stateName = stateName,
    stackProvenance = "event-observer",
    severity = "INFO",
    observation = "restriction-transition-not-a-failure",
    restriction = RestrictionSnapshot(),
  })
  if entry and (status == "stored" or status == "queued") and type(RDL.Log) == "function" then
    pcall(RDL.Log, RDL, "INFO", "TAINT", "Restriction state changed", {
      type = typeName,
      state = stateName,
    })
  end
  return entry, status
end
