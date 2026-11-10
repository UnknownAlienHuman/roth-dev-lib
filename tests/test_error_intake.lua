local secret = setmetatable({}, {
  __tostring = function() error('secret tostring') end,
  __index = function() error('secret index') end,
  __len = function() error('secret len') end,
})

function _G.canaccessvalue(v) return v ~= secret end
function _G.issecretvalue(v) return v == secret end
function _G.canaccesstable(v) return v ~= secret end
function _G.issecrettable(v) return v == secret end
function _G.canaccessallvalues(...)
  for i = 1, select('#', ...) do
    if select(i, ...) == secret then return false end
  end
  return true
end
function _G.time() return 100 end
function _G.debugstack() return secret end
function _G.UnitAffectingCombat() return false end

local realSetter = function() end
_G.seterrorhandler = function() error('locked setter') end
_G.RothDevLib = { Capture = {}, UI = {} }
local RDL = RothDevLib
local Capture = RDL.Capture

local settings = {
  lockErrorHandler = true,
  chatNotifyOnError = false,
  forwardToDefaultErrorHandler = true,
}
RDL.DB = { GetSettings = function() return settings end }
RDL.Log = function() end
RDL.Doctor = {
  Reset = function(self) self.reset = true end,
}

assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/SecretGuard.lua'))()

local built = {}
Capture.BuildEntry = function(kind, message, stack, locals, addonName, funcName, extra)
  local entry = {
    kind = kind,
    message = message,
    stack = stack,
    locals = locals,
    addon = addonName or 'guessed',
    func = funcName or 'guessed',
    extra = extra,
  }
  built[#built + 1] = entry
  return entry
end
Capture.StoreEntry = function(entry)
  assert(type(entry) == 'table')
  return 'stored'
end
Capture.CaptureLocals = function()
  return { hidden = secret }
end
Capture._locked = true
Capture._real_seterrorhandler = realSetter

local forwarded
Capture.prevErrorHandler = function(value) forwarded = value end

assert(loadfile('Capture/Safety.lua'))()

Capture:ApplyHandlerLock()
assert(_G.seterrorhandler == realSetter)
assert(Capture._locked == false)
assert(settings.lockErrorHandler == false)

local captured, key, messageKey = Capture:OnLuaError(secret, secret, false)
assert(captured == true)
assert(type(key) == 'string' and key:find('<inaccessible>', 1, true))
assert(messageKey == '<inaccessible>')
assert(forwarded == secret)
assert(RDL.Doctor.reset == true)
local hard = built[#built]
assert(hard.kind == 'LUA_ERROR')
assert(hard.message == '<inaccessible>')
assert(hard.stack == '<inaccessible>')
assert(hard.locals.hidden == '<inaccessible>')
assert(hard.extra.source == 'errorhandler')

forwarded = nil
Capture._inHandler = true
assert(Capture:OnLuaError(secret, secret, false) == false)
assert(forwarded == secret)
Capture._inHandler = false

local extra = { hidden = secret, nested = { value = 1 } }
local suppressed = Capture:OnSuppressedError(secret, secret, { hidden = secret }, secret, secret, extra)
assert(type(suppressed) == 'table')
assert(suppressed.kind == 'SUPPRESSED')
assert(suppressed.message == '<inaccessible>')
assert(suppressed.stack == '<inaccessible>')
assert(suppressed.locals.hidden == '<inaccessible>')
assert(suppressed.addon == '<inaccessible>')
assert(suppressed.func == '<inaccessible>')
assert(suppressed.extra.hidden == '<inaccessible>')
assert(suppressed.extra.suppressed == true)
extra.nested.value = 9
assert(suppressed.extra.nested.value == 1)

print('error intake tests: ok')
