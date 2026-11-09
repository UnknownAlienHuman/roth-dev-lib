-- !RothDevLib/Util/JSON.lua
-- Deterministic diagnostic JSON encoder with raw bounded traversal and one
-- streaming output budget. Foreign __pairs/__index/__len metamethods are never
-- invoked and no subtree is assembled outside the global output ceiling.

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
    maxKeyBytes = 1024,
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
  config.maxKeyBytes = ClampInteger(RawOption(options, "maxKeyBytes"),
    config.maxKeyBytes, 64, 64 * 1024)
  config.maxOutputBytes = ClampInteger(RawOption(options, "maxOutputBytes"),
    config.maxOutputBytes, 4096, 8 * 1024 * 1024)
  config.indentStep = ClampInteger(RawOption(options, "indentStep"),
    config.indentStep, 0, 8)
  config.pretty = Scrub(RawOption(options, "pretty")) == true

  -- A key or scalar string can never contribute more useful bytes than the
  -- complete document budget. Clamp early to bound transient escaping work.
  config.maxStringBytes = math.min(config.maxStringBytes, config.maxOutputBytes)
  config.maxKeyBytes = math.min(config.maxKeyBytes, config.maxStringBytes, config.maxOutputBytes)
  return config
end

local function UTF8Prefix(value, maximum)
  if maximum <= 0 then return "" end
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
  return value:sub(1, lastComplete)
end

local function TruncateUTF8(value, maximum)
  if #value <= maximum then return value end
  return UTF8Prefix(value, maximum) .. "<truncated>"
end

-- Object-key identity is resolved after truncation, so key truncation must be
-- a strict final-byte contract. Appending an unbudgeted marker here would let a
-- later encoder pass collapse distinct keys again.
local function TruncateUTF8Exact(value, maximum)
  if maximum <= 0 then return "" end
  if #value <= maximum then return value end
  local marker = "<truncated>"
  if maximum <= #marker then return UTF8Prefix(marker, maximum) end
  return UTF8Prefix(value, maximum - #marker) .. marker
end

local function FilterString(value)
  local filtered = value
  local util = RDL.Util
  if util and type(util.FilterSecretEscapes) == "function" then
    local ok, result = pcall(util.FilterSecretEscapes, util, value)
    if ok and type(result) == "string" then filtered = result end
  else
    filtered = value:gsub("|K[^|]*|k", "<filtered>")
  end

  -- Truncation may cut a |K...|k escape before its terminator. Never emit the
  -- remaining opaque payload as plain diagnostic text.
  local incomplete = filtered:find("|K", 1, true)
  if incomplete then filtered = filtered:sub(1, incomplete - 1) .. "<filtered>" end
  return filtered
end

local function RenderUnsupported(value)
  local util = RDL.Util
  if util and type(util.SafeToString) == "function" then
    local ok, text = pcall(util.SafeToString, util, value)
    if ok and type(text) == "string" then return text end
  end
  return "<unsupported>"
end

local function EscapedString(value, maximum, exactLimit)
  local text = Scrub(value)
  if type(text) ~= "string" then text = RenderUnsupported(text) end
  text = FilterString(exactLimit and TruncateUTF8Exact(text, maximum)
    or TruncateUTF8(text, maximum))
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
  return '"' .. text .. '"'
end

local function Emit(state, text)
  local nextBytes = state.outputBytes + #text
  if nextBytes > state.config.maxOutputBytes then error(OUTPUT_LIMIT, 0) end
  state.outputBytes = nextBytes
  state.chunks[#state.chunks + 1] = text
end

local function EmitString(state, value, maximum, exactLimit)
  Emit(state, EscapedString(value, maximum or state.config.maxStringBytes, exactLimit))
end

local function EmitIndent(state, count)
  if count > 0 then Emit(state, string.rep(" ", count)) end
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

local HASH_MODULUS = 4294967296

-- Most long-key comparisons use a bounded stable fingerprint. Full string
-- comparison is retained only as a collision fallback, so output is stable
-- across table insertion/hash order without doing unbounded work normally.
local function KeyFingerprint(value)
  local length = #value
  local sample
  if length <= 2048 then
    sample = value
  else
    local quarter = math.floor(length / 4)
    local middle = math.floor(length / 2)
    local threeQuarter = math.floor(length * 3 / 4)
    sample = value:sub(1, 512)
      .. value:sub(math.max(1, quarter - 127), math.min(length, quarter + 128))
      .. value:sub(math.max(1, middle - 255), math.min(length, middle + 256))
      .. value:sub(math.max(1, threeQuarter - 127), math.min(length, threeQuarter + 128))
      .. value:sub(math.max(1, length - 511), length)
  end

  local hashA, hashB = 5381, 2166136261
  for index = 1, #sample do
    local byte = string.byte(sample, index)
    hashA = (hashA * 33 + byte) % HASH_MODULUS
    hashB = (hashB * 131 + byte) % HASH_MODULUS
  end
  return string.format("%x:%08x:%08x", length, hashA, hashB)
end

local function KeyRecord(key, config)
  if not CanAccessValue(key) or IsSecretValue(key) then return nil, "inaccessible-key" end
  local ordinary = Scrub(key)
  local keyType = type(ordinary)
  local keyText, identity, rawSort

  if keyType == "string" then
    keyText = TruncateUTF8Exact(FilterString(ordinary), config.maxKeyBytes)
    identity = KeyFingerprint(ordinary)
    rawSort = ordinary
  elseif keyType == "number" and IsFiniteNumber(ordinary) then
    keyText = tostring(ordinary)
    identity = keyText
  elseif keyType == "boolean" then
    keyText = ordinary and "true" or "false"
    identity = keyText
  else
    -- Tables/functions/threads/userdata have no stable cross-run identity.
    -- Skipping them with an explicit marker is deterministic; rendering an
    -- address or assigning sequence suffixes from hash iteration order is not.
    return nil, "unsupported-key"
  end

  local rank = keyType == "string" and "1"
    or keyType == "number" and "2"
    or "3"
  return {
    key = keyText,
    keyType = keyType,
    sortKey = rank .. "\031" .. keyText .. "\031" .. identity,
    rawSort = rawSort,
  }
end

local function ResolveDuplicateObjectKeys(records, config)
  local used = {}
  for index = 1, #records do
    local record = records[index]
    local base = TruncateUTF8Exact(record.key, config.maxKeyBytes)
    local candidate = base
    if used[candidate] then
      local prefix = "[" .. record.keyType .. "]"
      candidate = TruncateUTF8Exact(prefix .. base, config.maxKeyBytes)
      local suffix = 2
      while used[candidate] do
        local suffixText = "#" .. suffix
        local available = math.max(0, config.maxKeyBytes - #prefix - #suffixText)
        candidate = prefix .. TruncateUTF8Exact(base, available) .. suffixText
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

local function EncodeArray(value, arrayLength, state, depth, seen, indent)
  local config = state.config
  local pretty = config.pretty
  local childIndent = indent + config.indentStep
  local limit = math.min(arrayLength, config.maxArrayLen)
  local itemCount = limit + (arrayLength > limit and 1 or 0)

  Emit(state, "[")
  if itemCount > 0 and pretty then Emit(state, "\n") end

  for index = 1, limit do
    if index > 1 then Emit(state, pretty and ",\n" or ",") end
    if pretty then EmitIndent(state, childIndent) end
    local ok, item = RawGet(value, index)
    EncodeValue(ok and item or "<read-error>", state, depth + 1, seen, childIndent)
  end

  if arrayLength > limit then
    if limit > 0 then Emit(state, pretty and ",\n" or ",") end
    if pretty then EmitIndent(state, childIndent) end
    EmitString(state, "<truncated>")
  end

  if itemCount > 0 and pretty then
    Emit(state, "\n")
    EmitIndent(state, indent)
  end
  Emit(state, "]")
end

local function EncodeObject(value, state, depth, seen, indent)
  local config = state.config
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

    local record, keyError = KeyRecord(nextKey, config)
    if not record then
      if keyError == "inaccessible-key" then
        EmitString(state, "<inaccessible-table>")
        return
      end
      truncationReason = truncationReason or keyError or "unsupported-key"
    else
      record.rawValue = nextValue
      records[#records + 1] = record
      emitted = emitted + 1
    end
  end

  table.sort(records, function(a, b)
    if a.sortKey ~= b.sortKey then return a.sortKey < b.sortKey end
    if a.rawSort ~= nil and b.rawSort ~= nil and a.rawSort ~= b.rawSort then
      return a.rawSort < b.rawSort
    end
    return false
  end)
  local usedKeys = ResolveDuplicateObjectKeys(records, config)
  if truncationReason then AddTruncationRecord(records, usedKeys, truncationReason) end
  table.sort(records, function(a, b) return a.key < b.key end)

  local pretty = config.pretty
  local childIndent = indent + config.indentStep
  Emit(state, "{")
  if #records > 0 and pretty then Emit(state, "\n") end

  for index = 1, #records do
    if index > 1 then Emit(state, pretty and ",\n" or ",") end
    if pretty then EmitIndent(state, childIndent) end
    local record = records[index]
    EmitString(state, record.key, config.maxKeyBytes, true)
    Emit(state, pretty and ": " or ":")
    EncodeValue(record.rawValue, state, depth + 1, seen, childIndent)
  end

  if #records > 0 and pretty then
    Emit(state, "\n")
    EmitIndent(state, indent)
  end
  Emit(state, "}")
end

EncodeValue = function(value, state, depth, seen, indent)
  local config = state.config
  state.nodes = state.nodes + 1
  if state.nodes > config.maxNodes then
    EmitString(state, "<node-limit>")
    return
  end

  local ordinary = Scrub(value)
  if ordinary == nil then
    Emit(state, "null")
    return
  end

  local valueType = type(ordinary)
  if valueType == "boolean" then
    Emit(state, ordinary and "true" or "false")
    return
  end
  if valueType == "number" then
    Emit(state, IsFiniteNumber(ordinary) and tostring(ordinary) or "null")
    return
  end
  if valueType == "string" then
    EmitString(state, ordinary)
    return
  end
  if valueType ~= "table" then
    EmitString(state, RenderUnsupported(ordinary))
    return
  end

  if not CanAccessTable(ordinary) then
    EmitString(state, "<inaccessible-table>")
    return
  end
  if depth >= config.maxDepth then
    EmitString(state, "<depth>")
    return
  end
  if seen[ordinary] then
    EmitString(state, "<cycle>")
    return
  end
  seen[ordinary] = true

  local isArray, arrayLength, arrayError = InspectArray(ordinary, config)
  if arrayError == "inaccessible-key" then
    EmitString(state, "<inaccessible-table>")
  elseif arrayError == "scan-limit" then
    EmitString(state, "<table-scan-limit>")
  elseif arrayError == "iteration-error" then
    EmitString(state, "<table-iteration-error>")
  elseif isArray then
    EncodeArray(ordinary, arrayLength, state, depth, seen, indent)
  else
    EncodeObject(ordinary, state, depth, seen, indent)
  end

  seen[ordinary] = nil
end

function JSON:Encode(value, options)
  local config = NormalizeOptions(options)
  local state = {
    config = config,
    chunks = {},
    outputBytes = 0,
    nodes = 0,
  }
  local ok, failure = pcall(EncodeValue, value, state, 0, {}, 0)
  if not ok then
    if CanAccessValue(failure) and not IsSecretValue(failure) and failure == OUTPUT_LIMIT then
      return '{"error":"json_output_limit"}'
    end
    return '{"error":"json_encode_failed"}'
  end
  return table.concat(state.chunks)
end
