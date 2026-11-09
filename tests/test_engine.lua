local currentHandler
local setCalls = 0
_G.geterrorhandler = function() return currentHandler end
_G.seterrorhandler = function(fn) setCalls = setCalls + 1; currentHandler = fn end
_G.hooksecurefunc = function() end
_G.time = function() return 100 end
_G.GetTime = function() return 10 end
_G.debugstack = function() return 'Interface/AddOns/Demo/Core.lua:7: in function <...>' end
_G.canaccessvalue = function() return true end
_G.issecretvalue = function() return false end
_G.canaccesstable = function() return true end
_G.issecrettable = function() return false end

local previousCalls = 0
currentHandler = function() previousCalls = previousCalls + 1 end

_G.RothDevLib = { name = 'RothDevLib', addonName = '!RothDevLib' }
local RDL = RothDevLib
RDL.DB = {
  sessionId = 1,
  session = {},
  EnsureReady = function() return true end,
  IsReady = function() return true end,
  GetSettings = function() return {
    errorHandlerMode = 'chain',
    chainCallPrevHandler = true,
    maintainOwnership = false,
    lockErrorHandler = false,
  } end,
  IsIgnored = function() return false end,
  UpsertGroup = function(_, entry) return { sig = entry.sig } end,
}
assert(loadfile('Util/Util.lua'))()
assert(loadfile('Capture/Engine.lua'))()
local Capture = assert(RDL.Capture)
assert(setCalls == 1)
assert(Capture.ownsHandler == true)
assert(Capture:ProbeSetErrorHandler().skipped == true)
assert(setCalls == 1) -- status inspection never swaps the process handler

currentHandler('boom')
assert(previousCalls == 1)
assert(RDL.DB.session.errors == 1)
assert(Capture._lastStoredSig ~= nil)

-- The installed process handler must contain intake failures even before the
-- richer Safety.lua owner has replaced the base implementation.
local originalOnLuaError = Capture.OnLuaError
Capture.OnLuaError = function(self)
  self._inHandler = true
  error('bootstrap intake failure')
end
local beforeBootstrapForward = previousCalls
assert(pcall(currentHandler, 'bootstrap-broken') == true)
assert(previousCalls == beforeBootstrapForward + 1)
assert(Capture._inHandler == false and Capture._inChainWrapper == false)
Capture.OnLuaError = originalOnLuaError

local replacement = function() end
currentHandler = replacement
Capture:SyncOwnership('external')
assert(Capture.ownsHandler == false)
assert(Capture.ownerInfo.state == 'replaced')
assert(Capture:TryReclaimHandler('watchdog') == false)
assert(currentHandler == replacement)
assert(setCalls == 1)

assert(Capture:TryReclaimHandler('slash') == true)
assert(currentHandler == Capture._handler)
assert(setCalls == 2)


-- Fallback diagnostics must reflect actual ChatTap installation state.
Capture.ChatTap = { _hooked = false, Init = function() return false end }
Capture:Init()
assert(Capture._fallback.chatTapHooked == false)
Capture.ChatTap = { _hooked = false, Init = function(self) self._hooked = true; return true end }
Capture:Init()
assert(Capture._fallback.chatTapHooked == true)

print('capture engine tests: ok')
