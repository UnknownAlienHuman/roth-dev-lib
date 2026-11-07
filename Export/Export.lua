-- !RothDevLib/Export/Export.lua
-- Bounded JSON/share/GitHub export surfaces. Export callers receive detached
-- ordinary snapshots; ignored groups are evaluated through authoritative DB
-- policy instead of stale per-group flags.

local RDL = _G.RothDevLib
local Export = {}
RDL.Export = Export

local MAX_EXPORT_GROUPS = 500
local MAX_EXPORT_OCCURRENCES = 20
local MAX_STACK_LINES = 200
local MAX_MESSAGE_BYTES = 16 * 1024
local MAX_LOCALS_BYTES = 64 * 1024
local MAX_BREADCRUMBS = 100
local MAX_LOG_BYTES = 64 * 1024
local MAX_ISSUE_BYTES = 512 * 1024
local MAX_SHARE_INPUT_BYTES = 1024 * 1024

local function CanAccess(value)
  local guard = RDL.SecretGuard
  if guard and type(guard.CanAccess) == "function" then
    local ok, allowed = pcall(guard.CanAccess, guard, value)
    if not ok or allowed ~= true then return false end
  elseif type(_G.canaccessvalue) == "function" then
    local ok, allowed = pcall(_G.canaccessvalue, value)
    if not ok or allowed ~= true then return false end
  end

  if guard and type(guard.IsSecret) == "function" then
    local ok, secret = pcall(guard.IsSecret, guard, value)
    if not ok or secret == true then return false end
  elseif type(_G.issecretvalue) == "function" then
    local ok, secret = pcall(_G.issecretvalue, value)
    if not ok or secret == true then return false end
  end
  return true
end

local function CanAccessTable(value)
  if not CanAccess(value) or type(value) ~= "table" then return false end
  local guard = RDL.SecretGuard
  if guard and type(guard.CanAccessTable) == "function" then
    local ok, allowed = pcall(guard.CanAccessTable, guard, value)
    return ok and allowed == true
  end
  if type(_G.canaccesstable) == "function" then
    local ok, allowed = pcall(_G.canaccesstable, value)
    return ok and allowed == true
  end
  return true
end

local function RawOption(options, key)
  if not CanAccessTable(options) then return nil end
  local ok, value = pcall(rawget, options, key)
  if not ok or not CanAccess(value) then return nil end
  return value
end

local function FiniteNumber(value)
  return type(value) == "number" and value == value
    and value ~= math.huge and value ~= -math.huge
end

local function ClampInteger(value, fallback, minimum, maximum)
  if not CanAccess(value) or not FiniteNumber(value) then return fallback end
  value = math.floor(value)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function SafeText(value, fallback, maximum)
  if not CanAccess(value) then return "<inaccessible>" end
  if value == nil then return fallback or "" end

  local text = fallback or ""
  local util = RDL.Util
  if util and type(util.SafeToString) == "function" then
    local ok, rendered = pcall(util.SafeToString, util, value)
    if ok and type(rendered) == "string" then text = rendered end
  elseif type(value) == "string" then
    text = value
  elseif type(value) == "number" or type(value) == "boolean" then
    text = tostring(value)
  end

  if util and type(util.FilterSecretEscapes) == "function" then
    local ok, filtered = pcall(util.FilterSecretEscapes, util, text)
    if ok and type(filtered) == "string" then text = filtered end
  end
  if type(text) ~= "string" then text = fallback or "" end

  maximum = ClampInteger(maximum, 4096, 1, 1024 * 1024)
  if #text > maximum then
    return text:sub(1, maximum) .. "\n... (trimmed to " .. maximum .. " bytes)"
  end
  return text
end

local function OptionalText(value, maximum)
  if not CanAccess(value) then return "<inaccessible>" end
  if value == nil then return nil end
  return SafeText(value, "", maximum)
end

local function SafeCopy(value, options)
  if not CanAccess(value) then return "<inaccessible>" end
  if value == nil then return nil end
  local util = RDL.Util
  if util and type(util.CopyDiagnosticValue) == "function" then
    local ok, copy = pcall(util.CopyDiagnosticValue, util, value, options or {
      maxDepth = 4,
      maxEntries = 80,
      maxNodes = 500,
      maxStringBytes = 4096,
      maxTotalBytes = 128 * 1024,
    })
    if ok then return copy end
  end
  return SafeText(value, "<unavailable>", 4096)
end

local function RawField(value, key)
  if not CanAccessTable(value) then return nil end
  local ok, field = pcall(rawget, value, key)
  if not ok or not CanAccess(field) then return nil end
  return field
end

local function Now()
  if type(_G.time) ~= "function" then return 0 end
  local ok, value = pcall(_G.time)
  return ok and FiniteNumber(value) and value or 0
end

local function SafeDate(value)
  local timestamp = FiniteNumber(value) and value or Now()
  if type(_G.date) ~= "function" then return tostring(timestamp) end
  local ok, rendered = pcall(_G.date, "%Y-%m-%d %H:%M:%S", timestamp)
  return ok and type(rendered) == "string" and rendered or tostring(timestamp)
end

local function StackTopLines(stack, maximumLines)
  local text = OptionalText(stack, 128 * 1024)
  if type(text) ~= "string" then return nil end
  maximumLines = ClampInteger(maximumLines, 20, 1, MAX_STACK_LINES)

  local out = {}
  for line in text:gmatch("[^\n]+") do
    out[#out + 1] = line
    if #out >= maximumLines then break end
  end
  return table.concat(out, "\n")
end

local function EscapeFence(value)
  return SafeText(value, "", 128 * 1024):gsub("```", "``\\`")
end

local function OriginSnapshot(origin)
  if not CanAccessTable(origin) then return nil end
  local addon = OptionalText(RawField(origin, "addon"), 128)
  local file = OptionalText(RawField(origin, "file"), 1024)
  local line = RawField(origin, "line")
  line = FiniteNumber(line) and math.floor(line) or nil
  if addon == nil and file == nil and line == nil then return nil end
  return { addon = addon, file = file, line = line }
end

local function SerializeBreadcrumbs(source, maximum)
  if not CanAccessTable(source) then return nil end
  maximum = ClampInteger(maximum, 12, 0, MAX_BREADCRUMBS)
  local out = {}
  for index = 1, maximum do
    local breadcrumb = RawField(source, index)
    if not CanAccessTable(breadcrumb) then break end
    out[#out + 1] = {
      ts = FiniteNumber(RawField(breadcrumb, "ts")) and RawField(breadcrumb, "ts") or nil,
      cat = OptionalText(RawField(breadcrumb, "cat"), 128),
      msg = OptionalText(RawField(breadcrumb, "msg"), 4096),
      data = OptionalText(RawField(breadcrumb, "data"), 8192),
    }
  end
  return #out > 0 and out or nil
end

local function SerializeGroup(group, limits)
  if not CanAccessTable(group) then return nil end
  limits = limits or {}

  local count = RawField(group, "count")
  count = FiniteNumber(count) and math.max(0, math.floor(count)) or 0
  local firstSession = RawField(group, "firstSessionId")
  local lastSession = RawField(group, "lastSessionId")

  local object = {
    sig = OptionalText(RawField(group, "sig"), 4096),
    kind = OptionalText(RawField(group, "kind"), 64),
    count = count,
    firstSeen = FiniteNumber(RawField(group, "firstSeen")) and RawField(group, "firstSeen") or nil,
    lastSeen = FiniteNumber(RawField(group, "lastSeen")) and RawField(group, "lastSeen") or nil,
    firstSessionId = FiniteNumber(firstSession) and math.floor(firstSession) or nil,
    lastSessionId = FiniteNumber(lastSession) and math.floor(lastSession) or nil,
    addon = OptionalText(RawField(group, "addon"), 128),
    func = OptionalText(RawField(group, "func"), 512),
    message = OptionalText(RawField(group, "message"), limits.maxMessageBytes),
    origin = OriginSnapshot(RawField(group, "origin")),
    stack = StackTopLines(RawField(group, "stack"), limits.maxStackLines),
    locals = OptionalText(RawField(group, "locals"), limits.maxLocalsBytes),
  }

  object.sys = SafeCopy(RawField(group, "sys"), {
    maxDepth = 4, maxEntries = 80, maxNodes = 500,
    maxStringBytes = 4096, maxTotalBytes = 64 * 1024,
  })
  object.ctx = SafeCopy(RawField(group, "ctx"), {
    maxDepth = 5, maxEntries = 120, maxNodes = 800,
    maxStringBytes = 4096, maxTotalBytes = 96 * 1024,
  })

  local bus = RawField(group, "bus")
  if CanAccessTable(bus) then
    local breadcrumbs = SerializeBreadcrumbs(RawField(bus, "breadcrumbs"), limits.maxBreadcrumbs)
    local metrics = SafeCopy(RawField(bus, "metrics"), {
      maxDepth = 4, maxEntries = 80, maxNodes = 500,
      maxStringBytes = 4096, maxTotalBytes = 64 * 1024,
    })
    if breadcrumbs ~= nil or metrics ~= nil then
      object.bus = { breadcrumbs = breadcrumbs, metrics = metrics }
    end
  end

  if limits.includeOccurrences then
    local source = RawField(group, "occurrences")
    if CanAccessTable(source) then
      local occurrences = {}
      for index = 1, limits.maxOccurrences do
        local entry = RawField(source, index)
        if not CanAccessTable(entry) then break end
        occurrences[#occurrences + 1] = {
          ts = FiniteNumber(RawField(entry, "ts")) and RawField(entry, "ts") or nil,
          kind = OptionalText(RawField(entry, "kind"), 64),
          addon = OptionalText(RawField(entry, "addon"), 128),
          func = OptionalText(RawField(entry, "func"), 512),
          message = OptionalText(RawField(entry, "message"), 4096),
          origin = OriginSnapshot(RawField(entry, "origin")),
          stackTop = StackTopLines(RawField(entry, "stack"), 6),
        }
      end
      if #occurrences > 0 then object.occurrences = occurrences end
    end
  end
  return object
end

local function IsIgnored(signature, group)
  local db = RDL.DB
  if not (db and type(db.IsIgnored) == "function") then return false end
  local ok, ignored = pcall(db.IsIgnored, db, signature,
    RawField(group, "addon"), RawField(group, "message"))
  return ok and ignored == true
end

local function CollectGroups(signatureFilter, includeIgnored, maximum)
  local db = RDL.DB
  if not (db and type(db.IsReady) == "function" and type(db.IterGroups) == "function") then
    return {}, 0
  end
  local okReady, ready = pcall(db.IsReady, db)
  if not okReady or ready ~= true then return {}, 0 end

  local okIterator, iterator, state, control = pcall(db.IterGroups, db)
  if not okIterator or type(iterator) ~= "function" then return {}, 0 end

  local candidates, total, scanned = {}, 0, 0
  while scanned < 5000 do
    local okNext, signature, group = pcall(iterator, state, control)
    if not okNext or signature == nil then break end
    control = signature
    scanned = scanned + 1

    if type(signature) == "string" and (not signatureFilter or signature == signatureFilter)
        and CanAccessTable(group) and (includeIgnored or not IsIgnored(signature, group)) then
      total = total + 1
      if maximum > 0 then candidates[#candidates + 1] = group end
    end
  end

  if maximum > 0 then
    table.sort(candidates, function(a, b)
      local aLast = RawField(a, "lastSeen")
      local bLast = RawField(b, "lastSeen")
      aLast = FiniteNumber(aLast) and aLast or 0
      bLast = FiniteNumber(bLast) and bLast or 0
      if aLast == bLast then
        return SafeText(RawField(a, "sig"), "", 4096)
          < SafeText(RawField(b, "sig"), "", 4096)
      end
      return aLast > bLast
    end)
    while #candidates > maximum do candidates[#candidates] = nil end
  end
  return candidates, total
end

local function BuildBaseEnvelope(kind)
  local system
  local util = RDL.Util
  if util and type(util.SnapshotSys) == "function" then
    local ok, value = pcall(util.SnapshotSys, util)
    if ok then system = SafeCopy(value) end
  end

  local interfaceVersion
  if type(_G.GetBuildInfo) == "function" then
    local ok, _, _, _, toc = pcall(_G.GetBuildInfo)
    if ok and CanAccess(toc) then interfaceVersion = toc end
  end

  local locale
  if type(_G.GetLocale) == "function" then
    local ok, value = pcall(_G.GetLocale)
    if ok then locale = OptionalText(value, 32) end
  end

  return {
    type = "RothDevLibExport",
    schema = 1,
    exportKind = SafeText(kind, "full", 64),
    generatedAt = Now(),
    env = {
      build = RawField(system, "build"),
      locale = locale,
      client = { interface = interfaceVersion },
      player = SafeCopy(RawField(system, "player")),
      zone = CanAccessTable(system) and {
        zone = OptionalText(RawField(system, "zone"), 256),
        subzone = OptionalText(RawField(system, "subzone"), 256),
      } or nil,
    },
    addon = {
      name = "!RothDevLib",
      version = SafeText(RDL.version, "", 128),
    },
    session = RDL.DB and SafeCopy(RDL.DB.session, {
      maxDepth = 3, maxEntries = 40, maxNodes = 200,
      maxStringBytes = 1024, maxTotalBytes = 32 * 1024,
    }) or nil,
  }
end

local function NormalizeFullOptions(options)
  return {
    exportKind = SafeText(RawOption(options, "exportKind"), "full", 64),
    signature = OptionalText(RawOption(options, "sig"), 4096),
    includeIgnored = RawOption(options, "includeIgnored") == true,
    includeOccurrences = RawOption(options, "includeOccurrences") ~= false,
    includeLog = RawOption(options, "includeLog") == true,
    maxGroups = ClampInteger(RawOption(options, "maxGroups"), 200, 0, MAX_EXPORT_GROUPS),
    maxOccurrences = ClampInteger(RawOption(options, "maxOccurrences"), 3, 0, MAX_EXPORT_OCCURRENCES),
    maxStackLines = ClampInteger(RawOption(options, "maxStackLines"), 40, 1, MAX_STACK_LINES),
    maxLocalsBytes = ClampInteger(RawOption(options, "maxLocalsBytes"), 4096, 256, MAX_LOCALS_BYTES),
    maxMessageBytes = ClampInteger(RawOption(options, "maxMsgBytes"), 2048, 256, MAX_MESSAGE_BYTES),
    maxBreadcrumbs = ClampInteger(RawOption(options, "maxBreadcrumbs"), 12, 0, MAX_BREADCRUMBS),
    maxLogBytes = ClampInteger(RawOption(options, "maxLogBytes"), 12000, 0, MAX_LOG_BYTES),
  }
end

function Export:BuildFullObject(options)
  local limits = NormalizeFullOptions(options)
  local envelope = BuildBaseEnvelope(limits.exportKind)
  envelope.limits = {
    maxGroups = limits.maxGroups,
    maxOccurrences = limits.maxOccurrences,
    maxStackLines = limits.maxStackLines,
    maxLocalsBytes = limits.maxLocalsBytes,
    maxMessageBytes = limits.maxMessageBytes,
    maxBreadcrumbs = limits.maxBreadcrumbs,
  }

  local groups, total = CollectGroups(limits.signature, limits.includeIgnored, limits.maxGroups)
  local serialized = {}
  for index = 1, #groups do
    local object = SerializeGroup(groups[index], {
      includeOccurrences = limits.includeOccurrences,
      maxOccurrences = limits.maxOccurrences,
      maxStackLines = limits.maxStackLines,
      maxLocalsBytes = limits.maxLocalsBytes,
      maxMessageBytes = limits.maxMessageBytes,
      maxBreadcrumbs = limits.maxBreadcrumbs,
    })
    if object then serialized[#serialized + 1] = object end
  end
  envelope.groups = serialized

  local activeCount
  if RDL.DB and type(RDL.DB.GetActiveGroupCount) == "function" then
    local ok, value = pcall(RDL.DB.GetActiveGroupCount, RDL.DB)
    if ok and FiniteNumber(value) then activeCount = math.max(0, math.floor(value)) end
  end
  envelope.summary = {
    groupCount = total,
    exportedGroupCount = #serialized,
    activeGroupCount = activeCount,
  }

  if limits.includeLog and limits.maxLogBytes > 0
      and RDL.Logger and type(RDL.Logger.GetText) == "function" then
    local ok, text = pcall(RDL.Logger.GetText, RDL.Logger)
    if ok then envelope.log = OptionalText(text, limits.maxLogBytes) end
  end
  return envelope
end

local function BuildInfo()
  if type(_G.GetBuildInfo) ~= "function" then return nil, nil, nil, nil end
  local ok, version, number, buildDate, interfaceVersion = pcall(_G.GetBuildInfo)
  if not ok then return nil, nil, nil, nil end
  return version, number, buildDate, interfaceVersion
end

local function CallText(fn, fallback, maximum, ...)
  if type(fn) ~= "function" then return fallback end
  local ok, value = pcall(fn, ...)
  return ok and SafeText(value, fallback, maximum) or fallback
end

function Export:BuildGitHubIssueText(signature, options)
  signature = OptionalText(signature, 4096)
  if not signature or not RDL.DB or type(RDL.DB.IsReady) ~= "function"
      or type(RDL.DB.GetGroup) ~= "function" then
    return nil, "Select an error group first."
  end
  local okReady, ready = pcall(RDL.DB.IsReady, RDL.DB)
  if not okReady or ready ~= true then return nil, "Select an error group first." end

  local okGroup, group = pcall(RDL.DB.GetGroup, RDL.DB, signature)
  if not okGroup or not CanAccessTable(group) then
    return nil, "Selected signature not found."
  end

  local maxMessage = ClampInteger(RawOption(options, "maxMessageBytes"), 1200, 256, MAX_MESSAGE_BYTES)
  local maxStackLines = ClampInteger(RawOption(options, "maxStackLines"), 80, 1, MAX_STACK_LINES)
  local maxLocals = ClampInteger(RawOption(options, "maxLocalsBytes"), 2400, 256, MAX_LOCALS_BYTES)
  local maxBreadcrumbs = ClampInteger(RawOption(options, "maxBreadcrumbs"), 8, 0, MAX_BREADCRUMBS)
  local maxBreadcrumbData = ClampInteger(RawOption(options, "maxBreadcrumbDataBytes"), 220, 64, 4096)
  local maxDoctor = ClampInteger(RawOption(options, "maxDoctorBytes"), 1400, 128, 16 * 1024)
  local maxTotal = ClampInteger(RawOption(options, "maxTotalBytes"), 128 * 1024, 4096, MAX_ISSUE_BYTES)

  local buildVersion, buildNumber, buildDate, interfaceVersion = BuildInfo()
  local addonName = SafeText(RawField(group, "addon"), "<?>" , 128)
  local kind = SafeText(RawField(group, "kind"), "<?>" , 64)
  local oneLineMessage = SafeText(RawField(group, "message"), "", 120)
    :gsub("\r", " "):gsub("\n", " ")
  local issueTitle = SafeText("[" .. addonName .. "] " .. kind .. ": " .. oneLineMessage,
    "RothDevLib report", 240)

  local playerName = CallText(_G.UnitName, "?", 128, "player")
  local realmName = CallText(_G.GetRealmName, "?", 128)
  local zoneName = CallText(_G.GetRealZoneText, "?", 256)
  local subzoneName = CallText(_G.GetSubZoneText, "?", 256)
  local locale = CallText(_G.GetLocale, "?", 32)

  local lines = {
    "## Bug Report (auto-generated by RothDevLib)",
    "",
    "### Suggested Title",
    "`" .. EscapeFence(issueTitle) .. "`",
    "",
    "### Environment",
    "- Addon: `" .. EscapeFence(addonName) .. "`",
    "- Kind: `" .. EscapeFence(kind) .. "`",
    "- Count: `" .. SafeText(RawField(group, "count"), "0", 32) .. "`",
    "- Signature: `" .. EscapeFence(signature) .. "`",
    "- RothDevLib: `" .. EscapeFence(SafeText(RDL.version, "", 128)) .. "`",
    "- WoW Build: `" .. EscapeFence(SafeText(buildVersion, "?", 64)) .. " ("
      .. EscapeFence(SafeText(buildNumber, "?", 64)) .. ")`",
    "- Interface: `" .. EscapeFence(SafeText(interfaceVersion, "?", 32)) .. "`",
    "- Build Date: `" .. EscapeFence(SafeText(buildDate, "?", 64)) .. "`",
    "- Locale: `" .. EscapeFence(locale) .. "`",
    "- Player: `" .. EscapeFence(playerName) .. "-" .. EscapeFence(realmName) .. "`",
    "- Zone: `" .. EscapeFence(zoneName) .. " / " .. EscapeFence(subzoneName) .. "`",
    "- First Seen: `" .. EscapeFence(SafeDate(RawField(group, "firstSeen"))) .. "`",
    "- Last Seen: `" .. EscapeFence(SafeDate(RawField(group, "lastSeen"))) .. "`",
    "",
    "### Error Message",
    "```",
    EscapeFence(OptionalText(RawField(group, "message"), maxMessage) or ""),
    "```",
    "",
    "### Stack Trace",
    "```lua",
    EscapeFence(StackTopLines(RawField(group, "stack"), maxStackLines) or ""),
    "```",
  }

  local locals = OptionalText(RawField(group, "locals"), maxLocals)
  if type(locals) == "string" and locals ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "<details><summary>Locals</summary>"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "```"
    lines[#lines + 1] = EscapeFence(locals)
    lines[#lines + 1] = "```"
    lines[#lines + 1] = "</details>"
  end

  local bus = RawField(group, "bus")
  local breadcrumbs = CanAccessTable(bus) and SerializeBreadcrumbs(RawField(bus, "breadcrumbs"), maxBreadcrumbs) or nil
  if breadcrumbs then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "<details><summary>Bus Breadcrumbs</summary>"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "```"
    for index = 1, #breadcrumbs do
      local breadcrumb = breadcrumbs[index]
      lines[#lines + 1] = string.format("%d) %s [%s] %s", index,
        breadcrumb.ts and SafeDate(breadcrumb.ts) or "<?>",
        SafeText(breadcrumb.cat, "?", 128), SafeText(breadcrumb.msg, "", 4096))
      if breadcrumb.data and breadcrumb.data ~= "" then
        lines[#lines + 1] = "   data: " .. SafeText(breadcrumb.data, "", maxBreadcrumbData)
      end
    end
    lines[#lines + 1] = "```"
    lines[#lines + 1] = "</details>"
  end

  local context = RawField(group, "ctx")
  local extra = CanAccessTable(context) and RawField(context, "extra") or nil
  if extra ~= nil then
    local rendered = SafeText(extra, "<unavailable>", maxDoctor)
    if RDL.Util and type(RDL.Util.SafeSerializeTable) == "function" then
      local ok, value = pcall(RDL.Util.SafeSerializeTable, RDL.Util, extra)
      if ok then rendered = SafeText(value, "", maxDoctor) end
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "<details><summary>Doctor Extra</summary>"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "```"
    lines[#lines + 1] = EscapeFence(rendered)
    lines[#lines + 1] = "```"
    lines[#lines + 1] = "</details>"
  end

  local output = table.concat(lines, "\n")
  if #output > maxTotal then
    output = output:sub(1, maxTotal) .. "\n\n...[report truncated]"
  end
  return output, issueTitle
end

function Export:ToJSON(object, options)
  local json = RDL.JSON
  if not json or type(json.Encode) ~= "function" then return "{}" end
  local ok, output = pcall(json.Encode, json, object, options)
  return ok and type(output) == "string" and output or '{"error":"json_encode_failed"}'
end

-- Optional share string: use LibDeflate when the normal callable LibStub table
-- or a function facade is present. Input is bounded before compression.
function Export:ToShareString(value)
  local json = SafeText(value, "", MAX_SHARE_INPUT_BYTES)
  local prefix = "RDL1:"
  local LibStub = _G.LibStub
  local libStubType = type(LibStub)
  if libStubType ~= "table" and libStubType ~= "function" then return prefix .. json end

  local okLibrary, LibDeflate = pcall(function()
    return LibStub("LibDeflate", true)
  end)
  if not okLibrary or not LibDeflate
      or type(LibDeflate.CompressDeflate) ~= "function"
      or type(LibDeflate.EncodeForPrint) ~= "function" then
    return prefix .. json
  end

  local okCompress, compressed = pcall(LibDeflate.CompressDeflate, LibDeflate, json, { level = 7 })
  if not okCompress or type(compressed) ~= "string" then return prefix .. json end
  local okEncode, encoded = pcall(LibDeflate.EncodeForPrint, LibDeflate, compressed)
  if not okEncode or type(encoded) ~= "string" then return prefix .. json end
  return prefix .. encoded
end
