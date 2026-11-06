-- !RothDevLib/Util/JSON.lua
-- Deterministic diagnostic JSON encoder with ordinary-value and size boundaries.

local RDL = _G.RothDevLib

local JSON = {}
RDL.JSON = JSON

local OUTPUT_LIMIT = {}

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

local function Scrub(value)
  local U = RDL.Util
  if U and type(U.Scrub) == "function" then
    return U:Scrub(value)
  end
  if not CanAccessValue(value) then return "<inaccessible>" end
  if IsSecretValue(value) then return "<secret>" end
  return value
end

local function IsFiniteNumber(value)
  if type(value) ~= "number" then return false end
  if value ~= value then return false end -- NaN
  if value == math.huge or value == -math.huge then return false end
  return true
end

local function ClampInteger(value, default, minimum, maximum)
  value = Scrub(value)
  if type(value) ~= "number" then return default end
  value = math.floor(value)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function NormalizeOptions(opts)
  local config = {
    maxDepth = 6,
    maxTableEntries = 200,
    maxArrayLen = 200,
    maxScanEntries = 5000,
    maxStringBytes = 64 * 1024,
    maxOutputBytes = 1024 * 1024,
    pretty = false,
    indentStep = 2,
  }

  local ordinary = Scrub(opts)
  if type(ordinary) ~= "table" or IsSecretTable(ordinary) or not CanAccessTable(ordinary) then
    return config
  end

  config.maxDepth = ClampInteger(ordinary.maxDepth, config.maxDepth, 1, 16)
  config.maxTableEntries = ClampInteger(ordinary.maxTableEntries, config.maxTableEntries, 1, 5000)
  config.maxArrayLen = ClampInteger(ordinary.maxArrayLen, config.maxArrayLen, 1, 5000)
  config.maxScanEntries = ClampInteger(ordinary.maxScanEntries, config.maxScanEntries, 1, 20000)
  config.maxStringBytes = ClampInteger(ordinary.maxStringBytes, config.maxStringBytes, 256, 1024 * 1024)
  config.maxOutputBytes = ClampInteger(ordinary.maxOutputBytes, config.maxOutputBytes, 4096, 8 * 1024 * 1024)

  local pretty = Scrub(ordinary.pretty)
  config.pretty = pretty == true
  config.indentStep = ClampInteger(ordinary.indentStep, config.indentStep, 0, 8)
  return config
end

local function CheckOutputSize(size, config)
  if size > config.maxOutputBytes then
    error(OUTPUT_LIMIT, 0)
  end
  return size
end

local function TruncateUTF8(value, maxBytes)
  if #value <= maxBytes then return value end

  local index = 1
  local lastComplete = 0
  while index <= #value and index <= maxBytes do
    local byte = string.byte(value, index)
    local width = 1
    if byte >= 0xF0 then
      width = 4
    elseif byte >= 0xE0 then
      width = 3
    elseif byte >= 0xC0 then
      width = 2
    end

    if index + width - 1 > maxBytes then break end
    lastComplete = index + width - 1
    index = index + width
  end

  return value:sub(1, lastComplete) .. "<truncated>"
end

local function EscapeString(value, config)
  local stringValue = Scrub(value)
  if type(stringValue) ~= "string" then
    local U = RDL.Util
    stringValue = U and U.SafeToString and U:SafeToString(stringValue) or "<unsupported>"
  end

  local U = RDL.Util
  if U and U.FilterSecretEscapes then
    stringValue = U:FilterSecretEscapes(stringValue)
  else
    stringValue = stringValue:gsub("|K[^|]*|k", "<filtered>")
  end

  stringValue = TruncateUTF8(stringValue, config.maxStringBytes)
  stringValue = stringValue:gsub("\\", "\\\\")
  stringValue = stringValue:gsub("\"", "\\\"")
  stringValue = stringValue:gsub("\b", "\\b")
  stringValue = stringValue:gsub("\f", "\\f")
  stringValue = stringValue:gsub("\n", "\\n")
  stringValue = stringValue:gsub("\r", "\\r")
  stringValue = stringValue:gsub("\t", "\\t")
  stringValue = stringValue:gsub("[%z\1-\31]", function(char)
    return string.format("\\u%04x", string.byte(char))
  end)

  local encoded = '"' .. stringValue .. '"'
  CheckOutputSize(#encoded, config)
  return encoded
end

local function InspectArray(value, config)
  local count, maximum = 0, 0
  for key in pairs(value) do
    if not CanAccessValue(key) or IsSecretValue(key) then
      return false, 0, "inaccessible-key"
    end

    local ordinaryKey = Scrub(key)
    if type(ordinaryKey) ~= "number" or ordinaryKey < 1 or ordinaryKey % 1 ~= 0 then
      return false, 0, nil
    end

    count = count + 1
    if count > config.maxScanEntries then
      return false, 0, "scan-limit"
    end
    if ordinaryKey > maximum then maximum = ordinaryKey end
  end

  if maximum ~= count then return false, 0, nil end
  return true, maximum, nil
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

local function RenderUnsupported(value)
  local U = RDL.Util
  return U and U.SafeToString and U:SafeToString(value) or "<unsupported>"
end

local function KeyRecord(key)
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

local function AddTruncationRecord(records, usedKeys)
  local key = "__truncated"
  local suffix = 2
  while usedKeys[key] do
    key = "__truncated_" .. suffix
    suffix = suffix + 1
  end
  records[#records + 1] = {
    key = key,
    keyType = "string",
    sortKey = "0\031" .. key,
    encoded = "true",
  }
end

local EncodeValue

local function EncodeArray(value, arrayLength, config, depth, seen, indent)
  local pretty = config.pretty
  local newline = pretty and "\n" or ""
  local separator = pretty and ",\n" or ","
  local childIndent = indent + config.indentStep
  local prefix = pretty and IndentString(childIndent) or ""
  local parts = {}
  local estimatedSize = 2

  local limit = math.min(arrayLength, config.maxArrayLen)
  for index = 1, limit do
    local encoded = EncodeValue(value[index], config, depth + 1, seen, childIndent)
    local part = prefix .. encoded
    estimatedSize = estimatedSize + #part + (index > 1 and #separator or 0)
    CheckOutputSize(estimatedSize, config)
    parts[#parts + 1] = part
  end
  if arrayLength > limit then
    local part = prefix .. EscapeString("<truncated>", config)
    estimatedSize = estimatedSize + #part + (#parts > 0 and #separator or 0)
    CheckOutputSize(estimatedSize, config)
    parts[#parts + 1] = part
  end

  if #parts == 0 then return "[]" end
  local opening = "[" .. newline
  local closing = newline .. (pretty and IndentString(indent) or "") .. "]"
  return JoinParts(opening, parts, separator, closing, config)
end

local function EncodeObject(value, config, depth, seen, indent)
  local pretty = config.pretty
  local newline = pretty and "\n" or ""
  local separator = pretty and ",\n" or ","
  local keySeparator = pretty and ": " or ":"
  local childIndent = indent + config.indentStep
  local prefix = pretty and IndentString(childIndent) or ""
  local records = {}
  local emitted = 0
  local truncated = false
  local estimatedSize = 2

  for key, item in pairs(value) do
    if not CanAccessValue(key) or IsSecretValue(key) then
      return EscapeString("<inaccessible-table>", config)
    end

    emitted = emitted + 1
    if emitted > config.maxTableEntries then
      truncated = true
      break
    end

    local record = KeyRecord(key)
    record.encoded = EncodeValue(item, config, depth + 1, seen, childIndent)
    local estimatedKeyBytes = math.min(#record.key, config.maxStringBytes) * 6 + 2
    estimatedSize = estimatedSize + estimatedKeyBytes + #record.encoded + #prefix + #keySeparator
      + (#records > 0 and #separator or 0)
    CheckOutputSize(estimatedSize, config)
    records[#records + 1] = record
  end

  table.sort(records, function(a, b)
    return a.sortKey < b.sortKey
  end)

  local usedKeys = ResolveDuplicateObjectKeys(records)
  if truncated then AddTruncationRecord(records, usedKeys) end

  table.sort(records, function(a, b)
    return a.key < b.key
  end)

  local parts = {}
  for index = 1, #records do
    local record = records[index]
    parts[index] = prefix .. EscapeString(record.key, config) .. keySeparator .. record.encoded
  end

  if #parts == 0 then return "{}" end
  local opening = "{" .. newline
  local closing = newline .. (pretty and IndentString(indent) or "") .. "}"
  return JoinParts(opening, parts, separator, closing, config)
end

EncodeValue = function(value, config, depth, seen, indent)
  local ordinary = Scrub(value)
  if ordinary == nil then return "null" end

  local valueType = type(ordinary)
  if valueType == "boolean" then return ordinary and "true" or "false" end
  if valueType == "number" then
    if not IsFiniteNumber(ordinary) then return "null" end
    return tostring(ordinary)
  end
  if valueType == "string" then
    return EscapeString(ordinary, config)
  end
  if valueType ~= "table" then
    return EscapeString(RenderUnsupported(ordinary), config)
  end

  if IsSecretTable(ordinary) or not CanAccessTable(ordinary) then
    return EscapeString("<inaccessible-table>", config)
  end
  if depth >= config.maxDepth then
    return EscapeString("<depth>", config)
  end
  if seen[ordinary] then
    return EscapeString("<cycle>", config)
  end
  seen[ordinary] = true

  local isArray, arrayLength, arrayError = InspectArray(ordinary, config)
  local encoded
  if arrayError == "inaccessible-key" then
    encoded = EscapeString("<inaccessible-table>", config)
  elseif arrayError == "scan-limit" then
    encoded = EscapeString("<table-scan-limit>", config)
  elseif isArray then
    encoded = EncodeArray(ordinary, arrayLength, config, depth, seen, indent)
  else
    encoded = EncodeObject(ordinary, config, depth, seen, indent)
  end

  seen[ordinary] = nil
  CheckOutputSize(#encoded, config)
  return encoded
end

function JSON:Encode(value, opts)
  local config = NormalizeOptions(opts)
  local ok, output = pcall(EncodeValue, value, config, 0, {}, 0)
  if not ok then
    if CanAccessValue(output) and not IsSecretValue(output) and output == OUTPUT_LIMIT then
      return '{"error":"json_output_limit"}'
    end
    return '{"error":"json_encode_failed"}'
  end
  if type(output) ~= "string" then
    return '{"error":"json_encode_failed"}'
  end
  return output
end
