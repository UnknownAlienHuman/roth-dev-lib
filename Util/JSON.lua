-- !RothDevLib/Util/JSON.lua
-- Minimal JSON encoder (no external deps).
-- Goals: strict output, secret-safe string filtering, bounded depth/size.

local RDL = _G.RothDevLib

local JSON = {}
RDL.JSON = JSON

local function IsFiniteNumber(n)
  if type(n) ~= "number" then return false end
  if n ~= n then return false end -- NaN
  if n == math.huge or n == -math.huge then return false end
  return true
end

local function EscapeString(s)
  s = tostring(s or "")
  -- Filter secret escapes if present
  local U = RDL.Util
  if U and U.FilterSecretEscapes then
    s = U:FilterSecretEscapes(s)
  else
    s = s:gsub("|K[^|]*|k", "<filtered>")
  end

  -- JSON escapes
  s = s:gsub("\\", "\\\\")
  s = s:gsub("\"", "\\\"")
  s = s:gsub("\b", "\\b")
  s = s:gsub("\f", "\\f")
  s = s:gsub("\n", "\\n")
  s = s:gsub("\r", "\\r")
  s = s:gsub("\t", "\\t")
  -- Control chars 0-31
  s = s:gsub("[%z\1-\31]", function(c)
    return string.format("\\u%04x", c:byte())
  end)
  return '"' .. s .. '"'
end

local function IsArray(t)
  -- Strict array: integer keys 1..n only
  local n = 0
  for k, _ in pairs(t) do
    if type(k) ~= "number" then return false end
    if k < 1 or k % 1 ~= 0 then return false end
    if k > n then n = k end
  end
  for i = 1, n do
    if rawget(t, i) == nil then return false end
  end
  return true, n
end

local function SortKeys(keys)
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
end

local function IndentStr(n)
  return string.rep(" ", n)
end

local function EncodeValue(v, opts, depth, seen, indent)
  opts = opts or {}
  depth = depth or 0
  indent = indent or 0
  local maxDepth = opts.maxDepth or 6
  local maxTableEntries = opts.maxTableEntries or 200
  local pretty = opts.pretty == true
  local indentStep = opts.indentStep or 2

  if v == nil then return "null" end

  local tv = type(v)
  if tv == "boolean" then return v and "true" or "false" end
  if tv == "number" then
    if not IsFiniteNumber(v) then return "null" end
    return tostring(v)
  end
  if tv == "string" then
    return EscapeString(v)
  end

  local U = RDL.Util
  local SG = RDL.SecretGuard
  if SG and SG.IsSecret and SG:IsSecret(v) then
    return EscapeString("<secret>")
  end

  if tv ~= "table" then
    -- userdata/function/thread
    local s = (U and U.SafeToString) and U:SafeToString(v) or tostring(v)
    return EscapeString(s)
  end

  if seen[v] then
    return EscapeString("<cycle>")
  end
  seen[v] = true

  if depth >= maxDepth then
    seen[v] = nil
    return EscapeString("<depth>")
  end

  local isArr, n = IsArray(v)
  local parts = {}
  local newline = pretty and "\n" or ""
  local sep = pretty and ",\n" or ","
  local keySep = pretty and ": " or ":"
  local childIndent = indent + indentStep

  if isArr then
    local limit = opts.maxArrayLen or n
    local m = math.min(n, limit)
    for i = 1, m do
      parts[#parts + 1] = (pretty and IndentStr(childIndent) or "") .. EncodeValue(v[i], opts, depth + 1, seen, childIndent)
    end
    if n > m then
      parts[#parts + 1] = (pretty and IndentStr(childIndent) or "") .. EscapeString("<truncated>")
    end
    local open = "[" .. newline
    local close = newline .. (pretty and IndentStr(indent) or "") .. "]"
    seen[v] = nil
    if #parts == 0 then return "[]" end
    return open .. table.concat(parts, sep) .. close
  end

  -- object
  local keys = {}
  for k, _ in pairs(v) do keys[#keys + 1] = k end
  SortKeys(keys)

  local emitted = 0
  for _, k in ipairs(keys) do
    emitted = emitted + 1
    if emitted > maxTableEntries then
      parts[#parts + 1] = (pretty and IndentStr(childIndent) or "") .. EscapeString("__truncated") .. keySep .. "true"
      break
    end
    local kk = EscapeString(tostring(k))
    local vv = EncodeValue(v[k], opts, depth + 1, seen, childIndent)
    parts[#parts + 1] = (pretty and IndentStr(childIndent) or "") .. kk .. keySep .. vv
  end

  local open = "{" .. newline
  local close = newline .. (pretty and IndentStr(indent) or "") .. "}"
  seen[v] = nil
  if #parts == 0 then return "{}" end
  return open .. table.concat(parts, sep) .. close
end

function JSON:Encode(value, opts)
  local ok, out = pcall(function()
    return EncodeValue(value, opts or {}, 0, {}, 0)
  end)
  if not ok then
    return "{\"error\":\"json_encode_failed\",\"message\":" .. EscapeString(tostring(out)) .. "}"
  end
  return out
end
