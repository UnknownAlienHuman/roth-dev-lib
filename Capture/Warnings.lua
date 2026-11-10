-- !RothDevLib/Capture/Warnings.lua
-- Bounded LUA_WARNING intake for old and current payload shapes.

local RDL = _G.RothDevLib
local Capture = RDL and RDL.Capture
if not Capture then return end

local ACCEPTED_STATUS = { stored = true, queued = true, ignored = true }

local function SafeCopy(value, options)
  local util = RDL.Util
  if util and type(util.CopyDiagnosticValue) == "function" then
    local ok, copy = pcall(util.CopyDiagnosticValue, util, value, options or {
      maxDepth = 3,
      maxEntries = 40,
      maxNodes = 200,
      maxStringBytes = 4096,
    })
    if ok then return copy end
  end
  return nil
end

local function SafeText(value, fallback, maximum)
  local util = RDL.Util
  local text = type(fallback) == "string" and fallback or ""
  if util and type(util.SafeToString) == "function" then
    local ok, rendered = pcall(util.SafeToString, util, value)
    if ok and type(rendered) == "string" then text = rendered end
  elseif type(value) == "string" then
    text = value
  end
  if util and type(util.FilterSecretEscapes) == "function" then
    local ok, filtered = pcall(util.FilterSecretEscapes, util, text)
    if ok and type(filtered) == "string" then text = filtered end
  end
  maximum = tonumber(maximum) or 8192
  if #text > maximum then text = text:sub(1, maximum) .. "<truncated>" end
  return text
end

local function Stack()
  if type(_G.debugstack) ~= "function" then return "" end
  local ok, value = pcall(_G.debugstack, 3, 40, 40)
  return ok and SafeText(value, "", 128 * 1024) or ""
end

local function ContainsAddonPath(value)
  return type(value) == "string" and value:find("Interface/AddOns/", 1, true) ~= nil
end

function Capture:OnLuaWarning(...)
  if self._disabled then return nil end
  if type(self.BuildEntry) ~= "function" or type(self.StoreEntry) ~= "function" then return nil end

  local count = math.min(select("#", ...), 5)
  local args = { n = count }
  for index = 1, count do
    args[index] = SafeCopy(select(index, ...), {
      maxDepth = 2,
      maxEntries = 20,
      maxNodes = 80,
      maxStringBytes = 32 * 1024,
    })
  end

  local first = SafeText(args[1], "", 32 * 1024)
  local second = SafeText(args[2], "", 32 * 1024)
  local third = SafeText(args[3], "", 32 * 1024)
  local warningType, warningText

  if first ~= "" and second ~= "" and not ContainsAddonPath(first) and ContainsAddonPath(second) then
    warningType, warningText = first, second
  else
    warningText = first
    if warningText == "" and second ~= "" then warningText = second end
    if second ~= "" and not ContainsAddonPath(warningText) and ContainsAddonPath(second) then
      warningType, warningText = first ~= "" and first or nil, second
    end
  end

  local originText
  if ContainsAddonPath(warningText) then
    originText = warningText
  elseif ContainsAddonPath(second) then
    originText = second
  elseif ContainsAddonPath(third) then
    originText = third
  end

  local originAddon = originText and originText:match("Interface/AddOns/([^/]+)/") or nil
  local originFile, originLine
  if originText then originFile, originLine = originText:match("(Interface/AddOns/[^:]+):(%d+)") end

  local message = warningType and ("LUA_WARNING(" .. warningType .. "): " .. warningText)
    or ("LUA_WARNING: " .. warningText)
  local extra = {
    raw = args,
    warnType = warningType,
    warningText = warningText,
    origin = {
      addon = originAddon,
      file = originFile,
      line = originLine and tonumber(originLine) or nil,
    },
  }
  local funcName = originFile and originLine
    and ((originFile:match("Interface/AddOns/[^/]+/(.+)") or originFile) .. ":" .. originLine)
    or nil

  local okBuild, entry = pcall(self.BuildEntry, "LUA_WARNING", message, Stack(), nil,
    originAddon, funcName, SafeCopy(extra))
  if not okBuild or type(entry) ~= "table" then return nil, "build-failed" end
  entry.origin = SafeCopy(extra.origin)

  local okStore, status = pcall(self.StoreEntry, entry)
  if not okStore or not ACCEPTED_STATUS[status] then return nil, status or "store-failed" end
  if (status == "stored" or status == "queued") and type(RDL.Log) == "function" then
    pcall(RDL.Log, RDL, "WARN", "LUA_WARNING", "Lua warning captured", {
      addon = originAddon,
      warningType = warningType,
    })
  end
  return entry, status
end
