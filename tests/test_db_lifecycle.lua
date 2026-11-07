_G.RothDevLib = { addonName = '!RothDevLib', name = 'RothDevLib' }
local RDL = RothDevLib
local calls = { unitName = 0, init = 0, upsert = 0, groupsAtInit = nil, sessionsAtInit = nil, printed = 0 }
function _G.time() return 100 end
function _G.print() calls.printed = calls.printed + 1 end
function _G.UnitClass() return 'Mage', 'MAGE', 8 end
function _G.GetSpecialization() return 1 end
function _G.GetSpecializationInfo() return 62, 'Arcane' end
function _G.UnitName() calls.unitName = calls.unitName + 1; return 'Tester' end
function _G.GetRealmName() return 'Realm' end
function _G.GetBuildInfo() return '12.1.5', '70783', 'date', 120105 end

_G.RothDevLibDB = {
  settings = {
    maxGroups = 2,
    maxOccurrencesPerGroup = -5,
    cpuSampleRate = 9,
    minimap = { hide = 'bad', minimapPos = 999 },
  },
  groups = {
    good = {
      count = 'bad',
      pinned = true,
      lastSeen = 99,
      occurrences = { { ts = 1, kind = 'LUA_ERROR', message = 'x', locals = string.rep('x', 9000) }, 'bad' },
    },
    [9] = 'bad',
  },
  sessions = { 'bad', { id = 4 } },
  sessionIndex = {
    [4] = {
      __meta = { n = 99 },
      good = { count = 1, firstSeen = 1, lastSeen = 99 },
      g1 = { count = 1, firstSeen = 1, lastSeen = 1 },
      g11 = { count = 1, firstSeen = 11, lastSeen = 11 },
      missing = { count = 1 },
    },
  },
  ignore = { sig = {}, addon = {} },
}
for index = 1, 11 do
  RothDevLibDB.groups['g' .. index] = {
    count = 1,
    firstSeen = index,
    lastSeen = index,
    kind = 'ALERT',
    addon = 'Test',
    func = 'Fn',
    message = 'g' .. index,
    stack = '',
    occurrences = {},
  }
end

-- Compact model of the legacy DB owner. DBLifecycle must delay this player-
-- dependent initialization without replacing the actual persistence owner.
local DB = {}
RDL.DB = DB
function DB:IsReady() return self.raw ~= nil and type(self.raw.groups) == 'table' end
function DB:GetSettings() return self.raw and self.raw.settings end
function DB:Init()
  calls.init = calls.init + 1
  calls.sessionsAtInit = #_G.RothDevLibDB.sessions
  local groupCount = 0
  for _ in pairs(_G.RothDevLibDB.groups) do groupCount = groupCount + 1 end
  calls.groupsAtInit = groupCount
  if self:IsReady() then return end
  self.raw = _G.RothDevLibDB
  self.raw.settings = type(self.raw.settings) == 'table' and self.raw.settings or {}
  self.raw.groups = type(self.raw.groups) == 'table' and self.raw.groups or {}
  self.raw.sessions = type(self.raw.sessions) == 'table' and self.raw.sessions or {}
  self.raw.sessionIndex = type(self.raw.sessionIndex) == 'table' and self.raw.sessionIndex or {}
  local lastId = 0
  for _, session in ipairs(self.raw.sessions) do
    if type(session) == 'table' and type(session.id) == 'number' and session.id > lastId then
      lastId = session.id
    end
  end
  self.sessionId = lastId + 1
  self.session = {
    id = self.sessionId,
    started = time(),
    build = select(4, GetBuildInfo()),
    character = (UnitName('player') or '?') .. '-' .. (GetRealmName() or '?'),
    errors = 0,
  }
  table.insert(self.raw.sessions, 1, self.session)
  self.raw.sessionIndex[self.sessionId] = { __meta = { n = 0 } }
end
function DB:EnsureReady()
  if self:IsReady() then return true end
  self:Init()
  return self:IsReady()
end
function DB:UpsertGroup(entry)
  calls.upsert = calls.upsert + 1
  entry.lastSeen = entry.lastSeen or entry.ts or time()
  entry.pinned = entry.pinned == true
  entry.occurrences = { entry }
  self.raw.groups[entry.sig] = entry
  return entry
end
function DB:OnShutdown() if self.session then self.session.ended = time() end end
function DB:Clear()
  self.raw.groups = {}
  self.raw.sessions = {}
  self.raw.sessionIndex = {}
  self.raw = nil
  self.session = nil
  self.sessionId = nil
  self:Init()
end

assert(loadfile('Core/DBLifecycle.lua'))()

-- File-load capture policy must not construct player/session state.
assert(DB:EnsureReady() == false)
assert(DB.raw == nil and DB.session == nil)
assert(calls.unitName == 0 and calls.init == 0)

assert(loadfile('Capture/Policy.lua'))()
assert(RothDevLibDB.settings.errorHandlerMode == 'chain')
assert(RothDevLibDB.settings.maintainOwnership == false)
assert(DB.raw == nil and calls.unitName == 0)

DB:MarkPlayerReady()
assert(DB:Init() == true)
assert(DB.session and DB.session.character == 'Tester-Realm')
assert(calls.unitName == 1 and calls.init == 1)
assert(calls.groupsAtInit == 10 and calls.sessionsAtInit == 1)
assert(DB.raw._schema == 5)
assert(DB.raw.settings.maxGroups == 10)
assert(DB.raw.settings.maxOccurrencesPerGroup == 1)
assert(DB.raw.settings.cpuSampleRate == 1)
assert(DB.raw.settings.minimap.hide == false)
assert(DB.raw.settings.minimap.minimapPos == 360)
assert(DB.raw.groups[9] == nil)
local groupCount = 0
for _ in pairs(DB.raw.groups) do groupCount = groupCount + 1 end
assert(groupCount == 10)
assert(DB.raw.groups.g1 == nil and DB.raw.groups.g2 == nil)
assert(type(DB.raw.groups.good) == 'table')
assert(DB.raw.groups.good.count == 1)
assert(#DB.raw.groups.good.occurrences == 1)
assert(DB.raw.groups.good.occurrences[1].compact == true)
assert(DB.raw.groups.good.occurrences[1].locals == nil)
assert(#DB.raw.sessions == 2)
assert(DB.raw.sessionIndex[4].good and DB.raw.sessionIndex[4].g11)
assert(DB.raw.sessionIndex[4].g1 == nil and DB.raw.sessionIndex[4].missing == nil)
assert(DB.raw.sessionIndex[4].__meta.n == 2)
assert(DB.raw.sessionIndex[DB.sessionId].__meta.n == 0)

-- Queued boot entries are assigned only when committed into the real session.
local boot = {
  sig = 'boot', kind = 'LUA_ERROR', message = string.rep('m', 20000),
  stack = string.rep('s', 70000), locals = { x = 1 }, ts = 99,
}
assert(boot.sessionId == nil)
DB:UpsertGroup(boot)
assert(boot.sessionId == DB.sessionId)
assert(DB.raw.groups.boot == boot and calls.upsert == 1)
assert(#boot.message > 16000 and #boot.message < 17000)
assert(#boot.stack > 64000 and #boot.stack < 66000)
assert(boot.locals == '<structured locals omitted from persistence>')
assert(boot.occurrences[1].compact == true)
assert(boot.occurrences[1].locals == nil)
assert(#boot.occurrences[1].message < 4200)
assert(#boot.occurrences[1].stack < 17000)
local afterBootCount = 0
for _ in pairs(DB.raw.groups) do afterBootCount = afterBootCount + 1 end
assert(afterBootCount == 10)

local session = DB.session
assert(DB:Init() == true and DB.session == session)
assert(calls.unitName == 1 and calls.init == 1)
DB:OnShutdown()
assert(session.ended == 100)

-- Persistence failure is one bounded recovery path, not a retry loop.
for index = 1, 30 do
  DB.raw.groups['failure' .. index] = {
    sig = 'failure' .. index, count = 1, lastSeen = index,
    kind = 'LUA_ERROR', addon = 'Test', func = 'Fn',
    message = string.rep('m', 10000), stack = string.rep('s', 30000),
    locals = 'secret', ctx = { x = 1 }, bus = { x = 1 }, sys = { x = 1 },
    occurrences = { { message = 'old' } },
  }
end
assert(DB:HandlePersistenceFailure('OtherAddon') == false)
assert(DB:HandlePersistenceFailure('!RothDevLib') == true)
assert(DB:IsWriteSuspended() == true)
assert(DB.raw.settings.captureLocals == false)
assert(DB.raw.settings.maxGroups <= 20)
assert(DB.raw.settings.maxOccurrencesPerGroup == 1)
assert(calls.printed == 1)
local recoveredCount = 0
for _, group in pairs(DB.raw.groups) do
  recoveredCount = recoveredCount + 1
  assert(group.locals == nil and group.ctx == nil and group.bus == nil and group.sys == nil)
  assert(#group.occurrences == 0)
  assert(#group.message < 4200 and #group.stack < 17000)
end
assert(recoveredCount <= 20 and #DB.raw.sessions <= 10)
local beforeBlocked = calls.upsert
assert(DB:UpsertGroup({ sig = 'blocked' }) == nil)
assert(calls.upsert == beforeBlocked)

-- Explicit clear is the only in-session resume path.
DB:Clear()
assert(DB:IsWriteSuspended() == false)
assert(DB.raw.persistence == nil)

print('DB lifecycle tests: ok')
