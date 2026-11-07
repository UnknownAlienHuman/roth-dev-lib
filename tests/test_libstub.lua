_G.RothDevLib = {}
local RDL = RothDevLib
local secret = setmetatable({}, {
  __tostring = function() error('secret tostring') end,
  __index = function() error('secret index') end,
})
function _G.canaccessvalue(v) return v ~= secret end
function _G.issecretvalue(v) return v == secret end
function _G.canaccesstable(v) return v ~= secret end
function _G.issecrettable(v) return v == secret end
function _G.canaccessallvalues(...) return true end

assert(loadfile('Util/SecretGuard.lua'))()
assert(loadfile('Util/Util.lua'))()

local libraries = { ['RothDevLib-1.0'] = { MINOR = 2, Breadcrumb = function() return 'stale' end } }
local LibStub = {}
function LibStub:NewLibrary(major, minor)
  local existing = libraries[major]
  if existing and existing.MINOR and existing.MINOR >= minor then return nil end
  local lib = existing or {}
  libraries[major] = lib
  return lib
end
setmetatable(LibStub, { __call = function(_, major) return libraries[major] end })
_G.LibStub = LibStub

local calls = {}
function RDL:InitAddon(name, opts) calls.init = { name, opts }; return true end
for _, method in ipairs({
  'Breadcrumb', 'Metric', 'Alert', 'Assert', 'SafeCall', 'SafeCallCtx',
  'WrapSafe', 'WrapSafeCtx', 'WrapUnsafe', 'Profile', 'WrapProfiled',
  'MemDelta', 'WrapMemDelta', 'MemSample', 'Enter', 'Leave', 'Report',
  'ReportError', 'ReportWarning', 'ReportTaint', 'ReportSuppressed', 'Log',
}) do
  RDL[method] = function(_, ...) calls[method] = { ... }; return method end
end

assert(loadfile('Integration/LibStub.lua'))()
local lib = assert(LibStub('RothDevLib-1.0', true))
assert(lib.MINOR == 3)
assert(lib:Breadcrumb('A', 'B', 'C') == 'Breadcrumb')
assert(lib:Embed(secret, 'Test') == nil)
assert(lib:Embed({}, secret) == nil)

local target = {}
assert(lib:Embed(target, 'Test', { maxBreadcrumbs = 20 }) == target)
assert(calls.init[1] == 'Test')
assert(type(target.RDL_Breadcrumb) == 'function')
assert(target:RDL_Breadcrumb('flow', 'start', { n = 1 }) == 'Breadcrumb')
assert(calls.Breadcrumb[1] == 'Test')
assert(calls.Breadcrumb[2] == 'flow')

local locked = setmetatable({}, { __newindex = function() error('locked') end })
assert(lib:Embed(locked, 'Locked') == nil)
print('LibStub integration tests: ok')
