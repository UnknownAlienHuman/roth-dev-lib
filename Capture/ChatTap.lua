-- !RothDevLib/Capture/ChatTap.lua
-- Optional "chat tap" that parses addon-printed error stacks from chat.
-- Motivation: some addons wrap errors in xpcall and only print to chat (no Blizzard error UI).
-- This module attempts to reconstruct a suppressed-error entry from those chat lines.
--
-- Design constraints:
--   - Low overhead: fast pre-filter; only parses when it sees an error header or is in an active capture window.
--   - No overrides: uses hooksecurefunc on AddMessage.
--   - Best-effort: patterns vary by addon; this is a heuristic.

local RDL = _G.RothDevLib
local Capture = RDL.Capture
if not Capture then return end

local ChatTap = {}
Capture.ChatTap = ChatTap

ChatTap._hooked = false
ChatTap._active = nil
ChatTap._timerToken = 0

local function Settings()
  return (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or {}
end

local function StripTimestamp(msg)
  -- Chat timestamps vary by user settings/addons.
  -- Strip several common leading formats so stack-line detection still works:
  --   "[HH:MM:SS] ..." / "[HH:MM] ..." / "[1:02:03] ..."
  --   "HH:MM:SS ..." / "HH:MM ..."
  local s = tostring(msg or "")
  s = s:gsub("^%s*%[[%d:]+%]%s*", "")
  s = s:gsub("^%s*%d%d:%d%d:%d%d%s*", "")
  s = s:gsub("^%s*%d%d:%d%d%s*", "")
  return s
end

local function StripDecorations(msg)
  -- Parsing should not be fooled by color/texture/link markup.
  -- Keep this conservative: we only remove markup patterns; content remains.
  msg = tostring(msg or "")
  local s = Settings()
  if s.chatTapStripColors ~= false then
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x", "")
    msg = msg:gsub("|r", "")
  end
  -- textures: |T...|t
  msg = msg:gsub("|T[^|]*|t", "")
  -- links: keep visible text |H...|hTEXT|h
  msg = msg:gsub("|H[^|]*|h([^|]*)|h", "%1")
  return msg
end

local function IsStackLine(msg)
  if not msg or msg == "" then return false end
  -- Allow both bracketed and unbracketed stack formats.
  if msg:find("^%s*%[C%]:") then return true end
  if msg:find("^%s*%[tail call%]" ) then return true end
  if msg:find("^%s*%[Interface/AddOns/") then return true end
  if msg:find("^%s*Interface/AddOns/") then return true end
  if msg:find("^%s*%[string ") then return true end
  if msg:find("^%s*Interface/AddOns/[^:]+:%d+:") then return true end
  -- Some addons print without brackets for their own frames; keep conservative.
  return false
end

local function ParseHeader(msg)
  -- Patterns to capture:
  --   "RDM: error[event:PLAYER_ENTERING_WORLD]: <file>:<line>: <message>"
  --   "|cff...RDM|r: error[event:...] ..." (colored prefix)
  --   "AddonName: error: <...>" (fallback)
  local cleaned = StripDecorations(msg)

  -- Strip chat timestamps like "[01:01:16] " to avoid confusing ":"-based prefix parsing.
  cleaned = cleaned:gsub("^%s*%[[%d:]+%]%s*", "")
  cleaned = cleaned:gsub("^%s*%d%d:%d%d:%d%d%s*", "")

  -- Allow case variations: "error" / "Error" / "ERROR"
  local prefix, event, rest = cleaned:match("^([^:]+):%s*[Ee][Rr][Rr][Oo][Rr]%[event:([%w_]+)%]%s*:%s*(.+)$")
  if prefix and rest then
    return true, { prefix = prefix, event = event, rest = rest }
  end

  -- Generic bracketed tag: error[Something]: ...
  local tag
  prefix, tag, rest = cleaned:match("^([^:]+):%s*[Ee][Rr][Rr][Oo][Rr]%[([^%]]+)%]%s*:%s*(.+)$")
  if prefix and rest then
    return true, { prefix = prefix, event = tag, rest = rest }
  end

  prefix, rest = cleaned:match("^([^:]+):%s*[Ee][Rr][Rr][Oo][Rr]%s*:%s*(.+)$")
  if prefix and rest then
    return true, { prefix = prefix, event = nil, rest = rest }
  end

  -- Some addons print just a file:line:error (no prefix)
  rest = cleaned:match("^%s*%[?Interface/AddOns/[^:]+:%d+:%s*.+")
  if rest then
    return true, { prefix = nil, event = nil, rest = rest }
  end

  -- Generic "Lua error:" style
  rest = cleaned:match("^%s*[Ll]ua%s+[Ee]rror:%s*(.+)$")
  if rest then
    return true, { prefix = nil, event = nil, rest = rest }
  end

  return false, nil
end

local function GuessAddonFromText(text)
  if not text or text == "" then return nil end
  return text:match("Interface/AddOns/([^/]+)/")
end

local function TopAddonFrameLine(stack)
  if not stack or stack == "" then return nil end
  -- First line containing an addon file reference.
  local line = stack:match("(Interface/AddOns/[^\n]+)")
  return line
end

local function IsDuplicateSuppressed(kind, msg, stack)
  local U = RDL.Util
  local db = RDL.DB
  if not (U and db and db.GetGroup) then return false end

  -- If the same error was already captured as a hard LUA_ERROR (or warning/taint) very recently,
  -- avoid creating a separate SUPPRESSED group from chat-printing.
  local candidates = { "LUA_ERROR", "LUA_WARNING", "TAINT_BLOCKED", "TAINT_FORBIDDEN" }
  for _, k in ipairs(candidates) do
    local sig = U:MakeSignature(k, msg, stack)
    local g = db:GetGroup(sig)
    if g and g.lastSeen and (time() - (g.lastSeen or 0)) <= 2 then
      return true
    end
  end
  return false
end

local function DedupWindowHit(self, sig)
  local s = Settings()
  local window = tonumber(s.chatTapDedupSec) or 0.6
  if window <= 0 then return false end
  self._dedup = self._dedup or {}
  local now = (GetTime and GetTime()) or time()
  local last = self._dedup[sig]
  if last and (now - last) < window then
    self._dedup[sig] = now
    return true
  end
  self._dedup[sig] = now

  -- Opportunistic prune.
  local max = tonumber(s.chatTapDedupMax) or 200
  local n = 0
  for _ in pairs(self._dedup) do n = n + 1 end
  if n > max then
    for k, ts in pairs(self._dedup) do
      if (now - ts) > (window * 10) then self._dedup[k] = nil end
    end
  end
  return false
end

local function Finalize(self)
  local a = self._active
  if not a then return end
  self._active = nil

  local U = RDL.Util
  local msg = a.header or ""
  local stack = (a.stackLines and #a.stackLines > 0) and table.concat(a.stackLines, "\n") or ""

  -- Ensure we keep at least the most useful line even if stack formatting was odd.
  if (stack == "" or not stack:find("Interface/AddOns/")) and a.parsed and a.parsed.rest then
    local restAddonLine = a.parsed.rest:match("(Interface/AddOns/[^\n]+)")
    if restAddonLine then
      stack = restAddonLine .. (stack ~= "" and ("\n" .. stack) or "")
    end
  end

  -- Scrub secrets in both message and stack.
  if U and U.Scrub then
    msg = U:Scrub(msg)
    stack = U:Scrub(stack)
  end

  local addonName = GuessAddonFromText(stack) or GuessAddonFromText(msg) or (a.parsed and a.parsed.prefix) or "<?>"
  local funcName = (a.parsed and a.parsed.event) and ("event:" .. tostring(a.parsed.event)) or "<?>"

  local extra = {
    source = "chat",
    prefix = a.parsed and a.parsed.prefix or nil,
    event = a.parsed and a.parsed.event or nil,
    topLine = TopAddonFrameLine(stack),
  }

  -- Dedup policy:
  --   (1) if this chat-printed stack matches a recently captured hard error, skip
  --   (2) collapse duplicates of identical chat stacks within a small time window
  local kind = "SUPPRESSED"
  local sig = (U and U.MakeSignature) and U:MakeSignature(kind, msg, stack) or nil
  if sig and DedupWindowHit(self, sig) then
    if RDL.DB and RDL.DB.session then
      RDL.DB.session.chatTapDeduped = (RDL.DB.session.chatTapDeduped or 0) + 1
    end
    return
  end
  if IsDuplicateSuppressed(kind, msg, stack) then
    if RDL.DB and RDL.DB.session then
      RDL.DB.session.chatTapMerged = (RDL.DB.session.chatTapMerged or 0) + 1
    end
    return
  end

  -- Represent as SUPPRESSED: this is an error that did not reach the global Lua error handler.
  local entry = Capture.BuildEntry(kind, msg, stack, nil, addonName, funcName, extra)
  Capture.StoreEntry(entry)

  if RDL.DB and RDL.DB.session then
    RDL.DB.session.chatTapCaptured = (RDL.DB.session.chatTapCaptured or 0) + 1
  end

  if RDL and RDL.Log then
    pcall(function()
      RDL:Log("WARN", "CHAT", "Captured suppressed error from chat", { addon = addonName, func = funcName })
    end)
  end
end

local function ArmFinalizeTimer(self)
  if not C_Timer or not C_Timer.After then return end
  local s = Settings()
  local window = tonumber(s.chatTapWindowSec) or 0.8

  self._timerToken = (self._timerToken or 0) + 1
  local token = self._timerToken

  C_Timer.After(window, function()
    if token ~= self._timerToken then return end
    local a = self._active
    if not a then return end

    local now = (GetTime and GetTime()) or time()
    local last = a.lastTs or now
    if (now - last) >= window then
      Finalize(self)
    end
  end)
end

function ChatTap:OnChatMessage(msg)
  local s = Settings()
  if not s.captureChatErrors then return end

  msg = StripTimestamp(msg)

  -- Avoid self-noise.
  if msg:find("RothDevLib", 1, true) then return end

  local active = self._active

  -- Fast pre-filter: only do work if this looks like an error header OR we are already capturing.
  if not active then
    if (not msg:find("error", 1, true)) and (not msg:find("Error", 1, true)) then
      return
    end
  end

  local isHeader, parsed = ParseHeader(msg)
  if isHeader then
    if self._active then
      Finalize(self)
    end
    self._active = {
      header = msg,
      parsed = parsed,
      stackLines = {},
      lastTs = (GetTime and GetTime()) or time(),
    }
    ArmFinalizeTimer(self)
    return
  end

  if active and IsStackLine(msg) then
    local maxLines = tonumber(s.chatTapMaxStackLines) or 60
    if #active.stackLines < maxLines then
      active.stackLines[#active.stackLines + 1] = msg
    else
      -- Hit cap: finalize early to avoid unbounded memory/cpu.
      Finalize(self)
      return
    end
    active.lastTs = (GetTime and GetTime()) or time()
    ArmFinalizeTimer(self)
    return
  end

  -- If we were capturing and got a non-stack, non-header line, finalize.
  if active then
    Finalize(self)
  end
end

function ChatTap:Init()
  if self._hooked then return end
  self._hooked = true

  local function HookFrame(frame)
    if not frame or frame.__RDL_ChatTapHooked then return false end
    if type(frame.AddMessage) ~= "function" or type(hooksecurefunc) ~= "function" then return false end
    frame.__RDL_ChatTapHooked = true
    hooksecurefunc(frame, "AddMessage", function(_, msg)
      pcall(function() ChatTap:OnChatMessage(msg) end)
    end)
    return true
  end

  local ok = false
  -- Always hook DEFAULT_CHAT_FRAME and ChatFrame1.
  ok = HookFrame(_G.DEFAULT_CHAT_FRAME) or ok
  ok = HookFrame(_G.ChatFrame1) or ok

  -- Optionally hook all chat windows (covers addons that print to non-primary frames).
  local s = Settings()
  if s.chatTapHookAllFrames ~= false then
    local n = tonumber(_G.NUM_CHAT_WINDOWS) or 10
    for i = 1, n do
      ok = HookFrame(_G["ChatFrame" .. i]) or ok
    end
    -- Catch dynamically created chat frames.
    if type(_G.FloatingChatFrame_OnLoad) == "function" then
      hooksecurefunc("FloatingChatFrame_OnLoad", function(frame)
        pcall(function() HookFrame(frame) end)
      end)
    end
  end

  if RDL and RDL.Log then
    pcall(function()
      RDL:Log(ok and "INFO" or "WARN", "CHAT", "ChatTap init", { hooked = ok })
    end)
  end
end
