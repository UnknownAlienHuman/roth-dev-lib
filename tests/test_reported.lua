_G.RothDevLib = { Capture = {} }
local RDL = RothDevLib
local secret = setmetatable({}, {
  __tostring = function() error('secret tostring') end,
  __index = function() error('secret index') end,
  __pairs = function() error('secret pairs') end,
})
function _G.canaccessvalue(v) return v ~= secret end
function _G.issecretvalue(v) return v == secret end
function _G.canaccesstable(v) return v ~= secret end
function _G.issecrettable(v) return v == secret end
function _G.canaccessallvalues(...) return true end
function _G.debugstack() return 'Interface/AddOns/Test/Test.lua:12: stack' end
RDL.DB = { GetSettings = function() return { maxLocalsSize = 512 } end }
RDL.Log = function() end

assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/SecretGuard.lua'))()

local built, stored
RDL.Capture.BuildEntry = function(kind, msg, stack, locals, addon, funcName, extra)
  built = { kind = kind, msg = msg, stack = stack, locals = locals, addon = addon, funcName = funcName, extra = extra }
  return { sig = 'generated' }
end
RDL.Capture.StoreEntry = function(entry) stored = entry end

assert(loadfile('Capture/Reported.lua'))()

local opts = {
  code = secret,
  level = 'WARN',
  data = { hidden = secret, n = 1 },
  extra = { mutable = { x = 1 } },
  locals = { visible = 1, hidden = secret },
  signature = secret,
  func = secret,
}
RDL.Capture:OnReported(secret, secret, secret, opts)
opts.data.n = 2
opts.extra.mutable.x = 2
assert(built.kind == '<inaccessible>')
assert(built.addon == '<inaccessible>')
assert(built.msg == '[WARN] <inaccessible>: <inaccessible>')
assert(built.locals:find('hidden=<inaccessible>', 1, true))
assert(built.extra.data.hidden == '<inaccessible>')
assert(built.extra.data.n == 1)
assert(built.extra.mutable.x == 1)
assert(stored.sig == '<inaccessible>')
assert(built.funcName == '<inaccessible>')

local hostileOpts = setmetatable({}, { __pairs = function() error(secret, 0) end })
assert(pcall(RDL.Capture.OnReported, RDL.Capture, nil, nil, nil, hostileOpts) == true)
assert(built.kind == 'SUPPRESSED')
assert(built.addon == '<?>')

print('reported intake tests: ok')
