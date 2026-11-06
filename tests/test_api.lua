_G.RothDevLib = {}
local RDL = RothDevLib

local secret = setmetatable({}, {
  __tostring = function() error("secret tostring") end,
  __index = function() error("secret index") end,
  __pairs = function() error("secret pairs") end,
})
function _G.canaccessvalue(v) return v ~= secret end
function _G.issecretvalue(v) return v == secret end
function _G.canaccesstable(v) return v ~= secret end
function _G.issecrettable(v) return v == secret end
function _G.canaccessallvalues(...)
  for i = 1, select("#", ...) do if select(i, ...) == secret then return false end end
  return true
end

assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/BoundedCopy.lua'))()
assert(loadfile('Util/SecretGuard.lua'))()

local calls = {}
RDL.Bus = {
  RegisterAddon = function(_, ...) calls.register = { ... }; return true end,
  Breadcrumb = function(_, ...) calls.breadcrumb = { ... } end,
  Metric = function(_, ...) calls.metric = { ... } end,
  Alert = function(_, ...) calls.alert = { ... } end,
}
RDL.Capture = {
  OnIntegrationEvent = function(_, ...) calls.integration = { ... } end,
  OnReported = function(_, ...) calls.report = { ... } end,
}
function RDL:Fire(...) calls.fire = { ... } end
function RDL:SafeCall(...) return ... end
function RDL:SafeCallCtx(...) return ... end
function RDL:WrapSafe(_, _, fn) return fn end
function RDL:WrapSafeCtx(_, _, fn) return fn end
function RDL:WrapUnsafe(_, _, fn) return fn end

assert(loadfile('Integration/API.lua'))()

assert(RDL:InitAddon(secret) == nil)
assert(calls.register == nil)
assert(RDL:NewAddon(secret) == nil)

local payload = { n = 1, hidden = secret }
RDL:Breadcrumb('Test', secret, secret, payload)
payload.n = 2
assert(calls.breadcrumb[1] == 'Test')
assert(calls.breadcrumb[2] == '<inaccessible>')
assert(calls.breadcrumb[3] == '<inaccessible>')
assert(calls.breadcrumb[4].n == 1)
assert(calls.breadcrumb[4].hidden == '<inaccessible>')

RDL:Metric('Test', secret, secret, secret, { minInterval = 0 })
assert(calls.metric[2] == '<inaccessible>')
assert(calls.metric[3] == '<inaccessible>')
assert(calls.metric[4] == '<inaccessible>')
assert(calls.metric[5].minInterval == 0)

RDL:Alert('Test', secret, secret, { hidden = secret }, secret)
assert(calls.alert[2] == '<inaccessible>')
assert(calls.alert[3] == '<inaccessible>')
assert(calls.alert[4].hidden == '<inaccessible>')
assert(calls.integration[1] == 'ALERT')
assert(calls.fire[1] == 'RDL_INTEGRATION')

assert(RDL:Assert('Test', true, 'OK', 'ok') == true)
assert(RDL:Assert('Test', secret, secret, secret, secret) == false)
assert(calls.integration[1] == 'ASSERT')
assert(calls.integration[3] == '<inaccessible>')
assert(calls.integration[4] == '<inaccessible>')

RDL:Report('Test', secret, secret, { code = secret, data = { x = secret } })
assert(calls.report[1] == '<inaccessible>')
assert(calls.report[3] == '<inaccessible>')
assert(calls.report[4].code == '<inaccessible>')
assert(calls.report[4].data.x == '<inaccessible>')

RDL:Alert('Test', nil, nil, nil, nil)
assert(calls.alert[2] == 'ALERT')
assert(calls.alert[3] == '')
assert(calls.alert[5] == 'WARN')
assert(RDL:WrapProfiled('Test', 'bad', secret) == nil)
assert(RDL:WrapMemDelta('Test', 'bad', secret) == nil)

local poison = setmetatable({}, { __pairs = function() error("poison pairs") end })
RDL:Breadcrumb('Test', 'poison', 'payload', poison)
assert(type(calls.breadcrumb[4]) == 'table' and next(calls.breadcrumb[4]) == nil)

RDL.Bus.Breadcrumb = function() error('sink failure') end
local ok = pcall(RDL.Breadcrumb, RDL, 'Test', 'event', 'must not escape')
assert(ok == true)

RDL.Bus.Breadcrumb = function(_, ...) calls.breadcrumb = { ... } end
local client = assert(RDL:NewAddon('Client', { maxBreadcrumbs = 20 }))
client:Log(secret, secret, secret, { x = secret })
assert(calls.breadcrumb[1] == 'Client')
assert(calls.breadcrumb[2] == '<inaccessible>')

print('integration API tests: ok')
