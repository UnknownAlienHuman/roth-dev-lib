-- !RothDevLib/Capture/ChatTap.lua
-- Optional bounded heuristic for addon-printed error stacks in local chat.

local RDL = _G.RothDevLib
local Capture = RDL and RDL.Capture
if not Capture then return end

local ChatTap = {
  _hooked = false,
  _dynamicHooked = false,
  _active = nil,
  _timerToken = 0,
  _dedup = {},
  _hookedFrames = setmetatable({}, { __mode = "k" }),
}
Capture.ChatTap = ChatTap

local ACCEPTED_STATUS = { stored = true, queued = true, ignored = true }

local function Settings()
  if RDL.DB and type(RDL.DB.GetSettings) == "function" then
    local ok, value = pcall(RDL.DB.GetSettings, RDL.DB)
    if ok and type(value) == "table" then return value end
  end
  return {}
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
  maximum = tonumber(maximum) or 32 * 1024
  if #text > maximum then text = text:sub(1, maximum) .. "<truncated>" end
  return text
end

local function SafeCopy(value)
  local util = RDL.Util
  if util and type(util.CopyDiagnosticValue) == "function" then
    local ok, copy = pcall(util.CopyDiagnosticValue, util, value, {
      maxDepth = 3,
      maxEntries = 40,
      maxNodes = 200,
      maxStringBytes = 4096,
    })
    if ok then return copy end
  end
  return nil
end

local function Now()
  if type(_G.GetTime) == "function" then
    local ok, value = pcall(_G.GetTime)
    if ok and type(value) == "number" then return value end
  end
  return type(_G.time) == "function" and _G.time() or 0
end

local function StripTimestamp(message)
  return message
    :gsub("^%s*%[[%d:]+%]%s*", "")
    :gsub("^%s*%d%d:%d%d:%d%d%s*", "")
    :gsub("^%s*%d%d:%d%d%s*", "")
end

local function StripDecorations(message)
  local settings = Settings()
  if settings.chatTapStripColors ~= false then
    message = message:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  end
  return message
    :gsub("|T[^|]*|t", "")
    :gsub("|H[^|]*|h([^|]*)|h", "%1")
end

local function IsStackLine(message)
  return message:find("^%s*%[C%]:") ~= nil
    or message:find("^%s*%[tail call%]") ~= nil
    or message:find("^%s*%[Interface/AddOns/") ~= nil
    or message:find("^%s*Interface/AddOns/") ~= nil
    or message:find("^%s*%[string ") ~= nil
end

local function ParseHeader(message)
  local cleaned = StripTimestamp(StripDecorations(message))
  local prefix, eventName, rest = cleaned:match(
    "^([^:]+):%s*[Ee][Rr][Rr][Oo][Rr]%[event:([%w_]+)%]%s*:%s*(.+)$")
  if prefix and rest then return { prefix = prefix, event = eventName, rest = rest } end

  local tag
  prefix, tag, rest = cleaned:match(
    "^([^:]+):%s*[Ee][Rr][Rr][Oo][Rr]%[([^%]]+)%]%s*:%s*(.+)$")
  if prefix and rest then return { prefix = prefix, event = tag, rest = rest } end

  prefix, rest = cleaned:match("^([^:]+):%s*[Ee][Rr][Rr][Oo][Rr]%s*:%s*(.+)$")
  if prefix and rest then return { prefix = prefix, rest = rest } end

  rest = cleaned:match("^%s*%[?Interface/AddOns/[^:]+:%d+:%s*.+")
  if rest then return { rest = rest } end

  rest = cleaned:match("^%s*[Ll]ua%s+[Ee]rror:%s*(.+)$")
  if rest then return { rest = rest } end
  return nil
end

local function GuessAddon(text)
  return type(text) == "string" and text:match("Interface/AddOns/([^/]+)/") or nil
end

local function TopAddonLine(stack)
  return type(stack) == "string" and stack:match("(Interface/AddOns/[^\n]+)") or nil
end

local function RecentlyCaptured(message, stack)
  local util = RDL.Util
  local db = RDL.DB
  if not (util and type(util.MakeSignature) == "function" and db and type(db.GetGroup) == "function") then
    return false
  end

  local kinds = { "LUA_ERROR", "LUA_WARNING", "TAINT_BLOCKED", "TAINT_FORBIDDEN" }
  for index = 1, #kinds do
    local okSig, signature = pcall(util.MakeSignature, util, kinds[index], message, stack)
    if okSig then
      local okGroup, group = pcall(db.GetGroup, db, signature)
      if okGroup and type(group) == "table" and type(group.lastSeen) == "number"
          and (type(_G.time) == "function" and _G.time() or 0) - group.lastSeen <= 2 then
        return true
      end
    end
  end
  return false
end

local function DedupHit(self, signature)
  local settings = Settings()
  local window = tonumber(settings.chatTapDedupSec) or 0.6
  if window <= 0 then return false end

  local now = Now()
  local previous = self._dedup[signature]
  self._dedup[signature] = now
  if previous and now - previous < window then return true end

  local maximum = tonumber(settings.chatTapDedupMax) or 200
  local count = 0
  for _ in pairs(self._dedup) do count = count + 1 end
  if count > maximum then
    for key, timestamp in pairs(self._dedup) do
      if now - timestamp > window * 10 then self._dedup[key] = nil end
    end
  end
  return false
end

local function Finalize(self)
  local active = self._active
  self._active = nil
  if not active or Settings().captureChatErrors ~= true then return nil end

  local message = SafeText(active.header, "", 32 * 1024)
  local stack = active.stackLines and table.concat(active.stackLines, "\n") or ""
  if (stack == "" or not stack:find("Interface/AddOns/", 1, true))
      and active.parsed and active.parsed.rest then
    local line = active.parsed.rest:match("(Interface/AddOns/[^\n]+)")
    if line then stack = line .. (stack ~= "" and ("\n" .. stack) or "") end
  end
  stack = SafeText(stack, "", 128 * 1024)

  local addonName = GuessAddon(stack) or GuessAddon(message)
    or (active.parsed and active.parsed.prefix) or "<?>"
  local funcName = active.parsed and active.parsed.event
    and ("event:" .. SafeText(active.parsed.event, "<?>" , 128)) or "<?>"
  local extra = {
    source = "chat",
    prefix = active.parsed and active.parsed.prefix or nil,
    event = active.parsed and active.parsed.event or nil,
    topLine = TopAddonLine(stack),
  }

  local util = RDL.Util
  local signature
  if util and type(util.MakeSignature) == "function" then
    local ok, value = pcall(util.MakeSignature, util, "SUPPRESSED", message, stack)
    if ok then signature = SafeText(value, "", 4096) end
  end
  if signature and DedupHit(self, signature) then
    if RDL.DB and RDL.DB.session then
      RDL.DB.session.chatTapDeduped = (tonumber(RDL.DB.session.chatTapDeduped) or 0) + 1
    end
    return nil
  end
  if RecentlyCaptured(message, stack) then
    if RDL.DB and RDL.DB.session then
      RDL.DB.session.chatTapMerged = (tonumber(RDL.DB.session.chatTapMerged) or 0) + 1
    end
    return nil
  end

  if type(Capture.BuildEntry) ~= "function" or type(Capture.StoreEntry) ~= "function" then return nil end
  local okBuild, entry = pcall(Capture.BuildEntry, "SUPPRESSED", message, stack, nil,
    addonName, funcName, SafeCopy(extra))
  if not okBuild or type(entry) ~= "table" then return nil end
  local okStore, status = pcall(Capture.StoreEntry, entry)
  if not okStore or not ACCEPTED_STATUS[status] then return nil end

  if status == "stored" or status == "queued" then
    if RDL.DB and RDL.DB.session then
      RDL.DB.session.chatTapCaptured = (tonumber(RDL.DB.session.chatTapCaptured) or 0) + 1
    end
    if type(RDL.Log) == "function" then
      pcall(RDL.Log, RDL, "WARN", "CHAT", "Captured suppressed error from chat", {
        addon = addonName,
        func = funcName,
      })
    end
  end
  return entry, status
end

local function ArmFinalizeTimer(self)
  local timer = _G.C_Timer
  if type(timer) ~= "table" or type(timer.After) ~= "function" then return end
  local window = tonumber(Settings().chatTapWindowSec) or 0.8
  if window < 0.05 then window = 0.05 elseif window > 10 then window = 10 end

  self._timerToken = self._timerToken + 1
  local token = self._timerToken
  timer.After(window, function()
    if token ~= ChatTap._timerToken then return end
    if Settings().captureChatErrors ~= true then
      ChatTap._active = nil
      return
    end
    local active = ChatTap._active
    if active and Now() - (active.lastTs or 0) >= window then Finalize(ChatTap) end
  end)
end

function ChatTap:OnChatMessage(rawMessage)
  if Settings().captureChatErrors ~= true then
    self._active = nil
    self._timerToken = self._timerToken + 1
    return
  end

  local message = StripTimestamp(SafeText(rawMessage, "", 32 * 1024))
  if message == "" or message == "<inaccessible>" or message == "<secret>" then return end
  if message:find("RothDevLib", 1, true) then return end

  local active = self._active
  if not active and not message:lower():find("error", 1, true) then return end

  -- Once a capture is active, addon-frame lines are continuation data, not
  -- fresh generic headers. Check this before ParseHeader(), because a stack
  -- line also matches the generic Interface/AddOns header shape.
  if active and IsStackLine(message) then
    local maximum = tonumber(Settings().chatTapMaxStackLines) or 60
    if maximum < 1 then maximum = 1 elseif maximum > 200 then maximum = 200 end
    if #active.stackLines >= maximum then
      Finalize(self)
      return
    end
    active.stackLines[#active.stackLines + 1] = message
    active.lastTs = Now()
    ArmFinalizeTimer(self)
    return
  end

  local parsed = ParseHeader(message)
  if parsed then
    if active then Finalize(self) end
    self._active = {
      header = message,
      parsed = parsed,
      stackLines = {},
      lastTs = Now(),
    }
    ArmFinalizeTimer(self)
    return
  end

  if active then Finalize(self) end
end

local function HookFrame(frame)
  if not frame or ChatTap._hookedFrames[frame] then return false end
  if type(frame.AddMessage) ~= "function" or type(_G.hooksecurefunc) ~= "function" then return false end
  local ok = pcall(_G.hooksecurefunc, frame, "AddMessage", function(_, message)
    pcall(ChatTap.OnChatMessage, ChatTap, message)
  end)
  if ok then ChatTap._hookedFrames[frame] = true end
  return ok
end

function ChatTap:Init()
  local hooked = false
  hooked = HookFrame(_G.DEFAULT_CHAT_FRAME) or hooked
  hooked = HookFrame(_G.ChatFrame1) or hooked

  if Settings().chatTapHookAllFrames ~= false then
    local count = tonumber(_G.NUM_CHAT_WINDOWS) or 10
    if count < 1 then count = 1 elseif count > 50 then count = 50 end
    for index = 1, count do hooked = HookFrame(_G["ChatFrame" .. index]) or hooked end

    if not self._dynamicHooked and type(_G.FloatingChatFrame_OnLoad) == "function"
        and type(_G.hooksecurefunc) == "function" then
      local ok = pcall(_G.hooksecurefunc, "FloatingChatFrame_OnLoad", function(frame)
        pcall(HookFrame, frame)
      end)
      self._dynamicHooked = ok == true
    end
  end

  self._hooked = hooked or self._dynamicHooked
  if type(RDL.Log) == "function" then
    pcall(RDL.Log, RDL, self._hooked and "INFO" or "WARN", "CHAT", "ChatTap init", {
      hooked = self._hooked,
    })
  end
  return self._hooked
end
