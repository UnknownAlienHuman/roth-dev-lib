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
_G.C_Timer = { After = function() end }

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
}
RDL.DB = {
  GetSettings = function() return settings end,
  session = {},
}
RDL.Log = function() end
assert(loadfile('Util/Util.lua'))()

local captured
RDL.Capture.OnSuppressedError = function(_, message, stack, locals, addon, func, extra)
  captured = {
    message = message,
    stack = stack,
    addon = addon,
    func = func,
    extra = extra,
  }
  return captured
end

assert(loadfile('Capture/ChatTap.lua'))()
local tap = assert(RDL.Capture.ChatTap)
assert(pcall(tap.OnChatMessage, tap, secret))
assert(captured == nil)

tap:OnChatMessage('Demo: error[event:PLAYER_LOGIN]: Interface/AddOns/Demo/Core.lua:7: boom')
tap:OnChatMessage('Interface/AddOns/Demo/Core.lua:7: in function <Core.lua:1>')
tap:OnChatMessage('done')
assert(captured)
assert(captured.message:find('Demo: error', 1, true))
assert(captured.stack:find('Interface/AddOns/Demo/Core.lua:7', 1, true))
assert(captured.addon == 'Demo')
assert(captured.func == 'event:PLAYER_LOGIN')
assert(captured.extra.source == 'chat')
assert(RDL.DB.session.chatTapCaptured == 1)

tap:Init()
assert(hooks[frame])
assert(frame.__RDL_ChatTapHooked == nil)
assert(pcall(hooks[frame], frame, secret))

print('chat tap tests: ok')
