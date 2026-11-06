-- !RothDevLib/Util/JSON.lua
-- Deterministic diagnostic JSON encoder with raw bounded traversal.
-- Foreign __pairs/__index/__len metamethods are never invoked.

local RDL = _G.RothDevLib
if not RDL then return end

local JSON = {}
RDL.JSON = JSON

local OUTPUT_LIMIT = {}

local function Predicate(fn, ...)
  local ok, value = pcall(fn, ...)
  return ok and value == true
end

local function CanAccessValue(value)
  local guard = RDL.SecretGuard
  if guard and type(guard.CanAccess) == "function" then
    local ok, allowed = pcall(guard.CanAccess, guard, value)
    return ok and allowed == true
  end
  if type(_G.canaccessvalue) == "function" then
    return Predicate(_G.canaccessvalue, value)
  end
  if type(_G.issecretvalue) == "function" then
    return not Predicate(_G.issecretvalue, value)
  end
  return true
end

local function IsSecretValue(value)
  local guard = RDL.SecretGuard
  if guard and type(guard.IsSecret) == "function" then
    local ok, secret = pcall(guard.IsSecret, guard, value)
    return ok and secret == true
  end
  return type(_G.issecretvalue) == "function" and Predicate(_G.issecretvalue, value)
end

local function CanAccessTable(value)
  if not CanAccessValue(value) then return false end
  if type(value) ~= "table" then return false end
  if type(_G.issecrettable) == "function" and Predicate(_G.issecrettable, value) then
    return false
  end

  local guard = RDL.SecretGuard
  if guard and type(guard.CanAccessTable) == "function" then
    local ok, allowed = pcall(guard.CanAccessTable, guard, value)
    return ok and allowed == true
  end
  if type(_G.canaccesstable) == "function" then
    return Predicate(_G.canaccesstable, value)
  end
  return true
end

local function Scrub(value)
  local util = RDL.Util
  if util and type(util.Scrub) == "function" then
    local ok, ordinary = pcall(util.Scrub, util, value)
    if ok then return ordinary end
    return "<unavailable>"
  end
  if not CanAccessValue(value) then return "<inaccessible>" end
  if IsSecretValue(value) then return "<secret>" end
  return value
end

local function RawGet(tableValue, key)
  local ok, value = pcall(rawget, tableValue, key)
  if not ok then return false, nil end
  return true, value
end

local function RawNext(tableValue, key)
  local ok, nextKey, nextValue = pcall(next, tableValue, key)
  if not ok then return false, nil, nil end
  return true, nextKey, nextValue
end

local function IsFiniteNumber(value)
  return type(value) == "number"
    and value == value
    and value ~= math.huge
    and value ~= -math.huge
end

local function ClampInteger(value, fallback, minimum, maximum)
  value = Scrub(value)
  if not IsFiniteNumber(value) then return fallback end
  value = math.floor(value)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function RawOption(options, key)
  if not CanAccessTable(options) then return nil end
  local ok, value = RawGet(options, key)
  if not ok then return nil end
  return value
end

local function NormalizeOptions(options)
  local config = {
    maxDepth = 6,
    maxTableEntries = 200,
    maxArrayLen = 200,
    maxScanEntries = 5000,
    maxNodes = 5000,
    maxStringBytes = 64 * 1024,
    maxOutputBytes = 1024 * 1024,
    pretty = false,
    indentStep = 2,
  }

  if not CanAccessTable(options) then return config end
  config.maxDepth = ClampInteger(RawOption(options, "maxDepth"), config.maxDepth, 1, 16)
  config.maxTableEntries = ClampInteger(RawOption(options, "maxTableEntries"),
    config.maxTableEntries, 1, 5000)
  config.maxArrayLen = ClampInteger(RawOption(options, "maxArrayLen"),
    config.maxArrayLen, 1, 5000)
  config.maxScanEntries = ClampInteger(RawOption(options, "maxScanEntries"),
    config.maxScanEntries, 1, 20000)
  config.maxNodes = ClampInteger(RawOption(options, "maxNodes"),
    config.maxNodes, 1, 100000)
  config.maxStringBytes = ClampInteger(RawOption(options, "maxStringBytes"),
    config.maxStringBytes, 256, 1024 * 1024)
  config.maxOutputBytes = ClampInteger(RawOption(options, "maxOutputBytes"),
    config.maxOutputBytes, 4096, 8 * 1024 * 1024)
  config.indentStep = ClampInteger(RawOption(options, "indentStep"),
    config.indentStep, 0, 8)
  config.pretty = Scrub(RawOption(options, "pretty")) == true
  return config
end

local function CheckOutputSize(size, config)
  if size > config.maxOutputBytes then error(OUTPUT_LIMIT, 0) end
  return size
end

local function TruncateUTF8(value, maximum)
  if #value <= maximum then return value end

  local index, lastComplete = 1, 0
  while index <= #value and index <= maximum do
    local byte = string.byte(value, index)
    local width = 1
    if byte and byte >= 0xF0 then
      width = 4
    elseif byte and byte >= 0xE0 then
      width = 3
    elseif byte and byte >= 0xC0 then
      width = 2
    end
    if index + width - 1 > maximum then break end
    lastComplete = index + width - 1
    index = index + width
  end
  return value:sub(1, lastComplete) .. "<truncated>"
end

local function RenderUnsupported(value)
  local util = RDL.Util
  if util and type(util.SafeToString) == "function" then
    local ok, text = pcall(util.SafeToString, util, value)
    if ok and type(text) == "string" then return text end
  end
  return "<unsupported>"
end

local function EscapeString(value, config)
  local text = Scrub(value)
  if type(text) ~= "string" then text = RenderUnsupported(text) end

  local util = RDL.Util
  if util and type(util.FilterSecretEscapes) == "function" then
    local ok, filtered = pcall(util.FilterSecretEscapes, util, text)
    if ok and type(filtered) == "string" then text = filtered end
  else
    text = text:gsub("|K[^|]*|k", "<filtered>")
  end

  text = TruncateUTF8(text, config.maxStringBytes)
  text = text:gsub("\\", "\\\\")
    :gsub('"', '\\"')
    :gsub("\b", "\\b")
    :gsub("\f", "\\f")
    :gsub("\n", "\\n")
    :gsub("\r", "\\r")
    :gsub("\t", "\\t")
    :gsub("[%z\1-\31]", function(char)
      return string.format("\\u%04x", string.byte(char))
    end)

  local encoded = '"' .. text .. '"'
  CheckOutputSize(#encoded, config)
  return encoded
end

local function IndentString(count)
  return string.rep(" ", count)
end

local function JoinParts(opening, parts, separator, closing, config)
  local total = #opening + #closing
  for index = 1, #parts do
    if index > 1 then total = total + #separator end
    total = total + #parts[index]
    CheckOutputSize(total, config)
  end
  return opening .. table.concat(parts, separator) .. closing
end

local function InspectArray(value, config)
  local count, maximum, scanned = 0, 0, 0
  local rawKey = nil

  while true do
    local ok, nextKey = RawNext(value, rawKey)
    if not ok then return false, 0, "iteration-error" end
    if nextKey == nil then break end
    rawKey = nextKey
    scanned = scanned + 1
    if scanned > config.maxScanEntries then return false, 0, "scan-limit" end

    if not CanAccessValue(nextKey) or IsSecretValue(nextKey) then
      return false, 0, "inaccessible-key"
    end
    local ordinaryKey = Scrub(nextKey)
    if type(ordinaryKey) ~= "number" or ordinaryKey < 1 or ordinaryKey % 1 ~= 0 then
      return false, 0, nil
    end
    count = count + 1
    if ordinaryKey > maximum then maximum = ordinaryKey end
  end

  if maximum ~= count then return false, 0, nil end
  return true, maximum, nil
end

local function KeyRecord(key)
  if not CanAccessValue(key) or IsSecretValue(key) then return nil end
  local ordinary = Scrub(key)
  local keyType = type(ordinary)
  local keyText

  if keyType == "string" then
    keyText = ordinary
  elseif keyType == "number" and IsFiniteNumber(ordinary) then
    keyText = tostring(ordinary)
  elseif keyType == "boolean" then
    keyText = ordinary and "true" or "false"
  else
    keyText = RenderUnsupported(ordinary)
  end

  local rank = keyType == "string" and "1"
    or keyType == "number" and "2"
    or keyType == "boolean" and "3"
    or "9"
  return {
    key = keyText,
    keyType = keyType,
    sortKey = rank .. "\031" .. keyText,
  }
end

local function ResolveDuplicateObjectKeys(records)
  local used = {}
  for index = 1, #records do
    local record = records[index]
    local base = record.key
    local candidate = base
    if used[candidate] then
      candidate = "[" .. record.keyType .. "]" .. base
      local suffix = 2
      while used[candidate] do
        candidate = "[" .. record.keyType .. "]" .. base .. "#" .. suffix
        suffix = suffix + 1
      end
    end
    record.key = candidate
    used[candidate] = true
  end
  return used
end

local function AddTruncationRecord(records, usedKeys, reason)
  local key, suffix = "__truncated", 2
  while usedKeys[key] do
    key = "__truncated_" .. suffix
    suffix = suffix + 1
  end
  records[#records + 1] = {
    key = key,
    keyType = "string",
    sortKey = "0\031" .. key,
    rawValue = reason or true,
  }
end

local EncodeValue

local function EncodeArray(value, arrayLength, config, state, depth, seen, indent)
  local pretty = config.pretty
  local newline = pretty and "\n" or ""
  local separator = pretty and ",\n" or ","
  local childIndent = indent + config.indentStep
  local prefix = pretty and IndentString(childIndent) or ""
  local parts = {}
  local limit = math.min(arrayLength, config.maxArrayLen)

  for index = 1, limit do
    local ok, item = RawGet(value, index)
    if not ok then item = "<read-error>" end
    parts[#parts + 1] = prefix .. EncodeValue(item, config, state, depth + 1, seen, childIndent)
  end
  if arrayLength > limit then
    parts[#parts + 1] = prefix .. EscapeString("<truncated>", config)
  end

  if #parts == 0 then return "[]" end
  local opening = "[" .. newline
  local closing = newline .. (pretty and IndentString(indent) or "") .. "]"
  return JoinParts(opening, parts, separator, closing, config)
end

local function EncodeObject(value, config, state, depth, seen, indent)
  local pretty = config.pretty
  local newline = pretty and "\n" or ""
  local separator = pretty and ",\n" or ","
  local keySeparator = pretty and ": " or ":"
  local childIndent = indent + config.indentStep
  local prefix = pretty and IndentString(childIndent) or ""
  local records = {}
  local rawKey = nil
  local scanned, emitted = 0, 0
  local truncationReason

  while true do
    local ok, nextKey, nextValue = RawNext(value, rawKey)
    if not ok then
      truncationReason = "iteration-error"
      break
    end
    if nextKey == nil then break end
    rawKey = nextKey
    scanned = scanned + 1
    if scanned > config.maxScanEntries then
      truncationReason = "scan-limit"
      break
    end
    if emitted >= config.maxTableEntries then
      truncationReason = "entry-limit"
      break
    end

    local record = KeyRecord(nextKey)
    if not record then return EscapeString("<inaccessible-table>", config) end
    record.rawValue = nextValue
    records[#records + 1] = record
    emitted = emitted + 1
  end

  table.sort(records, function(a, b) return a.sortKey < b.sortKey end)
  local usedKeys = ResolveDuplicateObjectKeys(records)
  if truncationReason then AddTruncationRecord(records, usedKeys, truncationReason) end
  table.sort(records, function(a, b) return a.key < b.key end)

  local parts = {}
  for index = 1, #records do
    local record = records[index]
    local encodedValue = EncodeValue(record.rawValue, config, state, depth + 1, seen, childIndent)
    parts[index] = prefix .. EscapeString(record.key, config) .. keySeparator .. encodedValue
  end

  if #parts == 0 then return "{}" end
  local opening = "{" .. newline
  local closing = newline .. (pretty and IndentString(indent) or "") .. "}"
  return JoinParts(opening, parts, separator, closing, config)
end

EncodeValue = function(value, config, state, depth, seen, indent)
  state.nodes = state.nodes + 1
  if state.nodes > config.maxNodes then return EscapeString("<node-limit>", config) end

  local ordinary = Scrub(value)
  if ordinary == nil then return "null" end

  local valueType = type(ordinary)
  if valueType == "boolean" then return ordinary and "true" or "false" end
  if valueType == "number" then
    if not IsFiniteNumber(ordinary) then return "null" end
    return tostring(ordinary)
  end
  if valueType == "string" then return EscapeString(ordinary, config) end
  if valueType ~= "table" then return EscapeString(RenderUnsupported(ordinary), config) end

  if not CanAccessTable(ordinary) then return EscapeString("<inaccessible-table>", config) end
  if depth >= config.maxDepth then return EscapeString("<depth>", config) end
  if seen[ordinary] then return EscapeString("<cycle>", config) end
  seen[ordinary] = true

  local isArray, arrayLength, arrayError = InspectArray(ordinary, config)
  local encoded
  if arrayError == "inaccessible-key" then
    encoded = EscapeString("<inaccessible-table>", config)
  elseif arrayError == "scan-limit" then
    encoded = EscapeString("<table-scan-limit>", config)
  elseif arrayError == "iteration-error" then
    encoded = EscapeString("<table-iteration-error>", config)
  elseif isArray then
    encoded = EncodeArray(ordinary, arrayLength, config, state, depth, seen, indent)
  else
    encoded = EncodeObject(ordinary, config, state, depth, seen, indent)
  end

  seen[ordinary] = nil
  CheckOutputSize(#encoded, config)
  return encoded
end

function JSON:Encode(value, options)
  local config = NormalizeOptions(options)
  local state = { nodes = 0 }
  local ok, output = pcall(EncodeValue, value, config, state, 0, {}, 0)
  if not ok then
    if CanAccessValue(output) and not IsSecretValue(output) and output == OUTPUT_LIMIT then
      return '{"error":"json_output_limit"}'
    end
    return '{"error":"json_encode_failed"}'
  end
  if type(output) ~= "string" then return '{"error":"json_encode_failed"}' end
  return output
end
