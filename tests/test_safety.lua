_G.RothDevLib = { Capture = {} }
local RDL = RothDevLib
local secret = {}
function _G.canaccessvalue(v) return v ~= secret end
function _G.issecretvalue(v) return v == secret end
function _G.canaccesstable(v) return v ~= secret end
function _G.issecrettable(v) return v == secret end
function _G.canaccessallvalues(...) return true end
function _G.debugstack() return secret end
local settings = { lockErrorHandler = true }
RDL.DB = { GetSettings = function() return settings end }
RDL.Log = function() end
assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/SecretGuard.lua'))()
local built
RDL.Capture.BuildEntry = function(...) built = { ... }; return { ok = true } end
RDL.Capture.StoreEntry = function(entry) assert(entry.ok) end
assert(loadfile('Capture/Safety.lua'))()
RDL.Capture:ApplyHandlerLock()
assert(settings.lockErrorHandler == false)
RDL.Capture:OnIntegrationEvent(secret, secret, secret, secret, { x = secret }, secret)
assert(built[1] == '<inaccessible>')
assert(built[2] == '[<inaccessible>] <inaccessible>: <inaccessible>')
assert(built[3] == '<inaccessible>')
assert(built[5] == '<inaccessible>')
assert(built[7].data.x == '<inaccessible>')
print('capture safety tests: ok')
