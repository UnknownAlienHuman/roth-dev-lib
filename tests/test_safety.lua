_G.RothDevLib = { Capture = {} }
local RDL = RothDevLib
local secret = {}
function _G.canaccessvalue(v) return v ~= secret end
function _G.issecretvalue(v) return v == secret end
function _G.canaccesstable(v) return v ~= secret end
function _G.issecrettable(v) return v == secret end
function _G.canaccessallvalues(...) return true end
function _G.debugstack() return secret end
function _G.time() return 1 end

local settings = { lockErrorHandler = true, importBugGrabber = true }
RDL.DB = { GetSettings = function() return settings end }
RDL.Log = function() end
RDL.Doctor = { Reset = function(self) self.reset = (self.reset or 0) + 1 end }
assert(loadfile('Util/SecretGuard.lua'))()
assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/BoundedCopy.lua'))()

local built
RDL.Capture.BuildEntry = function(...) built = { ... }; return { ok = true } end
RDL.Capture.StoreEntry = function(entry) assert(entry.ok); return 'stored' end
RDL.Capture._SetOwnershipState = function(self, state) self.state = state end
RDL.Capture.SyncOwnership = function(self) self.syncs = (self.syncs or 0) + 1 end
RDL.Capture.EnsureHandler = function(self) self._handler = self._handler or function() end end

local currentHandler = function() end
_G.geterrorhandler = function() return currentHandler end
local setCalls = 0
_G.seterrorhandler = function(handler) setCalls = setCalls + 1; currentHandler = handler end
RDL.Capture._real_seterrorhandler = _G.seterrorhandler

local addLuaCalls = 0
_G.AddLuaErrorHandler = function() addLuaCalls = addLuaCalls + 1 end
local bugEnabled, bugDisabled = 0, 0
RDL.Capture.BugGrabber = {
  IsPresent = function() return true end,
  Enable = function() bugEnabled = bugEnabled + 1; return true end,
  Disable = function() bugDisabled = bugDisabled + 1 end,
}
_G.C_AddOns = { IsAddOnLoaded = function() return false end }

assert(loadfile('Capture/Safety.lua'))()
RDL.Capture:ApplyHandlerLock()
assert(settings.lockErrorHandler == false)

RDL.Capture.ownsHandler = false
RDL.Capture:InstallFallbackHooks()
assert(addLuaCalls == 0)
assert(bugEnabled == 1)
assert(RDL.Capture._fallback.blizzardLuaHandlerUnsupported == true)

-- Automatic reclaim attempts only synchronize and attach fallback.
assert(RDL.Capture:TryReclaimHandler('watchdog') == false)
assert(setCalls == 0)
assert(RDL.Capture.syncs >= 1)

-- Explicit user reclaim may install one chain handler.
assert(RDL.Capture:TryReclaimHandler('slash') == true)
assert(setCalls == 1)
assert(RDL.Capture.ownsHandler == true)
assert(bugDisabled == 1)

-- Status probing is non-mutating.
local beforeProbeCalls = setCalls
local probe = RDL.Capture:ProbeSetErrorHandler()
assert(probe.skipped == true and probe.reason == 'non-mutating-policy')
assert(setCalls == beforeProbeCalls)

RDL.Capture:OnIntegrationEvent(secret, secret, secret, secret, { x = secret }, secret)
assert(built[1] == '<inaccessible>')
assert(built[2] == '[<inaccessible>] <inaccessible>: <inaccessible>')
assert(built[3] == '<inaccessible>')
assert(built[5] == '<inaccessible>')
assert(built[7].data.x == '<inaccessible>')

RDL.Capture:OnLuaError('boom', 'stack', true)
assert(RDL.Doctor.reset == 1)

print('capture safety tests: ok')
