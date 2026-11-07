local secret = setmetatable({}, {
  __tostring = function() error('secret tostring') end,
  __index = function() error('secret index') end,
})
function _G.canaccessvalue(v) return v ~= secret end
function _G.issecretvalue(v) return v == secret end
function _G.canaccesstable(v) return v ~= secret end
function _G.issecrettable(v) return v == secret end
function _G.canaccessallvalues(...) return true end

local now = 10
function _G.time() return math.floor(now) end
function _G.GetTime() return now end
local timers = {}
_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }

local hooks = {}
function _G.hooksecurefunc(target, method, callback)
  if type(target) == 'table' then
    hooks[target] = callback
  else
    hooks[target .. ':' .. tostring(method)] = callback
  end
end

local frame = { AddMessage = function() end }
_G.DEFAULT_CHAT_FRAME = frame
_G.ChatFrame1 = frame
_G.NUM_CHAT_WINDOWS = 1
_G.RothDevLib = { Capture = {}, UI = {} }
local RDL = RothDevLib
local settings = {
  captureChatErrors = true,
  chatTapHookAllFrames = false,
  chatTapWindowSec = 1,
  chatTapDedupSec = 0.6,
  chatTapDedupMax = 10,
}
RDL.DB = {
  GetSettings = function() return settings end,
  session = {},
}
RDL.Log = function() end
assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/BoundedCopy.lua'))()

local captured
RDL.Capture.BuildEntry = function(kind, message, stack, locals, addon, func, extra)
  captured = {
    kind = kind,
    message = message,
    stack = stack,
    addon = addon,
    func = func,
    extra = extra,
  }
  return captured
end
RDL.Capture.StoreEntry = function() return 'stored' end

assert(loadfile('Capture/ChatTap.lua'))()
local tap = assert(RDL.Capture.ChatTap)
assert(pcall(tap.OnChatMessage, tap, secret))
assert(captured == nil)

tap:OnChatMessage('Demo: error[event:PLAYER_LOGIN]: Interface/AddOns/Demo/Core.lua:7: boom')
tap:OnChatMessage('Interface/AddOns/Demo/Core.lua:7: in function <Core.lua:1>')
tap:OnChatMessage('done')
assert(captured)
assert(captured.kind == 'SUPPRESSED')
assert(captured.message:find('Demo: error', 1, true))
assert(captured.stack:find('Interface/AddOns/Demo/Core.lua:7', 1, true))
assert(captured.addon == 'Demo')
assert(captured.func == 'event:PLAYER_LOGIN')
assert(captured.extra.source == 'chat')
assert(RDL.DB.session.chatTapCaptured == 1)

-- Unique bursts must keep the dedup cache within its configured hard cap even
-- when every timestamp is recent and stale pruning removes nothing.
for index = 1, 25 do
  tap:OnChatMessage('Demo: error: Interface/AddOns/Demo/Core.lua:' .. index .. ': unique-' .. index)
  tap:OnChatMessage('done')
end
local dedupCount = 0
for _ in pairs(tap._dedup) do dedupCount = dedupCount + 1 end
assert(dedupCount <= settings.chatTapDedupMax)

tap:Init()
assert(hooks[frame])
assert(frame.__RDL_ChatTapHooked == nil)
assert(pcall(hooks[frame], frame, secret))

-- A pending timer must discard capture when the setting is disabled.
captured = nil
settings.captureChatErrors = true
tap:OnChatMessage('Demo: error: Interface/AddOns/Demo/Core.lua:9: later')
assert(#timers > 0)
settings.captureChatErrors = false
now = now + 2
timers[#timers]()
assert(captured == nil and tap._active == nil)

print('chat tap tests: ok')
