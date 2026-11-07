-- !RothDevLib/Util/BoundedCopy.lua
-- Bounded raw traversal for external diagnostic values.
-- Loaded after Util.lua and replaces only the generic copy/serialization boundary.

local RDL = _G.RothDevLib
local Util = RDL and RDL.Util
if not Util then return end

local function Predicate(fn, ...)
  local ok, value = pcall(fn, ...)
  if not ok then return false end
  return value == true
end

local function CanAccessValue(value)
  local guard = RDL.SecretGuard
  if guard and type(guard.CanAccess) == "function" then
    local ok, allowed = pcall(guard.CanAccess, guard, value)
    if not ok or allowed ~= true then return false end
  elseif type(_G.canaccessvalue) == "function" then
    if not Predicate(_G.canaccessvalue, value) then return false end
  end

  if guard and type(guard.IsSecret) == "function" then
    local ok, secret = pcall(guard.IsSecret, guard, value)
    if not ok or secret == true then return false end
  elseif type(_G.issecretvalue) == "function" then
    if Predicate(_G.issecretvalue, value) then return false end
  end
  return true
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

local function ClampInteger(value, fallback, minimum, maximum)
  if not CanAccessValue(value) or type(value) ~= "number" or value ~= value then
    return fallback
  end
  value = math.floor(value)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function RawOption(opts, key)
  if not CanAccessTable(opts) then return nil end
  local ok, value = pcall(rawget, opts, key)
  if not ok then return nil end
  return value
end

local function Options(opts)
  return {
    maxDepth = ClampInteger(RawOption(opts, "maxDepth"), 4, 1, 12),
    maxEntries = ClampInteger(RawOption(opts, "maxEntries"), 80, 1, 2000),
    maxNodes = ClampInteger(RawOption(opts, "maxNodes"), 500, 1, 20000),
    maxStringBytes = ClampInteger(RawOption(opts, "maxStringBytes"), 4096, 64, 1024 * 1024),
    maxTotalBytes = ClampInteger(RawOption(opts, "maxTotalBytes"),
      256 * 1024, 1024, 8 * 1024 * 1024),
  }
end

local function Truncate(value, maximum)
  if #value <= maximum then return value end
  return value:sub(1, maximum) .. "<truncated>"
end

local function FilterString(self, value, maximum)
  local filtered = value
  if type(self.FilterSecretEscapes) == "function" then
    local ok, result = pcall(self.FilterSecretEscapes, self, value)
    if ok and type(result) == "string" then filtered = result end
  end
  return Truncate(filtered, maximum)
end

local function MarkerForUnsupported(self, value)
  if type(self.SafeToString) == "function" then
    local ok, text = pcall(self.SafeToString, self, value)
    if ok and type(text) == "string" then return text end
  end
  return "<unsupported>"
end

local function SafeKey(self, key)
  if not CanAccessValue(key) then return nil, "inaccessible" end
  local keyType = type(key)

  if keyType == "string" then
    return FilterString(self, key, 256)
  end
  if keyType == "number" then
    if key ~= key then return "<nan-key>" end
    if key == math.huge then return "<infinity-key>" end
    if key == -math.huge then return "<-infinity-key>" end
    return key
  end
  if keyType == "boolean" then return key end
  return "[" .. keyType .. "]" .. MarkerForUnsupported(self, key)
end

function Util:CopyDiagnosticValue(value, opts)
  local config = Options(opts)
  local seen = {}
  local nodeCount = 0
  local byteCount = 0
  local byteLimitHit = false

  local function Reserve(bytes)
    if byteLimitHit then return false end
    bytes = tonumber(bytes) or 0
    if bytes < 0 then bytes = 0 end
    if byteCount + bytes > config.maxTotalBytes then
      byteLimitHit = true
      return false
    end
    byteCount = byteCount + bytes
    return true
  end

  local function Copy(current, depth)
    if byteLimitHit then return "<byte-limit>" end
    nodeCount = nodeCount + 1
    if nodeCount > config.maxNodes then return "<node-limit>" end
    if not Reserve(8) then return "<byte-limit>" end
    if not CanAccessValue(current) then return "<inaccessible>" end
    if current == nil then return nil end

    local currentType = type(current)
    if currentType == "string" then
      local filtered = FilterString(Util, current, config.maxStringBytes)
      if not Reserve(#filtered) then return "<byte-limit>" end
      return filtered
    end
    if currentType == "number" then
      if current ~= current then return "<nan>" end
      if current == math.huge then return "<infinity>" end
      if current == -math.huge then return "<-infinity>" end
      return current
    end
    if currentType == "boolean" then return current end
    if currentType ~= "table" then
      local marker = MarkerForUnsupported(Util, current)
      if not Reserve(#marker) then return "<byte-limit>" end
      return marker
    end

    if not CanAccessTable(current) then return "<inaccessible-table>" end
    if depth >= config.maxDepth then return "<depth>" end
    if seen[current] then return "<cycle>" end

    seen[current] = true
    local out, usedKeys = {}, {}
    local count, rawKey = 0, nil
    local truncated, truncationReason = false, nil

    while count < config.maxEntries do
      if byteLimitHit then
        truncated, truncationReason = true, "byte-limit"
        break
      end

      local ok, nextKey, nextValue = pcall(next, current, rawKey)
      if not ok then
        truncated, truncationReason = true, "iteration-error"
        break
      end
      if nextKey == nil then break end
      rawKey = nextKey
      count = count + 1

      local safeKey, keyError = SafeKey(Util, nextKey)
      if safeKey == nil then
        truncated, truncationReason = true, keyError or "inaccessible-key"
        break
      end

      local uniqueKey = safeKey
      local suffix = 2
      while usedKeys[uniqueKey] do
        uniqueKey = tostring(safeKey) .. "#" .. suffix
        suffix = suffix + 1
      end
      local keyBytes = type(uniqueKey) == "string" and #uniqueKey or 8
      if not Reserve(keyBytes + 8) then
        truncated, truncationReason = true, "byte-limit"
        break
      end

      usedKeys[uniqueKey] = true
      out[uniqueKey] = Copy(nextValue, depth + 1)
      if byteLimitHit then
        truncated, truncationReason = true, "byte-limit"
        break
      end
    end

    if not truncated then
      local ok, moreKey = pcall(next, current, rawKey)
      if not ok then
        truncated, truncationReason = true, "iteration-error"
      elseif moreKey ~= nil then
        truncated, truncationReason = true, "entry-limit"
      end
    end

    if truncated then
      local marker = "__rdl_truncated"
      local suffix = 2
      while usedKeys[marker] do
        marker = "__rdl_truncated_" .. suffix
        suffix = suffix + 1
      end
      out[marker] = truncationReason or true
    end

    seen[current] = nil
    return out
  end

  return Copy(value, 0)
end

local function SerializeCopy(self, value, depth, seen)
  if value == nil then return "nil" end
  local valueType = type(value)
  if valueType == "string" then return value end
  if valueType == "number" or valueType == "boolean" then return tostring(value) end
  if valueType ~= "table" then return MarkerForUnsupported(self, value) end
  if depth > 6 then return "<depth>" end
  if seen[value] then return "<cycle>" end

  seen[value] = true
  local entries, rawKey = {}, nil
  while true do
    local nextKey, nextValue = next(value, rawKey)
    if nextKey == nil then break end
    rawKey = nextKey
    entries[#entries + 1] = {
      key = tostring(nextKey),
      value = SerializeCopy(self, nextValue, depth + 1, seen),
    }
  end
  seen[value] = nil

  table.sort(entries, function(a, b) return a.key < b.key end)
  local parts = {}
  for index = 1, #entries do
    parts[index] = entries[index].key .. "=" .. entries[index].value
  end
  return "{ " .. table.concat(parts, ", ") .. " }"
end

function Util:SafeSerializeTable(value, depth)
  local startDepth = ClampInteger(depth, 0, 0, 6)
  local copy = self:CopyDiagnosticValue(value, {
    maxDepth = math.max(1, 6 - startDepth),
    maxEntries = 80,
    maxNodes = 500,
    maxStringBytes = 4096,
    maxTotalBytes = 256 * 1024,
  })
  return SerializeCopy(self, copy, startDepth, {})
end
