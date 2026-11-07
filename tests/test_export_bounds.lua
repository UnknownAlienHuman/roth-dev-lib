_G.RothDevLib = { version = 'test' }
local RDL = RothDevLib

function _G.canaccessvalue() return true end
function _G.issecretvalue() return false end
function _G.canaccesstable(value) return type(value) == 'table' end
function _G.issecrettable() return false end
function _G.canaccessallvalues() return true end
_G.time = function() return 100 end
_G.date = function(_, value) return 'date-' .. tostring(value) end
_G.GetBuildInfo = function() return '12.1.5', '70783', 'date', 120105 end
_G.GetLocale = function() return 'enUS' end
_G.UnitName = function() return 'Tester' end
_G.GetRealmName = function() return 'Realm' end
_G.GetRealZoneText = function() return 'Zone' end
_G.GetSubZoneText = function() return 'Subzone' end

assert(loadfile('Util/SecretGuard.lua'))()
assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/BoundedCopy.lua'))()
assert(loadfile('Util/JSON.lua'))()

local groups = {}
for index = 1, 520 do
  local signature = 'g' .. index
  groups[signature] = {
    sig = signature,
    kind = 'LUA_ERROR',
    count = index,
    firstSeen = index,
    lastSeen = index,
    addon = 'Addon' .. (index % 7),
    func = 'Fn',
    message = 'message-' .. index,
    stack = 'Interface/AddOns/Test/Core.lua:' .. index,
    locals = 'x=' .. index,
    occurrences = {
      { ts = index, sig = signature, kind = 'LUA_ERROR', addon = 'Test',
        func = 'Fn', message = 'message-' .. index, stack = 'stack-' .. index },
    },
  }
end
groups.ignored = {
  sig = 'ignored', kind = 'LUA_ERROR', count = 1, lastSeen = 9999,
  addon = 'IgnoredAddon', func = 'Fn', message = 'must-not-export', stack = 'stack',
  ignored = false,
}

local DB = {
  groups = groups,
  session = { id = 1, nested = { value = 7 } },
}
RDL.DB = DB
function DB:IsReady() return true end
function DB:IterGroups() return next, self.groups, nil end
function DB:IsIgnored(signature) return signature == 'ignored' end
function DB:GetGroup(signature) return self.groups[signature] end
function DB:GetActiveGroupCount()
  local count = 0
  for signature in pairs(self.groups) do
    if not self:IsIgnored(signature) then count = count + 1 end
  end
  return count
end
RDL.Logger = { GetText = function() return string.rep('log', 1000) end }

assert(loadfile('Export/Export.lua'))()
assert(loadfile('Export/Packer.lua'))()
local E = RDL.Export

-- Public options are read raw and hard-clamped. The authoritative ignore table,
-- not a stale group.ignored flag, controls normal exports.
local hostileOptions = setmetatable({
  maxGroups = 999999,
  includeOccurrences = false,
}, {
  __index = function() error('export option __index must not run') end,
  __pairs = function() error('export option __pairs must not run') end,
})
local okFull, full = pcall(E.BuildFullObject, E, hostileOptions)
assert(okFull and type(full) == 'table')
assert(#full.groups == 500)
assert(full.summary.groupCount == 520 and full.summary.exportedGroupCount == 500)
for _, group in ipairs(full.groups) do
  assert(group.sig ~= 'ignored' and group.message ~= 'must-not-export')
end

-- Session and nested diagnostics are detached from live DB state.
assert(full.session.nested.value == 7)
full.session.nested.value = 99
assert(DB.session.nested.value == 7)

local zero = E:BuildFullObject({ maxGroups = 0 })
assert(#zero.groups == 0 and zero.summary.groupCount == 520)
local hidden = E:BuildFullObject({ sig = 'ignored', maxGroups = 1 })
assert(#hidden.groups == 0 and hidden.summary.groupCount == 0)
local included = E:BuildFullObject({ sig = 'ignored', includeIgnored = true, maxGroups = 1 })
assert(#included.groups == 1 and included.groups[1].sig == 'ignored')

-- Callable-table LibStub is the normal implementation shape and must still
-- activate optional LibDeflate support.
local fakeDeflate = {
  CompressDeflate = function(_, value) return 'C<' .. value .. '>' end,
  EncodeForPrint = function(_, value) return 'E<' .. value .. '>' end,
}
_G.LibStub = setmetatable({}, {
  __call = function(_, name)
    if name == 'LibDeflate' then return fakeDeflate end
  end,
})
assert(E:ToShareString('{}') == 'RDL1:E<C<{}>>')
_G.LibStub = nil
assert(E:ToShareString('{}') == 'RDL1:{}')

-- Use a smaller but deliberately heavy corpus for pack degradation.
DB.groups = {}
for index = 1, 24 do
  local signature = 'pack-' .. index
  DB.groups[signature] = {
    sig = signature,
    kind = 'LUA_ERROR',
    count = index,
    firstSeen = index,
    lastSeen = index,
    addon = 'PackAddon',
    func = 'VeryLongFunctionName',
    message = string.rep('m', 12000),
    stack = string.rep('Interface/AddOns/Pack/Core.lua:1\n', 200),
    locals = string.rep('l', 32000),
    ctx = { extra = { payload = string.rep('x', 8000) } },
    bus = {
      breadcrumbs = {
        { ts = index, cat = 'event', msg = string.rep('b', 4000), data = string.rep('d', 4000) },
      },
      metrics = { value = string.rep('v', 4000) },
    },
    occurrences = {
      { ts = index, sig = signature, kind = 'LUA_ERROR', addon = 'PackAddon',
        func = 'Fn', message = string.rep('o', 8000), stack = string.rep('s', 8000) },
    },
  }
end

local hostilePackOptions = setmetatable({
  maxBytes = 4096,
  maxGroups = 999999,
  maxOccurrences = 999999,
  includeLog = true,
  maxLogBytes = 999999,
}, {
  __index = function() error('packer option __index must not run') end,
  __pairs = function() error('packer option __pairs must not run') end,
})
local okPack, packed = pcall(E.Packer.BuildPackedJSON, E.Packer, hostilePackOptions)
assert(okPack and type(packed) == 'string')
assert(#packed <= 4096)
assert(packed ~= '{"error":"json_output_limit"}')
assert(packed ~= '{"error":"json_encode_failed"}')
assert(packed:sub(1, 1) == '{' and packed:sub(-1) == '}')

-- Source indexes are built once, and the coarse ladder must converge without
-- the former dozens/hundreds of full DB rebuilds.
local packStats = assert(E.Packer:GetLastStats())
assert(packStats.sourceGroups == 24)
assert(packStats.sourceTimeline == 24)
assert(packStats.attempts <= 16)
assert(packStats.degradationCount < packStats.attempts)
assert(packStats.outputBytes == #packed and packStats.maxBytes == 4096)
assert(packStats.exhausted ~= true)
packStats.attempts = 999
assert(E.Packer:GetLastStats().attempts ~= 999)

print('export and packer bound tests: ok')
