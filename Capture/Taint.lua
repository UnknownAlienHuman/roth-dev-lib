-- !RothDevLib/Capture/Taint.lua
-- Restricted-action capture with an explicit ordinary-value boundary.

local RDL = _G.RothDevLib
local Capture = RDL and RDL.Capture
if not Capture then return end

local function U()
  return RDL.Util
end

local function SafeCopy(value, opts)
  local util = U()
  if util and util.CopyDiagnosticValue then
    local ok, copy = pcall(util.CopyDiagnosticValue, util, value, opts or {
      maxDepth = 3,
      maxEntries = 40,
      maxStringBytes = 2048,
    })
    if ok then return copy end
  end
  return nil
end

local function SafeText(value, fallback, maxBytes)
  local util = U()
  local ordinary = value
  if util and util.Scrub then
    local ok, scrubbed = pcall(util.Scrub, util, value)
    if ok then ordinary = scrubbed else ordinary = "<unavailable>" end
  end

  local text = fallback or "<?>"
  if ordinary ~= nil and util and util.SafeToString then
    local ok, rendered = pcall(util.SafeToString, util, ordinary)
    if ok then text = rendered end
  elseif ordinary ~= nil and type(ordinary) == "string" then
    text = ordinary
  end

  if util and util.FilterSecretEscapes then
    local ok, filtered = pcall(util.FilterSecretEscapes, util, text)
    if ok then text = filtered end
  end
  if type(text) ~= "string" then text = fallback or "<?>" end

  maxBytes = tonumber(maxBytes) or 2048
  if #text > maxBytes then text = text:sub(1, maxBytes) .. "<truncated>" end
  return text
end

local function SafeCall(fn, ...)
  local guard = RDL.SecretGuard
  if guard and guard.CanAccess and not guard:CanAccess(fn) then return nil end
  if type(fn) ~= "function" then return nil end

  local ok, value = pcall(fn, ...)
  if not ok then return nil end
  return SafeCopy(value, { maxDepth = 1, maxEntries = 1, maxStringBytes = 256 })
end

local function SafeStack(level, top, bottom)
  if type(_G.debugstack) ~= "function" then return "" end
  local ok, stack = pcall(_G.debugstack, level, top, bottom)
  if not ok then return "" end
  return SafeText(stack, "", 64 * 1024)
end

local function MapRestrictionTypeName(value)
  local ordinary = SafeCopy(value, { maxDepth = 1, maxEntries = 1, maxStringBytes = 64 })
  local enum = _G.Enum and _G.Enum.AddOnRestrictionType
  if type(enum) ~= "table" then return SafeText(ordinary, "unknown", 64) end
  if ordinary == enum.Combat then return "Combat" end
  if ordinary == enum.Encounter then return "Encounter" end
  if ordinary == enum.ChallengeMode then return "ChallengeMode" end
  if ordinary == enum.PvPMatch then return "PvPMatch" end
  if ordinary == enum.Map then return "Map" end
  return SafeText(ordinary, "unknown", 64)
end

local function MapRestrictionStateName(value)
  local ordinary = SafeCopy(value, { maxDepth = 1, maxEntries = 1, maxStringBytes = 64 })
  local enum = _G.Enum and _G.Enum.AddOnRestrictionState
  if type(enum) ~= "table" then return SafeText(ordinary, "unknown", 64) end
  if ordinary == enum.Inactive then return "Inactive" end
  if ordinary == enum.Activating then return "Activating" end
  if ordinary == enum.Active then return "Active" end
  return SafeText(ordinary, "unknown", 64)
end

local function GetRestrictionSnapshot()
  local snapshot = { inCombat = SafeCall(_G.InCombatLockdown) }

  local restricted = _G.C_RestrictedActions
  local enumType = _G.Enum and _G.Enum.AddOnRestrictionType
  if type(restricted) ~= "table" or type(enumType) ~= "table" then
    return snapshot
  end

  local getState = restricted.GetAddOnRestrictionState
  local isActive = restricted.IsAddOnRestrictionActive
  if type(getState) ~= "function" and type(isActive) ~= "function" then
    return snapshot
  end

  snapshot.restrictions = {}
  local order = {
    { key = "Combat", value = enumType.Combat },
    { key = "Encounter", value = enumType.Encounter },
    { key = "ChallengeMode", value = enumType.ChallengeMode },
    { key = "PvPMatch", value = enumType.PvPMatch },
    { key = "Map", value = enumType.Map },
  }

  for index = 1, #order do
    local item = order[index]
    local record = {}
    if type(getState) == "function" then
      local state = SafeCall(getState, item.value)
      if state ~= nil then
        record.state = state
        record.stateName = MapRestrictionStateName(state)
      end
    end
    if type(isActive) == "function" then
      local active = SafeCall(isActive, item.value)
      if active ~= nil then record.active = active end
    end
    snapshot.restrictions[item.key] = record
  end

  return snapshot
end

local function BuildAndStore(kind, message, stack, addon, extra)
  if type(Capture.BuildEntry) ~= "function" or type(Capture.StoreEntry) ~= "function" then
    return nil
  end

  local okBuild, entry = pcall(Capture.BuildEntry, kind, message, stack, nil, addon, nil, extra)
  if not okBuild or type(entry) ~= "table" then
    if RDL.Log then
      RDL:Log("ERROR", "TAINT", "BuildEntry failed", {
        error = SafeText(entry, "<error>", 2048),
      })
    end
    return nil
  end

  local okStore, result = pcall(Capture.StoreEntry, entry)
  if not okStore then
    if RDL.Log then
      RDL:Log("ERROR", "TAINT", "StoreEntry failed", {
        error = SafeText(result, "<error>", 2048),
      })
    end
    return nil
  end
  return entry
end

function Capture:OnTaintEvent(event, addonName, blockedText)
  if self._disabled then return end

  local eventName = SafeText(event, "UNKNOWN_RESTRICTED_ACTION", 64)
  local source = "addon"
  local addon = SafeText(addonName, "<?>", 128)
  local blocked = SafeText(blockedText, "<?>", 2048)

  if eventName == "MACRO_ACTION_BLOCKED" or eventName == "MACRO_ACTION_FORBIDDEN" then
    source = "macro"
    blocked = SafeText(addonName, "<?>", 2048)
    addon = "BlizzardMacro"
  end

  local isBlocked = eventName == "ADDON_ACTION_BLOCKED" or eventName == "MACRO_ACTION_BLOCKED"
  local kind = isBlocked and "TAINT_BLOCKED" or "TAINT_FORBIDDEN"
  local message = kind .. ": source=" .. source .. " addon=" .. addon .. " func=" .. blocked
  local stack = SafeStack(2, 50, 50)
  local entry = BuildAndStore(kind, message, stack, addon, {
    event = eventName,
    source = source,
    blocked = blocked,
    restriction = GetRestrictionSnapshot(),
  })
  if not entry then return nil end

  if RDL.Log then
    RDL:Log("WARN", "TAINT", "Restricted action event captured", {
      event = eventName,
      source = source,
      addon = addon,
    })
  end
  return entry
end

function Capture:OnRestrictionStateChanged(event, restrictionType, state)
  if self._disabled then return end

  local eventName = SafeText(event, "ADDON_RESTRICTION_STATE_CHANGED", 64)
  local safeType = SafeCopy(restrictionType, { maxDepth = 1, maxEntries = 1, maxStringBytes = 64 })
  local safeState = SafeCopy(state, { maxDepth = 1, maxEntries = 1, maxStringBytes = 64 })
  local typeName = MapRestrictionTypeName(safeType)
  local stateName = MapRestrictionStateName(safeState)
  local message = eventName .. ": type=" .. typeName .. " state=" .. stateName
  local stack = SafeStack(2, 30, 30)

  local entry = BuildAndStore("TAINT_STATE", message, stack, "BlizzardRestrictedActions", {
    event = eventName,
    restrictionType = safeType,
    restrictionTypeName = typeName,
    state = safeState,
    stateName = stateName,
    restriction = GetRestrictionSnapshot(),
  })
  if not entry then return nil end

  if RDL.Log then
    RDL:Log("WARN", "TAINT", "Restriction state changed", {
      type = typeName,
      state = stateName,
    })
  end
  return entry
end
