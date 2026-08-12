-- !RothDevLib/Util/Util.lua
-- Helpers: secret scrubbing, safe stringify, signatures, origin parsing, |K filtering.

local RDL = _G.RothDevLib
local Util = {}
RDL.Util = Util

-- UI-safe rendering: escape | for FontStrings
function Util:EscapePipes(s)
  if s == nil then return "" end
  local ok, str = pcall(function() return self:SafeToString(s) end)
  s = ok and str or tostring(s)
  return (s or ""):gsub("|", "||")
end

local function IsSecretAvailable()
  return type(_G.issecretvalue) == "function"
end

function Util:Scrub(value)
  if IsSecretAvailable() and type(_G.issecretvalue) == "function" then
    local ok, secret = pcall(_G.issecretvalue, value)
    if ok and secret then return "<secret>" end
  end
  return value
end

function Util:SafeToString(v)
  v = self:Scrub(v)
  if v == nil then return "nil" end
  local t = type(v)
  if t == "string" then return v end
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "table" then return "<table>" end
  if t == "function" then return "<function>" end
  return "<" .. t .. ">"
end

function Util:SafeSerializeTable(t, depth)
  depth = depth or 0
  if depth > 2 then return "<depth>" end
  if type(t) ~= "table" then return self:SafeToString(t) end
  local parts = {}
  local n = 0
  for k, v in pairs(t) do
    n = n + 1
    if n > 30 then table.insert(parts, "...=..."); break end
    local ks = self:SafeToString(k)
    local vs = type(v) == "table" and self:SafeSerializeTable(v, depth + 1) or self:SafeToString(v)
    table.insert(parts, ks .. "=" .. vs)
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

function Util:ScrubVarargs(...)
  if type(_G.scrubsecretvalues) == "function" then
    return _G.scrubsecretvalues(...)
  end
  return ...
end

-- |K filtering for WoW 12.x Midnight secret value escape sequences (gap #3)
function Util:FilterSecretEscapes(s)
  if type(s) ~= "string" then return s end
  return s:gsub("|K[^|]*|k", "<filtered>")
end

-- Filter and trim locals string
function Util:FilterLocals(localsStr, maxSize)
  if type(localsStr) ~= "string" then return nil end
  -- |K filtering
  localsStr = self:FilterSecretEscapes(localsStr)
  -- Trim to maxSize
  maxSize = maxSize or 8192
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
  if not stack then return "" end
  stack = tostring(stack):gsub("\\", "/")
  stack = stack:gsub("Interface/AddOns/", "")
  stack = stack:gsub(":(%d+):", ":#:")
  stack = stack:gsub(":%d+%)", ":#)")
  stack = stack:gsub("([%w_%-]+/[%w_%-./]+):(%d+)", "%1:#")
  return stack
end

-- Normalize line numbers in message too for stable signatures (gap #8)
function Util:NormalizeMessage(msg)
  if not msg then return "" end
  msg = tostring(msg):gsub("\\", "/")
  msg = msg:gsub("Interface/AddOns/", "")
  -- Remove line numbers from Interface/AddOns paths in message
  msg = msg:gsub("([%w_%-]+/[%w_%-./]+):(%d+)", "%1:#")
  -- Drop volatile table addresses to improve grouping stability.
  msg = msg:gsub("table:%s*0x[%x]+", "table:<?>")
  return msg
end

function Util:MakeSignature(kind, message, stack)
  local msg = Trunc(tostring(self:Scrub(message)), 260) or ""
  local normMsg = self:NormalizeMessage(msg)
  local st = self:NormalizeStack(stack or "")

  local top = st:match("([%w_%-]+)/")
    or normMsg:match("([%w_%-]+)/")
    or ""

  local line = st:match("([%w_%-]+/.-)\n")
    or normMsg:match("([%w_%-]+/[^\n|]+)")
    or ""
  line = Trunc(line, 200) or ""

  if kind == "LUA_ERROR" or kind == "LUA_WARNING" or kind == "SUPPRESSED" then
    -- BugGrabber groups by message text; keep Lua signatures message-centric for stable repeat counting.
    return kind .. "|" .. normMsg
  end
  return kind .. "|" .. top .. "|" .. normMsg .. "|" .. line
end

function Util:GuessAddonFromStack(stack)
  if not stack then return nil end
  local s = tostring(stack):gsub("\\", "/"):gsub("Interface/AddOns/", "")
  return s:match("([%w_%-]+)/")
end

-- Origin resolution: parse stack for first addon file reference (gap #10)
function Util:ParseOrigin(stack, message)
  if not stack and not message then return nil end

  local function tryParse(s)
    if not s then return nil end
    s = tostring(s):gsub("\\", "/")
    s = s:gsub("Interface/AddOns/", "")
    local file, line = s:match("([%w_%-]+/[^:]+):(%d+)")
    if file then
      local addon = file:match("([^/]+)/")
      local relFile = file:match("[^/]+/(.*)")
      return {
        addon = addon,
        file = relFile or file,
        line = tonumber(line),
      }
    end
    return nil
  end

  -- Try stack first (more reliable), then message
  return tryParse(stack) or tryParse(tostring(message))
end

-- System snapshot
function Util:SnapshotSys()
  local inInstance, instanceType = IsInInstance()
  local name, instanceType2, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceID = GetInstanceInfo()
  local inCombat = UnitAffectingCombat("player") and true or false
  local enc = IsEncounterInProgress() and true or false

  local specName, specID = nil, nil
  local specIndex = GetSpecialization and GetSpecialization()
  if specIndex and GetSpecializationInfo then
    specID, specName = GetSpecializationInfo(specIndex)
  end

  local zone = GetRealZoneText()
  local sub = GetSubZoneText()
  local v, build, dateStr, toc = GetBuildInfo()

  local function CVar(k)
    if not GetCVar then return nil end
    local ok, val = pcall(GetCVar, k)
    return ok and val or nil
  end

  local className, classFile, classID = UnitClass("player")

  return {
    ts = time(),
    inCombat = inCombat,
    encounter = enc,
    inInstance = inInstance,
    instanceType = instanceType or instanceType2,
    instanceName = name,
    difficultyID = difficultyID,
    instanceID = instanceID,
    zone = zone,
    subzone = sub,
    specID = specID,
    specName = specName,
    build = { version = v, build = build, date = dateStr, toc = toc },
    cvars = {
      scriptErrors = CVar("scriptErrors"),
      scriptWarnings = CVar("scriptWarnings"),
      taintLog = CVar("taintLog"),
    },
    player = {
      name = UnitName("player"),
      realm = GetRealmName and GetRealmName() or nil,
      class = className,
      classFile = classFile,
      classID = classID,
      level = UnitLevel and UnitLevel("player") or nil,
      guid = UnitGUID and UnitGUID("player") or nil,
    },
  }
end
