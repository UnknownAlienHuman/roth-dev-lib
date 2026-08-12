-- !RothDevLib/Capture/Warnings.lua
-- LUA_WARNING event handler.
-- Extracted from monolithic Capture.lua.
-- Patch-safe: handles both old (warnType, warningText) and new signatures.

local RDL = _G.RothDevLib

-- Called from Core/Events.lua when LUA_WARNING fires.
-- Uses Capture.BuildEntry / Capture.StoreEntry from ErrorHandler.lua.
function RDL.Capture:OnLuaWarning(...)
  if self._disabled then return end

  local Capture = self
  local BuildEntry = Capture.BuildEntry
  local StoreEntry = Capture.StoreEntry
  if not BuildEntry or not StoreEntry then return end

  local U = RDL.Util
  local a1, a2, a3, a4, a5 = ...
  if U and U.ScrubVarargs then
    a1, a2, a3, a4, a5 = U:ScrubVarargs(a1, a2, a3, a4, a5)
  end

  -- Patch drift: historically LUA_WARNING delivered (warnType, warningText).
  -- In newer clients warnType may be removed and only warningText remains.
  local warnType, warningText = nil, nil
  if type(a1) == "string" and type(a2) == "string"
     and (not a1:find("Interface/AddOns/"))
     and a2:find("Interface/AddOns/") then
    warnType, warningText = a1, a2
  else
    warningText = (type(a1) == "string") and a1 or (U and U:SafeToString(a1) or tostring(a1))
    if type(a2) == "string" and a2 ~= ""
       and not warningText:find("Interface/AddOns/")
       and a2:find("Interface/AddOns/") then
      warningText = a2
      warnType = (type(a1) == "string") and a1 or nil
    end
  end

  -- Origin detection: which addon / file / line
  local originText = nil
  if type(warningText) == "string" and warningText:find("Interface/AddOns/") then
    originText = warningText
  elseif type(a2) == "string" and a2:find("Interface/AddOns/") then
    originText = a2
  elseif type(a3) == "string" and a3:find("Interface/AddOns/") then
    originText = a3
  end

  local originAddon = originText and originText:match("Interface/AddOns/([^/]+)/") or nil
  local originFile, originLine = nil, nil
  if originText then
    originFile, originLine = originText:match("(Interface/AddOns/[^:]+):(%d+)")
  end

  local msg = "LUA_WARNING: " .. tostring(warningText or "")
  if warnType then
    msg = "LUA_WARNING(" .. tostring(warnType) .. "): " .. tostring(warningText or "")
  end

  local stack = debugstack(2, 40, 40)
  local extra = {
    raw = { a1, a2, a3, a4, a5 },
    warnType = warnType,
    warningText = warningText,
    origin = { addon = originAddon, file = originFile, line = originLine },
  }

  local funcGuess = (originFile and originLine)
    and (originFile:match("Interface/AddOns/[^/]+/(.+)") .. ":" .. originLine)
    or nil

  local entry = BuildEntry("LUA_WARNING", msg, stack, nil, originAddon, funcGuess, extra)
  entry.origin = extra.origin
  StoreEntry(entry)
  RDL:Log("WARN", "LUA_WARNING", "Lua warning captured", {})
end
