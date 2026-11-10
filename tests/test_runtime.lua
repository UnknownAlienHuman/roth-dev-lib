_G.RothDevLib = {}

local secret = setmetatable({}, {
  __tostring = function() error("secret tostring") end,
  __index = function() error("secret index") end,
  __pairs = function() error("secret pairs") end,
})

function _G.canaccessvalue(value) return value ~= secret end
function _G.issecretvalue(value) return value == secret end
function _G.canaccesstable(value) return value ~= secret end
function _G.issecrettable(value) return value == secret end
function _G.canaccessallvalues(...)
  for i = 1, select("#", ...) do
    if select(i, ...) == secret then return false end
  end
  return true
end
function _G.scrubsecretvalues(...)
  local n = select("#", ...)
  local out = {}
  for i = 1, n do
    local value = select(i, ...)
    if value == secret then out[i] = nil else out[i] = value end
  end
  return table.unpack(out, 1, n)
end

assert(loadfile("Util/Util.lua"))()
assert(loadfile("Util/SecretGuard.lua"))()
assert(loadfile("Util/JSON.lua"))()

local U = RothDevLib.Util
local SG = RothDevLib.SecretGuard
local J = RothDevLib.JSON

assert(U:SafeToString(secret) == "<inaccessible>")
assert(SG:CanAccess(secret) == false)
assert(SG:FormatValue(secret) == "<inaccessible>")
assert(J:Encode(secret) == '"<inaccessible>"')

local copied = U:CopyDiagnosticValue({ ordinary = true, hidden = secret, nested = { x = 1 } })
assert(copied.ordinary == true)
assert(copied.hidden == "<inaccessible>")
assert(copied.nested.x == 1)
local mutable = { n = 1 }
local snapshot = U:CopyDiagnosticValue(mutable)
mutable.n = 2
assert(snapshot.n == 1)
assert(J:Encode({ ordinary = true, hidden = secret }) == '{"hidden":"<inaccessible>","ordinary":true}')
assert(J:Encode({ [1] = "a", [2] = secret }) == '["a","<inaccessible>"]')
assert(J:Encode({ cycle = nil }) == '[]')
local cycle = {}; cycle.self = cycle
assert(J:Encode(cycle) == '{"self":"<cycle>"}')
local long = string.rep("x", 300)
local encoded = J:Encode(long, { maxStringBytes = 256 })
assert(encoded:find("<truncated>", 1, true))

print("runtime utility tests: ok")
