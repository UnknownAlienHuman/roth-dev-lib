-- !RothDevLib/Export/Packer.lua
-- LLM-oriented compact packing with a strict final byte contract. The packer
-- degrades deterministically until JSON encoding succeeds inside maxBytes; it
-- never returns an encoder error object as if it were a valid report.

local RDL = _G.RothDevLib
local Export = RDL.Export
if not Export then return end

local Packer = {}
Export.Packer = Packer

local MAX_PACK_BYTES = 1024 * 1024
local MAX_GROUPS = 500
local MAX_TIMELINE = 100
local MAX_DEGRADATION_RECORDS = 12
local MAX_ATTEMPTS = 128

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
  if value == nil then return fallback end

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

  maximum = ClampInteger(maximum, 4096, 0, 1024 * 1024)
  if maximum <= 0 then return nil end
  if #text > maximum then return text:sub(1, maximum) .. "…" end
  return text
end

local function RawField(value, key)
  if not CanAccessTable(value) then return nil end
  local ok, field = pcall(rawget, value, key)
  if not ok or not CanAccess(field) then return nil end
  return field
end

local function KindWeight(kind)
  if kind == "LUA_ERROR" then return 100 end
  if kind == "TAINT_FORBIDDEN" then return 85 end
  if kind == "TAINT_STATE" then return 80 end
  if kind == "TAINT_BLOCKED" then return 75 end
  if kind == "ALERT" then return 60 end
  if kind == "ASSERT" then return 55 end
  if kind == "LUA_WARNING" then return 40 end
  if kind == "SUPPRESSED" then return 30 end
  return 10
end

local function ScoreGroup(group)
  local weight = KindWeight(SafeText(RawField(group, "kind"), "", 64))
  local count = RawField(group, "count")
  count = FiniteNumber(count) and math.max(0, count) or 1
  local recent = RawField(group, "lastSeen")
  recent = FiniteNumber(recent) and recent or 0
  return recent * 0.001 + weight + math.log(count + 1) * 3
end

local function SafeSerialize(value)
  local util = RDL.Util
  if CanAccessTable(value) and util and type(util.SafeSerializeTable) == "function" then
    local ok, rendered = pcall(util.SafeSerializeTable, util, value)
    if ok and type(rendered) == "string" then return rendered end
  end
  return SafeText(value, "<unavailable>", 8192)
end

local function CompactStack(value, maximumLines)
  local stack = SafeText(value, "", 128 * 1024)
  if not stack or stack == "" then return nil end
  maximumLines = ClampInteger(maximumLines, 18, 0, 200)
  if maximumLines <= 0 then return nil end

  stack = stack:gsub("\r", ""):gsub("\n+$", "")
  local lines = {}
  for line in stack:gmatch("[^\n]+") do
    lines[#lines + 1] = line
    if #lines >= maximumLines then break end
  end
  return #lines > 0 and table.concat(lines, "\n") or nil
end

local function CompactOrigin(value)
  if not CanAccessTable(value) then return nil end
  local addon = SafeText(RawField(value, "addon"), nil, 128)
  local file = SafeText(RawField(value, "file"), nil, 1024)
  local line = RawField(value, "line")
  line = FiniteNumber(line) and math.floor(line) or nil
  if addon == nil and file == nil and line == nil then return nil end
  return { addon = addon, file = file, line = line }
end

local function CompactMetrics(metrics, maximumEntries, maximumValueBytes)
  if not CanAccessTable(metrics) or maximumEntries <= 0 or maximumValueBytes <= 0 then return nil end

  local records, rawKey, scanned = {}, nil, 0
  while #records < maximumEntries and scanned < 500 do
    local ok, nextKey, nextValue = pcall(next, metrics, rawKey)
    if not ok or nextKey == nil then break end
    rawKey = nextKey
    scanned = scanned + 1
    records[#records + 1] = {
      k = SafeText(nextKey, "?", 256),
      v = SafeText(SafeSerialize(nextValue), "<unavailable>", maximumValueBytes),
    }
  end
  table.sort(records, function(a, b) return a.k < b.k end)
  return #records > 0 and records or nil
end

local function CompactDoctor(context, maximumBytes)
  if not CanAccessTable(context) or maximumBytes <= 0 then return nil end
  local doctor = {}
  local top = RawField(context, "top")
  local chain = RawField(context, "chain")
  local extra = RawField(context, "extra")
  if top ~= nil then doctor.top = SafeText(SafeSerialize(top), "", maximumBytes) end
  if chain ~= nil then doctor.chain = SafeText(SafeSerialize(chain), "", maximumBytes) end
  if extra ~= nil then doctor.extra = SafeText(SafeSerialize(extra), "", maximumBytes) end
  return next(doctor) and doctor or nil
end

local function IsIgnored(signature, group)
  local db = RDL.DB
  if not (db and type(db.IsIgnored) == "function") then return false end
  local ok, ignored = pcall(db.IsIgnored, db, signature,
    RawField(group, "addon"), RawField(group, "message"))
  return ok and ignored == true
end

local function CollectGroupsAll()
  local groups = {}
  local db = RDL.DB
  if not (db and type(db.IsReady) == "function" and type(db.IterGroups) == "function") then
    return groups
  end
  local okReady, ready = pcall(db.IsReady, db)
  if not okReady or ready ~= true then return groups end

  local okIterator, iterator, state, control = pcall(db.IterGroups, db)
  if not okIterator or type(iterator) ~= "function" then return groups end

  local scanned = 0
  while scanned < 5000 do
    local okNext, signature, group = pcall(iterator, state, control)
    if not okNext or signature == nil then break end
    control = signature
    scanned = scanned + 1
    if type(signature) == "string" and CanAccessTable(group) and not IsIgnored(signature, group) then
      groups[#groups + 1] = group
    end
  end

  table.sort(groups, function(a, b)
    local aScore, bScore = ScoreGroup(a), ScoreGroup(b)
    if aScore == bScore then
      return SafeText(RawField(a, "sig"), "", 4096)
        < SafeText(RawField(b, "sig"), "", 4096)
    end
    return aScore > bScore
  end)
  return groups
end

local function BuildAddonStats(groups)
  local output = {}
  for index = 1, #groups do
    local group = groups[index]
    local addon = SafeText(RawField(group, "addon"), "<?>" , 128)
    local kind = SafeText(RawField(group, "kind"), "<?>" , 64)
    local count = RawField(group, "count")
    count = FiniteNumber(count) and math.max(0, math.floor(count)) or 1
    local record = output[addon]
    if not record then
      record = { total = 0, byKind = {} }
      output[addon] = record
    end
    record.total = record.total + count
    record.byKind[kind] = (record.byKind[kind] or 0) + count
  end
  return output
end

local function EntryOrder(a, b)
  local aTime = RawField(a, "ts")
  local bTime = RawField(b, "ts")
  aTime = FiniteNumber(aTime) and aTime or 0
  bTime = FiniteNumber(bTime) and bTime or 0
  if aTime ~= bTime then return aTime > bTime end

  local fields = { "kind", "addon", "sig", "message" }
  for index = 1, #fields do
    local field = fields[index]
    local aText = SafeText(RawField(a, field), "", 4096)
    local bText = SafeText(RawField(b, field), "", 4096)
    if aText ~= bText then return aText < bText end
  end
  return false
end

local function InsertRecent(best, entry, maximum)
  local position = #best + 1
  for index = 1, #best do
    if EntryOrder(entry, best[index]) then
      position = index
      break
    end
  end
  table.insert(best, position, entry)
  if #best > maximum then best[#best] = nil end
end

local function FlattenRecentEntries(groups, maximumEntries, maximumMessageBytes)
  if maximumEntries <= 0 then return {} end
  local best = {}

  for groupIndex = 1, #groups do
    local occurrences = RawField(groups[groupIndex], "occurrences")
    if CanAccessTable(occurrences) then
      for occurrenceIndex = 1, 4 do
        local entry = RawField(occurrences, occurrenceIndex)
        if not CanAccessTable(entry) then break end
        InsertRecent(best, entry, maximumEntries)
      end
    end
  end

  local output = {}
  for index = 1, #best do
    local entry = best[index]
    local stack = SafeText(RawField(entry, "stack"), nil, 16 * 1024)
    output[index] = {
      ts = RawField(entry, "ts"),
      kind = SafeText(RawField(entry, "kind"), nil, 64),
      addon = SafeText(RawField(entry, "addon"), nil, 128),
      func = SafeText(RawField(entry, "func"), nil, 512),
      sig = SafeText(RawField(entry, "sig"), nil, 4096),
      msg = SafeText(RawField(entry, "message"), "", maximumMessageBytes),
      origin = CompactOrigin(RawField(entry, "origin")),
      stackTop = stack and stack:match("([^\n]*)") or nil,
    }
  end
  return output
end

local function BuildPolicyDoc()
  return {
    order = {
      "maxStackLines", "maxLocalsBytes", "maxMsgBytes", "maxDoctorBytes",
      "maxBreadcrumbs", "maxBreadcrumbMsgBytes", "maxMetricEntries",
      "maxMetricValueBytes", "timelineMax", "timelineMsgBytes",
      "maxOccurrences", "maxGroups", "includeLog",
    },
    note = "One bounded field shrinks at a time until the strict output budget is met.",
  }
end

local function DegradationTail(records)
  local output = {}
  local first = math.max(1, #records - MAX_DEGRADATION_RECORDS + 1)
  for index = first, #records do output[#output + 1] = records[index] end
  return output
end

local function SerializeGroup(group, limits)
  local object = {
    sig = SafeText(RawField(group, "sig"), nil, 4096),
    kind = SafeText(RawField(group, "kind"), nil, 64),
    count = RawField(group, "count"),
    lastSeen = RawField(group, "lastSeen"),
    addon = SafeText(RawField(group, "addon"), "<?>" , 128),
    func = SafeText(RawField(group, "func"), "<?>" , 512),
    message = SafeText(RawField(group, "message"), "", limits.maxMsgBytes),
    origin = CompactOrigin(RawField(group, "origin")),
    stack = CompactStack(RawField(group, "stack"), limits.maxStackLines),
  }

  if limits.maxLocalsBytes > 0 then
    object.locals = SafeText(RawField(group, "locals"), nil, limits.maxLocalsBytes)
  end
  object.doctor = CompactDoctor(RawField(group, "ctx"), limits.maxDoctorBytes)

  local bus = RawField(group, "bus")
  if CanAccessTable(bus) then
    local breadcrumbs = RawField(bus, "breadcrumbs")
    if CanAccessTable(breadcrumbs) and limits.maxBreadcrumbs > 0 then
      local output = {}
      for index = 1, limits.maxBreadcrumbs do
        local breadcrumb = RawField(breadcrumbs, index)
        if not CanAccessTable(breadcrumb) then break end
        output[#output + 1] = {
          t = RawField(breadcrumb, "ts"),
          c = SafeText(RawField(breadcrumb, "cat"), nil, 24),
          m = SafeText(RawField(breadcrumb, "msg"), nil, limits.maxBreadcrumbMsgBytes),
          d = SafeText(RawField(breadcrumb, "data"), nil, limits.maxBreadcrumbMsgBytes),
        }
      end
      if #output > 0 then object.breadcrumbs = output end
    end
    object.metrics = CompactMetrics(RawField(bus, "metrics"),
      limits.maxMetricEntries, limits.maxMetricValueBytes)
  end

  local occurrences = RawField(group, "occurrences")
  if CanAccessTable(occurrences) and limits.maxOccurrences > 0 then
    local output = {}
    for index = 1, limits.maxOccurrences do
      local entry = RawField(occurrences, index)
      if not CanAccessTable(entry) then break end
      local stack = SafeText(RawField(entry, "stack"), nil, 16 * 1024)
      output[#output + 1] = {
        ts = RawField(entry, "ts"),
        kind = SafeText(RawField(entry, "kind"), nil, 64),
        func = SafeText(RawField(entry, "func"), nil, 512),
        msg = SafeText(RawField(entry, "message"), "", limits.maxMsgBytes),
        stackTop = stack and stack:match("([^\n]*)") or nil,
      }
    end
    if #output > 0 then object.occ = output end
  end
  return object
end

local function TryPackWithLimits(limits, meta)
  local base = Export:BuildFullObject({
    exportKind = "packed",
    maxGroups = 0,
    includeOccurrences = false,
    includeLog = limits.includeLog,
    maxLogBytes = limits.maxLogBytes,
  })

  local allGroups = CollectGroupsAll()
  local chosen = {}
  for index = 1, math.min(#allGroups, limits.maxGroups) do chosen[index] = allGroups[index] end

  local serialized = {}
  for index = 1, #chosen do serialized[index] = SerializeGroup(chosen[index], limits) end
  base.groups = serialized
  base.addonStats = BuildAddonStats(chosen)
  base.timeline = FlattenRecentEntries(allGroups, limits.timelineMax, limits.timelineMsgBytes)
  base.packing = {
    limits = {
      maxGroups = limits.maxGroups,
      maxOccurrences = limits.maxOccurrences,
      maxStackLines = limits.maxStackLines,
      maxLocalsBytes = limits.maxLocalsBytes,
      maxMsgBytes = limits.maxMsgBytes,
      maxDoctorBytes = limits.maxDoctorBytes,
      maxBreadcrumbs = limits.maxBreadcrumbs,
      maxBreadcrumbMsgBytes = limits.maxBreadcrumbMsgBytes,
      maxMetricEntries = limits.maxMetricEntries,
      maxMetricValueBytes = limits.maxMetricValueBytes,
      timelineMax = limits.timelineMax,
      timelineMsgBytes = limits.timelineMsgBytes,
      includeLog = limits.includeLog == true,
      maxLogBytes = limits.maxLogBytes,
    },
    byteBudget = {
      target = meta.maxBytes,
      attempt = meta.attempt,
      degradationCount = #meta.degradation,
    },
    byteBudgetPolicy = BuildPolicyDoc(),
    degradation = DegradationTail(meta.degradation),
    limitations = {
      "Packed export is size-constrained and fields are truncated deterministically.",
      "WoW sandbox output is copy-only; no external attachment is created.",
    },
  }

  local json = Export:ToJSON(base, {
    pretty = true,
    maxDepth = 7,
    maxTableEntries = 600,
    maxArrayLen = 600,
    maxScanEntries = 5000,
    maxNodes = 20000,
    maxStringBytes = math.min(64 * 1024, meta.maxBytes),
    maxKeyBytes = 1024,
    maxOutputBytes = meta.maxBytes,
  })
  if json == '{"error":"json_output_limit"}' or json == '{"error":"json_encode_failed"}' then
    return nil
  end
  if #json > meta.maxBytes then return nil end
  return json
end

local function ShrinkMultiply(limits, key, minimum, multiplier)
  local old = tonumber(limits[key]) or 0
  if old <= minimum then return nil end
  local newValue = math.max(minimum, math.floor(old * multiplier))
  if newValue == old then newValue = old - 1 end
  if newValue < minimum then newValue = minimum end
  if newValue == old then return nil end
  limits[key] = newValue
  return key, old, newValue
end

local function ShrinkStep(limits, key, minimum, step)
  local old = tonumber(limits[key]) or 0
  if old <= minimum then return nil end
  local newValue = math.max(minimum, old - step)
  if newValue == old then return nil end
  limits[key] = newValue
  return key, old, newValue
end

local function ApplyNextDegradation(limits)
  return ShrinkMultiply(limits, "maxStackLines", 1, 0.70)
      or ShrinkMultiply(limits, "maxLocalsBytes", 0, 0.65)
      or ShrinkMultiply(limits, "maxMsgBytes", 64, 0.75)
      or ShrinkMultiply(limits, "maxDoctorBytes", 0, 0.65)
      or ShrinkStep(limits, "maxBreadcrumbs", 0, 1)
      or ShrinkMultiply(limits, "maxBreadcrumbMsgBytes", 32, 0.75)
      or ShrinkStep(limits, "maxMetricEntries", 0, 1)
      or ShrinkMultiply(limits, "maxMetricValueBytes", 32, 0.75)
      or ShrinkStep(limits, "timelineMax", 0, 4)
      or ShrinkMultiply(limits, "timelineMsgBytes", 32, 0.75)
      or ShrinkStep(limits, "maxOccurrences", 0, 1)
      or ShrinkStep(limits, "maxGroups", 0, 1)
      or (limits.includeLog and (function()
            limits.includeLog = false
            limits.maxLogBytes = 0
            return "includeLog", true, false
          end)() or nil)
end

local function NormalizeOptions(options)
  return {
    maxBytes = ClampInteger(RawOption(options, "maxBytes"), 32000, 4096, MAX_PACK_BYTES),
    maxGroups = ClampInteger(RawOption(options, "maxGroups"), 8, 0, MAX_GROUPS),
    maxOccurrences = ClampInteger(RawOption(options, "maxOccurrences"), 2, 0, 20),
    maxStackLines = ClampInteger(RawOption(options, "maxStackLines"), 18, 0, 200),
    maxBreadcrumbs = ClampInteger(RawOption(options, "maxBreadcrumbs"), 8, 0, 100),
    maxBreadcrumbMsgBytes = ClampInteger(RawOption(options, "maxBreadcrumbMsgBytes"), 180, 32, 4096),
    maxMetricEntries = ClampInteger(RawOption(options, "maxMetricEntries"), 8, 0, 100),
    maxMetricValueBytes = ClampInteger(RawOption(options, "maxMetricValueBytes"), 140, 32, 4096),
    maxMsgBytes = ClampInteger(RawOption(options, "maxMsgBytes"), 1200, 64, 16 * 1024),
    maxLocalsBytes = ClampInteger(RawOption(options, "maxLocalsBytes"), 1600, 0, 64 * 1024),
    maxDoctorBytes = ClampInteger(RawOption(options, "maxDoctorBytes"), 640, 0, 16 * 1024),
    includeLog = RawOption(options, "includeLog") == true,
    maxLogBytes = ClampInteger(RawOption(options, "maxLogBytes"), 4000, 0, 64 * 1024),
    timelineMax = ClampInteger(RawOption(options, "timelineMax"), 24, 0, MAX_TIMELINE),
    timelineMsgBytes = ClampInteger(RawOption(options, "timelineMsgBytes"), 200, 32, 4096),
  }
end

local function FallbackJSON(maxBytes, attempts, degradationCount)
  local output = string.format(
    '{"type":"RothDevLibExport","schema":1,"error":"pack_budget_exhausted","maxBytes":%d,"attempts":%d,"degradationCount":%d}',
    maxBytes, attempts, degradationCount)
  if #output > maxBytes then return '{"error":"pack_budget_exhausted"}' end
  return output
end

function Packer:BuildPackedJSON(options)
  local limits = NormalizeOptions(options)
  local maxBytes = limits.maxBytes
  local attempts, degradation = 0, {}

  while attempts < MAX_ATTEMPTS do
    attempts = attempts + 1
    local json = TryPackWithLimits(limits, {
      maxBytes = maxBytes,
      attempt = attempts,
      degradation = degradation,
    })
    if json then return json end

    local key, from, to = ApplyNextDegradation(limits)
    if not key then break end
    degradation[#degradation + 1] = {
      step = key,
      from = from,
      to = to,
      attempt = attempts,
    }
  end

  return FallbackJSON(maxBytes, attempts, #degradation)
end
