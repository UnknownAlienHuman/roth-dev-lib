-- !RothDevLib/Util/Logger.lua
-- Bounded in-memory logger. Line count is not a memory bound by itself, so
-- every field, line and the complete retained log have explicit byte budgets.

local RDL = _G.RothDevLib
local Logger = {}
RDL.Logger = Logger

local DEFAULT_MAX_LINES = 300
local MAX_LINES = 1000
local MAX_LEVEL_BYTES = 16
local MAX_TAG_BYTES = 64
local MAX_MESSAGE_BYTES = 4096
local MAX_DATA_BYTES = 4096
local MAX_LINE_BYTES = 8192
local MAX_TOTAL_BYTES = 2 * 1024 * 1024

Logger.maxLines = DEFAULT_MAX_LINES
Logger._bytes = 0
Logger._dropped = 0

local function Truncate(value, maximum)
  if #value <= maximum then return value end
  return value:sub(1, maximum) .. "<truncated>"
end

local function SafeText(value, fallback, maximum)
  local text = fallback
  local util = RDL.Util
  if util and type(util.SafeToString) == "function" then
    local ok, rendered = pcall(util.SafeToString, util, value)
    if ok and type(rendered) == "string" then text = rendered end
  elseif type(value) == "string" then
    text = value
  elseif type(value) == "number" or type(value) == "boolean" then
    text = tostring(value)
  end
  if type(text) ~= "string" then text = fallback end

  if util and type(util.FilterSecretEscapes) == "function" then
    local ok, filtered = pcall(util.FilterSecretEscapes, util, text)
    if ok and type(filtered) == "string" then text = filtered end
  end
  return Truncate(text, maximum)
end

local function Timestamp()
  if type(_G.date) == "function" then
    local ok, value = pcall(_G.date, "%H:%M:%S")
    if ok and type(value) == "string" then return Truncate(value, 32) end
  end
  return "??:??:??"
end

local function NormalizeMaximum(value)
  value = tonumber(value) or DEFAULT_MAX_LINES
  if value ~= value then value = DEFAULT_MAX_LINES end
  value = math.floor(value)
  if value < 1 then return 1 end
  if value > MAX_LINES then return MAX_LINES end
  return value
end

local function RemoveOldest(self)
  local line = table.remove(self.lines, 1)
  if type(line) == "string" then
    self._bytes = math.max(0, (tonumber(self._bytes) or 0) - #line)
  end
  self._dropped = (tonumber(self._dropped) or 0) + 1
end

local function Trim(self)
  local maximum = NormalizeMaximum(self.maxLines)
  self.maxLines = maximum
  while #self.lines > maximum or (tonumber(self._bytes) or 0) > MAX_TOTAL_BYTES do
    RemoveOldest(self)
  end
end

function Logger:Init()
  local source = type(self.lines) == "table" and self.lines or {}
  self.lines = {}
  self._bytes = 0
  self._dropped = tonumber(self._dropped) or 0
  self.maxLines = NormalizeMaximum(self.maxLines)

  local first = math.max(1, #source - self.maxLines + 1)
  for index = first, #source do
    local line = SafeText(source[index], "<invalid log line>", MAX_LINE_BYTES)
    self.lines[#self.lines + 1] = line
    self._bytes = self._bytes + #line
  end
  Trim(self)
end

function Logger:Log(level, tag, message, data)
  if type(self.lines) ~= "table" then self:Init() end

  local levelText = SafeText(level, "INFO", MAX_LEVEL_BYTES)
  local tagText = SafeText(tag, "LOG", MAX_TAG_BYTES)
  local messageText = SafeText(message, "", MAX_MESSAGE_BYTES)
  local line = string.format("[%s][%s][%s] %s",
    Timestamp(), levelText, tagText, messageText)

  if data ~= nil and RDL.Util and type(RDL.Util.SafeSerializeTable) == "function" then
    local ok, serialized = pcall(RDL.Util.SafeSerializeTable, RDL.Util, data)
    if ok and type(serialized) == "string" then
      line = line .. " " .. Truncate(serialized, MAX_DATA_BYTES)
    end
  end

  line = Truncate(line, MAX_LINE_BYTES)
  self.lines[#self.lines + 1] = line
  self._bytes = (tonumber(self._bytes) or 0) + #line
  Trim(self)
  return true
end

function Logger:GetText()
  if type(self.lines) ~= "table" then return "" end
  return table.concat(self.lines, "\n")
end

function Logger:Clear()
  self.lines = {}
  self._bytes = 0
  self._dropped = 0
end

function Logger:GetStats()
  return {
    lines = type(self.lines) == "table" and #self.lines or 0,
    maxLines = NormalizeMaximum(self.maxLines),
    bytes = tonumber(self._bytes) or 0,
    maxBytes = MAX_TOTAL_BYTES,
    maxLineBytes = MAX_LINE_BYTES,
    dropped = tonumber(self._dropped) or 0,
  }
end
