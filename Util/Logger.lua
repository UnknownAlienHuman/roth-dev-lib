-- !RothDevLib/Util/Logger.lua
-- Lightweight in-memory logger: last N lines, optionally echoes.

local RDL = _G.RothDevLib
local Logger = {}
RDL.Logger = Logger

Logger.maxLines = 300

function Logger:Init()
  self.lines = self.lines or {}
end

function Logger:Log(level, tag, msg, data)
  self.lines = self.lines or {}
  local ts = date("%H:%M:%S")
  local line = string.format("[%s][%s][%s] %s", ts, level, tag, tostring(msg))
  if data and RDL.Util then
    line = line .. " " .. RDL.Util:SafeSerializeTable(data)
  end
  table.insert(self.lines, line)
  if #self.lines > self.maxLines then
    table.remove(self.lines, 1)
  end
end

function Logger:GetText()
  return table.concat(self.lines or {}, "\n")
end
