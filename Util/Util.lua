-- !RothDevLib/Util/Util.lua
-- Helpers: ordinary-value gating, safe stringify, signatures, origin parsing, |K filtering.

local RDL = _G.RothDevLib
local Util = {}
RDL.Util = Util

local function CallPredicate(fn, ...)
  local ok, result = pcall(fn, ...)
  if not ok then return nil end
  return result == true
end

local function CanAccessValue(value)
  local SG = RDL.SecretGuard
  if SG and type(SG.CanAccess) == "function" then
    return SG:CanAccess(value)
  end

  local fn = _G.canaccessvalue
  if type(fn) == "function" then
    return CallPredicate(fn, value) == true
  end

  local isSecret = _G.issecretvalue
  if type(isSecret) == "function" then
    return CallPredicate(isSecret, value) == false
  end

  return true
end

local function IsSecretValue(value)
  local SG = RDL.SecretGuard
  if SG and type(SG.IsSecret) == "function" then
    return SG:IsSecret(value)
  end

  local fn = _G.issecretvalue
  if type(fn) ~= "function" then return false end
  return CallPredicate(fn, value) == true
end

local function IsSecretTable(value)
  local fn = _G.issecrettable
  if type(fn) ~= "function" then return false end
  return CallPredicate(fn, value) == true
end

local function CanAccessTable(value)
  local SG = RDL.SecretGuard
  if SG and type(SG.CanAccessTable) == "function" then
    return SG:CanAccessTable(value)
  end

  if not CanAccessValue(value) then return false end
  if value == nil or type(value) ~= "table" then return false end

  local fn = _G.canaccesstable
  if type(fn) ~= "function" then return true end
  return CallPredicate(fn, value) == true
end

-- Convert inaccessible/secret values into ordinary diagnostic markers before
-- any comparison, formatting, table-key use, export or persistence.
function Util:Scrub(value)
  if not CanAccessValue(value) then return "<inaccessible>" end
  if IsSecretValue(value) then return "<secret>" end
  return value
end

function Util:SafeToString(value)
  local v = self:Scrub(value)
  if v == nil then return "nil" end

  local valueType = type(v)
  if valueType == "string" then return v end
  if valueType == "number" or valueType == "boolean" then return tostring(v) end
  if valueType == "table" then
    if IsSecretTable(v) or not CanAccessTable(v) then return "<inaccessible-table>" end
    return "<table>"
  end
  if valueType == "function" then return "<function>" end
  return "<" .. valueType .. ">"
end

-- UI-safe rendering: escape | for FontStrings.
function Util:EscapePipes(value)
  local ok, str = pcall(self.SafeToString, self, value)
  if not ok then return "<unavailable>" end
  return (str or ""):gsub("|", "||")
end

local function SerializeTable(self, value, depth, seen)
  local scrubbed = self:Scrub(value)
  if type(scrubbed) ~= "table" then
    return self:SafeToString(scrubbed)
  end
  if IsSecretTable(scrubbed) or not CanAccessTable(scrubbed) then
    return "<inaccessible-table>"
  end
  if depth > 2 then return "<depth>" end
  if seen[scrubbed] then return "<cycle>" end

  seen[scrubbed] = true
  local entries = {}
  local count = 0

  for key, item in pairs(scrubbed) do
    count = count + 1
    if count > 30 then
      entries[#entries + 1] = { key = "...", value = "..." }
      break
    end

    local keyText = self:SafeToString(key)
    local itemText
    local ordinaryItem = self:Scrub(item)
    if type(ordinaryItem) == "table" then
      itemText = SerializeTable(self, ordinaryItem, depth + 1, seen)
    else
      itemText = self:SafeToString(ordinaryItem)
    end
    entries[#entries + 1] = { key = keyText, value = itemText }
  end

  seen[scrubbed] = nil
  table.sort(entries, function(a, b)
    return a.key < b.key
  end)

  local parts = {}
  for i = 1, #entries do
    local entry = entries[i]
    parts[i] = entry.key .. "=" .. entry.value
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

function Util:SafeSerializeTable(value, depth)
  local ordinaryDepth = self:Scrub(depth)
  if type(ordinaryDepth) ~= "number" then ordinaryDepth = 0 end
  return SerializeTable(self, value, ordinaryDepth, {})
end

function Util:ScrubVarargs(...)
  if type(_G.scrubsecretvalues) == "function" then
    return _G.scrubsecretvalues(...)
  end

  -- Compatibility fallback for clients without scrubsecretvalues(). Keep the
  -- boundary explicit instead of leaking raw varargs back to callers.
  return self:Scrub(select(1, ...)),
    self:Scrub(select(2, ...)),
    self:Scrub(select(3, ...)),
    self:Scrub(select(4, ...)),
    self:Scrub(select(5, ...)),
    self:Scrub(select(6, ...)),
    self:Scrub(select(7, ...)),
    self:Scrub(select(8, ...))
end

local function ClampInteger(value, fallback, minimum, maximum)
  local ordinary = value
  if type(ordinary) ~= "number" then return fallback end
  ordinary = math.floor(ordinary)
  if ordinary < minimum then return minimum end
  if ordinary > maximum then return maximum end
  return ordinary
end

local function NormalizeCopyOptions(self, opts)
  local config = {
    maxDepth = 4,
    maxEntries = 80,
    maxStringBytes = 4096,
  }

  local ordinary = self:Scrub(opts)
  if type(ordinary) ~= "table" or IsSecretTable(ordinary) or not CanAccessTable(ordinary) then
    return config
  end

  config.maxDepth = ClampInteger(self:Scrub(ordinary.maxDepth), config.maxDepth, 1, 12)
  config.maxEntries = ClampInteger(self:Scrub(ordinary.maxEntries), config.maxEntries, 1, 2000)
  config.maxStringBytes = ClampInteger(self:Scrub(ordinary.maxStringBytes), config.maxStringBytes, 64, 1024 * 1024)
  return config
end

local function TruncateBytes(value, maximum)
  if #value <= maximum then return value end
  return value:sub(1, maximum) .. "<truncated>"
end

-- Deep-copy external diagnostic data into ordinary, bounded Lua values.
-- This is the persistence/callback boundary: no foreign table references or
-- secret-capable values survive beyond this function.
function Util:CopyDiagnosticValue(value, opts)
  local config = NormalizeCopyOptions(self, opts)
  local seen = {}

  local function Copy(current, depth)
    local ordinary = self:Scrub(current)
    if ordinary == nil then return nil end

    local valueType = type(ordinary)
    if valueType == "string" then
      local filtered = self:FilterSecretEscapes(ordinary)
      return TruncateBytes(filtered, config.maxStringBytes)
    end
    if valueType == "number" then
      if ordinary ~= ordinary then return "<nan>" end
      if ordinary == math.huge then return "<infinity>" end
      if ordinary == -math.huge then return "<-infinity>" end
      return ordinary
    end
    if valueType == "boolean" then return ordinary end
    if valueType ~= "table" then return self:SafeToString(ordinary) end

    if IsSecretTable(ordinary) or not CanAccessTable(ordinary) then
      return "<inaccessible-table>"
    end
    if depth >= config.maxDepth then return "<depth>" end
    if seen[ordinary] then return "<cycle>" end

    seen[ordinary] = true
    local out = {}
    local usedKeys = {}
    local count = 0
    local truncated = false

    for key, item in pairs(ordinary) do
      count = count + 1
      if count > config.maxEntries then
        truncated = true
        break
      end

      local safeKey = self:Scrub(key)
      local keyType = type(safeKey)
      if keyType == "string" then
        safeKey = TruncateBytes(self:FilterSecretEscapes(safeKey), 256)
      elseif keyType == "number" then
        if safeKey ~= safeKey or safeKey == math.huge or safeKey == -math.huge then
          safeKey = self:SafeToString(safeKey)
        end
      elseif keyType ~= "boolean" then
        safeKey = "[" .. keyType .. "]" .. self:SafeToString(safeKey)
      end

      local baseKey = safeKey
      local suffix = 2
      while usedKeys[safeKey] do
        safeKey = self:SafeToString(baseKey) .. "#" .. suffix
        suffix = suffix + 1
      end
      usedKeys[safeKey] = true
      out[safeKey] = Copy(item, depth + 1)
    end

    if truncated then
      local marker = "__rdl_truncated"
      local suffix = 2
      while usedKeys[marker] do
        marker = "__rdl_truncated_" .. suffix
        suffix = suffix + 1
      end
      out[marker] = true
    end

    seen[ordinary] = nil
    return out
  end

  return Copy(value, 0)
end

-- |K filtering for WoW 12.x secret-value escape sequences.
function Util:FilterSecretEscapes(value)
  local s = self:Scrub(value)
  if type(s) ~= "string" then return s end
  return s:gsub("|K[^|]*|k", "<filtered>")
end

-- Filter and trim an already-readable locals string.
function Util:FilterLocals(value, maxSize)
  local localsStr = self:FilterSecretEscapes(value)
  if type(localsStr) ~= "string" then return nil end

  maxSize = self:Scrub(maxSize)
  if type(maxSize) ~= "number" then maxSize = 8192 end
  if maxSize < 256 then maxSize = 256 end
  if maxSize > 1024 * 1024 then maxSize = 1024 * 1024 end

  if #localsStr > maxSize then
    localsStr = localsStr:sub(1, maxSize) .. "\n... (trimmed to " .. maxSize .. " bytes)"
  end
  return localsStr
end

local function Trunc(s, n)
  if not s then return s end
  if #s <= n then return s end
  return string.sub(s, 1, n) .. "…"
end

function Util:NormalizeStack(stack)
  local value = self:Scrub(stack)
  if value == nil then return "" end
  if type(value) ~= "string" then value = self:SafeToString(value) end

  value = value:gsub("\\", "/")
  value = value:gsub("Interface/AddOns/", "")
  value = value:gsub(":(%d+):", ":#:")
  value = value:gsub(":%d+%)", ":#)")
  value = value:gsub("([%w_%-]+/[%w_%-./]+):(%d+)", "%1:#")
  return value
end

-- Normalize line numbers in messages for stable signatures.
function Util:NormalizeMessage(message)
  local value = self:Scrub(message)
  if value == nil then return "" end
  if type(value) ~= "string" then value = self:SafeToString(value) end

  value = value:gsub("\\", "/")
  value = value:gsub("Interface/AddOns/", "")
  value = value:gsub("([%w_%-]+/[%w_%-./]+):(%d+)", "%1:#")
  value = value:gsub("table:%s*0x[%x]+", "table:<?>")
  return value
end

function Util:MakeSignature(kind, message, stack)
  local kindText = self:SafeToString(kind)
  local msg = Trunc(self:SafeToString(message), 260) or ""
  local normMsg = self:NormalizeMessage(msg)
  local st = self:NormalizeStack(stack)

  local top = st:match("([%w_%-]+)/")
    or normMsg:match("([%w_%-]+)/")
    or ""

  local line = st:match("([%w_%-]+/.-)\n")
    or normMsg:match("([%w_%-]+/[^\n|]+)")
    or ""
  line = Trunc(line, 200) or ""

  if kindText == "LUA_ERROR" or kindText == "LUA_WARNING" or kindText == "SUPPRESSED" then
    return kindText .. "|" .. normMsg
  end
  return kindText .. "|" .. top .. "|" .. normMsg .. "|" .. line
end

function Util:GuessAddonFromStack(stack)
  local s = self:NormalizeStack(stack)
  if s == "" then return nil end
  return s:match("([%w_%-]+)/")
end

-- Origin resolution: parse stack for first addon file reference.
function Util:ParseOrigin(stack, message)
  local function TryParse(value)
    local s = self:Scrub(value)
    if s == nil then return nil end
    if type(s) ~= "string" then s = self:SafeToString(s) end

    s = s:gsub("\\", "/")
    s = s:gsub("Interface/AddOns/", "")
    local file, line = s:match("([%w_%-]+/[^:]+):(%d+)")
    if not file then return nil end

    local addon = file:match("([^/]+)/")
    local relFile = file:match("[^/]+/(.*)")
    return {
      addon = addon,
      file = relFile or file,
      line = tonumber(line),
    }
  end

  return TryParse(stack) or TryParse(message)
end

local function ScrubSnapshot(self, value)
  return self:Scrub(value)
end

local function CallOptional(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if not ok then return nil end
  return value
end

-- System snapshot. All external values are normalized before storage/export.
function Util:SnapshotSys()
  local inInstance, instanceType = IsInInstance()
  local name, instanceType2, difficultyID, _difficultyName, _maxPlayers,
    _dynamicDifficulty, _isDynamic, instanceID = GetInstanceInfo()

  local inCombat = UnitAffectingCombat("player")
  local encounter = IsEncounterInProgress()

  local specName, specID = nil, nil
  local specIndex = GetSpecialization and GetSpecialization()
  if CanAccessValue(specIndex) and not IsSecretValue(specIndex)
     and type(specIndex) == "number" and GetSpecializationInfo then
    specID, specName = GetSpecializationInfo(specIndex)
  end

  local zone = GetRealZoneText()
  local subzone = GetSubZoneText()
  local version, build, dateStr, toc = GetBuildInfo()

  local function CVar(nameKey)
    if not GetCVar then return nil end
    local ok, value = pcall(GetCVar, nameKey)
    if not ok then return nil end
    return ScrubSnapshot(self, value)
  end

  local className, classFile, classID = UnitClass("player")

  local storedInstanceType = ScrubSnapshot(self, instanceType)
  if storedInstanceType == nil then
    storedInstanceType = ScrubSnapshot(self, instanceType2)
  end

  return {
    ts = time(),
    inCombat = ScrubSnapshot(self, inCombat),
    encounter = ScrubSnapshot(self, encounter),
    inInstance = ScrubSnapshot(self, inInstance),
    instanceType = storedInstanceType,
    instanceName = ScrubSnapshot(self, name),
    difficultyID = ScrubSnapshot(self, difficultyID),
    instanceID = ScrubSnapshot(self, instanceID),
    zone = ScrubSnapshot(self, zone),
    subzone = ScrubSnapshot(self, subzone),
    specID = ScrubSnapshot(self, specID),
    specName = ScrubSnapshot(self, specName),
    build = {
      version = ScrubSnapshot(self, version),
      build = ScrubSnapshot(self, build),
      date = ScrubSnapshot(self, dateStr),
      toc = ScrubSnapshot(self, toc),
    },
    cvars = {
      scriptErrors = CVar("scriptErrors"),
      scriptWarnings = CVar("scriptWarnings"),
      taintLog = CVar("taintLog"),
    },
    player = {
      name = ScrubSnapshot(self, CallOptional(UnitName, "player")),
      realm = ScrubSnapshot(self, CallOptional(GetRealmName)),
      class = ScrubSnapshot(self, className),
      classFile = ScrubSnapshot(self, classFile),
      classID = ScrubSnapshot(self, classID),
      level = ScrubSnapshot(self, CallOptional(UnitLevel, "player")),
      guid = ScrubSnapshot(self, CallOptional(UnitGUID, "player")),
    },
  }
end
