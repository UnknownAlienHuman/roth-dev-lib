-- !RothDevLib/Capture/Taint.lua
-- Taint/restricted-action handlers.
-- Covers BugGrabber parity events:
--   * ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN
-- Plus additional restricted-action signals:
--   * MACRO_ACTION_BLOCKED / MACRO_ACTION_FORBIDDEN
--   * ADDON_RESTRICTION_STATE_CHANGED

local RDL = _G.RothDevLib

local function SafeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, r1 = pcall(fn, ...)
  if ok then return r1 end
  return nil
end

local function MapRestrictionTypeName(v)
  local E = _G.Enum and _G.Enum.AddOnRestrictionType
  if type(E) ~= "table" then return tostring(v) end
  if v == E.Combat then return "Combat" end
  if v == E.Encounter then return "Encounter" end
  if v == E.ChallengeMode then return "ChallengeMode" end
  if v == E.PvPMatch then return "PvPMatch" end
  if v == E.Map then return "Map" end
  return tostring(v)
end

local function MapRestrictionStateName(v)
  local E = _G.Enum and _G.Enum.AddOnRestrictionState
  if type(E) ~= "table" then return tostring(v) end
  if v == E.Inactive then return "Inactive" end
  if v == E.Activating then return "Activating" end
  if v == E.Active then return "Active" end
  return tostring(v)
end

local function GetRestrictionSnapshot()
  local snap = {
    inCombat = SafeCall(_G.InCombatLockdown) and true or false,
  }

  local CRA = _G.C_RestrictedActions
  local EnumType = _G.Enum and _G.Enum.AddOnRestrictionType
  if type(CRA) ~= "table" or type(EnumType) ~= "table" then
    return snap
  end

  local getState = CRA.GetAddOnRestrictionState
  local isActive = CRA.IsAddOnRestrictionActive
  if type(getState) ~= "function" and type(isActive) ~= "function" then
    return snap
  end

  snap.restrictions = {}
  local order = {
    { key = "Combat", value = EnumType.Combat },
    { key = "Encounter", value = EnumType.Encounter },
    { key = "ChallengeMode", value = EnumType.ChallengeMode },
    { key = "PvPMatch", value = EnumType.PvPMatch },
    { key = "Map", value = EnumType.Map },
  }

  for i = 1, #order do
    local it = order[i]
    local rec = {}
    if type(getState) == "function" then
      local st = SafeCall(getState, it.value)
      if st ~= nil then
        rec.state = st
        rec.stateName = MapRestrictionStateName(st)
      end
    end
    if type(isActive) == "function" then
      local ac = SafeCall(isActive, it.value)
      if ac ~= nil then rec.active = ac and true or false end
    end
    snap.restrictions[it.key] = rec
  end

  return snap
end

-- Called from Core/Events.lua when restricted-action events fire.
-- Uses Capture.BuildEntry / Capture.StoreEntry from ErrorHandler.lua.
function RDL.Capture:OnTaintEvent(event, addonName, blockedText)
  if self._disabled then return end

  local BuildEntry = self.BuildEntry
  local StoreEntry = self.StoreEntry
  if not BuildEntry or not StoreEntry then return end

  local source = "addon"
  local addon = addonName
  local blocked = blockedText
  if event == "MACRO_ACTION_BLOCKED" or event == "MACRO_ACTION_FORBIDDEN" then
    source = "macro"
    blocked = addonName
    addon = "BlizzardMacro"
  end

  local blockedKind = (event == "ADDON_ACTION_BLOCKED" or event == "MACRO_ACTION_BLOCKED")
  local kind = blockedKind and "TAINT_BLOCKED" or "TAINT_FORBIDDEN"
  local msg = kind .. ": source=" .. tostring(source) .. " addon=" .. tostring(addon) .. " func=" .. tostring(blocked)
  local stack = debugstack(2, 50, 50)

  local extra = {
    event = event,
    source = source,
    blocked = blocked,
    restriction = GetRestrictionSnapshot(),
  }
  local entry = BuildEntry(kind, msg, stack, nil, addon, nil, extra)
  StoreEntry(entry)

  RDL:Log("WARN", "TAINT", "Restricted action event captured", { event = event, source = source, addon = addon })
end

function RDL.Capture:OnRestrictionStateChanged(event, restrictionType, state)
  if self._disabled then return end

  local BuildEntry = self.BuildEntry
  local StoreEntry = self.StoreEntry
  if not BuildEntry or not StoreEntry then return end

  local typeName = MapRestrictionTypeName(restrictionType)
  local stateName = MapRestrictionStateName(state)
  local msg = "ADDON_RESTRICTION_STATE_CHANGED: type=" .. tostring(typeName) .. " state=" .. tostring(stateName)
  local stack = debugstack(2, 30, 30)

  local extra = {
    event = event,
    restrictionType = restrictionType,
    restrictionTypeName = typeName,
    state = state,
    stateName = stateName,
    restriction = GetRestrictionSnapshot(),
  }

  local entry = BuildEntry("TAINT_STATE", msg, stack, nil, "BlizzardRestrictedActions", nil, extra)
  StoreEntry(entry)

  RDL:Log("WARN", "TAINT", "Restriction state changed", { type = typeName, state = stateName })
end
