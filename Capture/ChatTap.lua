-- !RothDevLib/Capture/ChatTap.lua
-- Optional, bounded parser for addon-printed Lua errors.

local RDL = _G.RothDevLib
local Capture = RDL and RDL.Capture
if not Capture then return end

local ChatTap = {
  _hooked = false,
  _active = nil,
  _timerToken = 0,
  _dedup = {},
  _hookedFrames = setmetatable({}, { __mode = "k" }),
}
Capture.ChatTap = ChatTap

local function Settings()
  if RDL.DB and type(RDL.DB.GetSettings) == "function" then
    local ok, value = pcall(RDL.DB.GetSettings, RDL.DB)
    if ok and type(value) == "table" then return value end
  end
  return {}
end

local function SafeText(value, maxBytes)
  local util = RDL.Util
  local text = ""
  if util and type(util.SafeToString) == "function" then
    local ok, valueText = pcall(util.SafeToString, util, value)
    if ok and type(valueText) == "string" then text = valueText end
  elseif type(value) == "string" then
    text = value
  end
  if util and type(util.FilterSecretEscapes) == "function" then
    local ok, filtered = pcall(util.FilterSecretEscapes, util, text)
    if ok and type(filtered) == "string" then text = filtered end
  end
  maxBytes = tonumber(maxBytes) or 32 * 1024
  if #text > maxBytes then text = text:sub(1, maxBytes) .. "<truncated>" end
  return text
end

local function NumberSetting(settings, key, fallback, minimum, maximum)
  local value = tonumber(settings[key]) or fallback
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function Now()
  if type(_G.GetTime) == "function" then
    local ok, value = pcall(_G.GetTime)
    if ok and type(value) == "number" then return value end
  end
  return type(_G.time) == "function" and _G.time() or 0
end

local function NormalizeLine(value)
  local text = SafeText(value, 32 * 1024)
  text = text:gsub("^%s*%[[%d:]+%]%s*", "")
    :gsub("^%s*%d%d:%d%d:%d%d%s*", "")
    :gsub("^%s*%d%d:%d%d%s*", "")
  return text
end

local function StripDecorations(text)
  local settings = Settings()
  if settings.chatTapStripColors ~= false then
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  end
  return text:gsub("|T[^|]*|t", ""):gsub("|H[^|]*|h([^|]*)|h", "%1")
end

local function IsStackLine(text)
  if text == "" then return false end
  return text:find("^%s*%[C%]:") ~= nil
    or text:find("^%s*%[tail call%]") ~= nil
    or text:find("^%s*%[?Interface/AddOns/") ~= nil
    or text:find("^%s*%[string ") ~= nil
end

local function ParseHeader(text)
  local clean = StripDecorations(text)
  local prefix, event, rest = clean:match(
    "^([^:]+):%s*[Ee][Rr][Rr][Oo][Rr]%[event:([%w_]+)%]%s*:%s*(.+)$")
  if prefix and rest then return { prefix = prefix, event = event, rest = rest } end

  prefix, event, rest = clean:match(
    "^([^:]+):%s*[Ee][Rr][Rr][Oo][Rr]%[([^%]]+)%]%s*:%s*(.+)$")
  if prefix and rest then return { prefix = prefix, event = event, rest = rest } end

  prefix, rest = clean:match("^([^:]+):%s*[Ee][Rr][Rr][Oo][Rr]%s*:%s*(.+)$")
  if prefix and rest then return { prefix = prefix, rest = rest } end

  rest = clean:match("^%s*%[?Interface/AddOns/[^:]+:%d+:%s*.+")
    or clean:match("^%s*[Ll]ua%s+[Ee]rror:%s*(.+)$")
  if rest then return { rest = rest } end
  return nil
end

local function GuessAddon(text)
  return text:match("Interface/AddOns/([^/]+)/")
end

local function IsRecentHardDuplicate(message, stack)
  local util, db = RDL.Util, RDL.DB
  if not (util and type(util.MakeSignature) == "function" and db and type(db.GetGroup) == "function") then
    return false
  end

  local now = type(_G.time) == "function" and _G.time() or 0
  local kinds = { "LUA_ERROR", "LUA_WARNING", "TAINT_BLOCKED", "TAINT_FORBIDDEN" }
  for i = 1, #kinds do
    local okSig, sig = pcall(util.MakeSignature, util, kinds[i], message, stack)
    if okSig and sig then
      local okGroup, group = pcall(db.GetGroup, db, sig)
      if okGroup and type(group) == "table" then
        local lastSeen = tonumber(group.lastSeen)
        if lastSeen and now - lastSeen <= 2 then return true end
      end
    end
  end
  return false
end

local function IsChatDuplicate(self, signature, settings)
  if type(signature) ~= "string" or signature == "" then return false end
  local window = NumberSetting(settings, "chatTapDedupSec", 0.6, 0, 60)
  if window == 0 then return false end

  local now = Now()
  local previous = self._dedup[signature]
  self._dedup[signature] = now
  if previous and now - previous < window then return true end

  local maximum = NumberSetting(settings, "chatTapDedupMax", 200, 20, 2000)
  local count = 0
  for _ in pairs(self._dedup) do count = count + 1 end
  if count > maximum then
    for key, timestamp in pairs(self._dedup) do
      if now - timestamp > window * 10 then self._dedup[key] = nil end
    end
  end
  return false
end

local function BumpSession(name)
  local session = RDL.DB and RDL.DB.session
  if type(session) == "table" then
    session[name] = (tonumber(session[name]) or 0) + 1
  end
end

local function Finalize(self)
  local active = self._active
  if not active then return end
  self._active = nil

  local message = SafeText(active.header, 32 * 1024)
  local stack = table.concat(active.stackLines or {}, "\n")
  if stack == "" and active.parsed and active.parsed.rest then
    local frame = active.parsed.rest:match("(Interface/AddOns/[^\n]+)")
    if frame then stack = frame end
  end
  stack = SafeText(stack, 128 * 1024)

  local settings = Settings()
  local util = RDL.Util
  local signature
  if util and type(util.MakeSignature) == "function" then
    local ok, value = pcall(util.MakeSignature, util, "SUPPRESSED", message, stack)
    if ok then signature = value end
  end

  if IsChatDuplicate(self, signature, settings) then
    BumpSession("chatTapDeduped")
    return
  end
  if IsRecentHardDuplicate(message, stack) then
    BumpSession("chatTapMerged")
    return
  end

  local parsed = active.parsed or {}
  local addonName = GuessAddon(stack) or GuessAddon(message) or parsed.prefix or "<?>"
  local funcName = parsed.event and ("event:" .. parsed.event) or "<?>"
  local topLine = stack:match("(Interface/AddOns/[^\n]+)")

  if type(Capture.OnSuppressedError) == "function" then
    local ok, entry = pcall(Capture.OnSuppressedError, Capture, message, stack, nil, addonName, funcName, {
      source = "chat",
      prefix = parsed.prefix,
      event = parsed.event,
      topLine = topLine,
      signature = signature,
    })
    if ok and entry then
      BumpSession("chatTapCaptured")
      if type(RDL.Log) == "function" then
        pcall(RDL.Log, RDL, "WARN", "CHAT", "Captured suppressed error from chat", {
          addon = addonName,
          func = funcName,
        })
      end
    end
  end
end

local function ArmFinalizeTimer(self, settings)
  local timer = _G.C_Timer
  if type(timer) ~= "table" or type(timer.After) ~= "function" then return end

  local window = NumberSetting(settings, "chatTapWindowSec", 0.8, 0.1, 10)
  self._timerToken = self._timerToken + 1
  local token = self._timerToken
  timer.After(window, function()
    if token ~= self._timerToken or not self._active then return end
    if Now() - (self._active.lastTs or 0) >= window then Finalize(self) end
  end)
end

function ChatTap:OnChatMessage(value)
  local settings = Settings()
  if settings.captureChatErrors ~= true then return end

  local message = NormalizeLine(value)
  if message == "" or message:find("RothDevLib", 1, true) then return end

  local active = self._active
  if not active and not message:lower():find("error", 1, true) then return end

  -- Once a capture is active, addon-frame lines are continuation data, not
  -- fresh generic headers. This prevents a stack line from replacing the real
  -- error header before Finalize().
  if active and IsStackLine(message) then
    local maximum = NumberSetting(settings, "chatTapMaxStackLines", 60, 1, 200)
    if #active.stackLines >= maximum then
      Finalize(self)
      return
    end
    active.stackLines[#active.stackLines + 1] = message
    active.lastTs = Now()
    ArmFinalizeTimer(self, settings)
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
    ArmFinalizeTimer(self, settings)
    return
  end

  if active then Finalize(self) end
end

function ChatTap:Init()
  if self._hooked then return end
  self._hooked = true

  local function HookFrame(frame)
    if type(frame) ~= "table" and type(frame) ~= "userdata" then return false end
    if self._hookedFrames[frame] then return true end
    if type(frame.AddMessage) ~= "function" or type(_G.hooksecurefunc) ~= "function" then return false end

    local ok = pcall(_G.hooksecurefunc, frame, "AddMessage", function(_, message)
      pcall(ChatTap.OnChatMessage, ChatTap, message)
    end)
    if ok then self._hookedFrames[frame] = true end
    return ok
  end

  local hooked = HookFrame(_G.DEFAULT_CHAT_FRAME)
  if _G.ChatFrame1 ~= _G.DEFAULT_CHAT_FRAME then
    hooked = HookFrame(_G.ChatFrame1) or hooked
  end

  local settings = Settings()
  if settings.chatTapHookAllFrames ~= false then
    local count = NumberSetting(_G, "NUM_CHAT_WINDOWS", 10, 1, 50)
    for i = 1, count do hooked = HookFrame(_G["ChatFrame" .. i]) or hooked end

    if type(_G.FloatingChatFrame_OnLoad) == "function" and type(_G.hooksecurefunc) == "function" then
      pcall(_G.hooksecurefunc, "FloatingChatFrame_OnLoad", function(frame)
        HookFrame(frame)
      end)
    end
  end

  if type(RDL.Log) == "function" then
    pcall(RDL.Log, RDL, hooked and "INFO" or "WARN", "CHAT", "ChatTap init", { hooked = hooked })
  end
end
