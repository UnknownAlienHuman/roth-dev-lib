local F = assert(loadfile('tests/helpers/mission_fixture.lua'))()
local R, DB = RothDevLib, RothDevLib.DB
local addonCount = 130
_G.C_AddOns = {
  GetNumAddOns = function() return addonCount end,
  GetAddOnInfo = function(i) return 'Addon' .. i end,
  IsAddOnLoaded = function(i) return true, i ~= 2 end,
  GetAddOnMetadata = function(i) return i == 1 and F.secret or 'v1' end,
}
_G.Enum = { AddOnProfilerMetric = { RecentAverageTime = 1, SessionAverageTime = 2,
  PeakTime = 3, CountTimeOver5Ms = 4, CountTimeOver50Ms = 5 } }
local enabled, nativeCalls = true, 0
_G.C_AddOnProfiler = {
  IsEnabled = function() return enabled end,
  GetTopKAddOnsForMetric = function(metric, k)
    nativeCalls = nativeCalls + 1
    assert(metric == 1 and k == 20)
    return { { addOnName = 'Addon1', metricValue = 3.5 },
      { addOnName = F.secret, metricValue = F.secret } }
  end,
  GetAddOnMetric = function(name, metric)
    assert(name == 'Addon1')
    return metric == 5 and F.secret or metric * 2
  end,
  GetOverallMetric = function() return 8 end,
}
local stats = {}
for i = 1, 40 do stats['Addon:Fn' .. i] = { n = i, total = i * 10, max = i, last = i, ema = i } end
R.CPU = { GetStats = function() return stats end }
R.Mem = { GetStats = function() return stats end, GetKB = function() return 1234 end }
R.Logger = { GetText = function() return string.rep('x', 10000) .. 'LATEST' end }
R.Capture = { ownsHandler = false, _fallback = { kind = 'unavailable' },
  _intakeStats = { stored = 3, throttled = 5 }, _bootQueue = {} }
F.Load('Core/Diagnostics.lua')
local D = R.Diagnostics
D:Init()
local evidence = DB.session.diagnostics
assert(evidence and evidence.schema == 1)
assert(evidence.system.build.build == '70783' and evidence.system.inCombat == false)
assert(evidence.coverage.handlerOwned == false and evidence.coverage.intakeAttempts.throttled == 5)
assert(#evidence.addons.rows == 128 and evidence.addons.omitted == 2)
assert(evidence.addons.rows[2].loaded == false)
assert(evidence.addons.rows[1].version == '<inaccessible>')
assert(#evidence.wrappedCPU.rows == 32 and evidence.wrappedCPU.omitted == 8)
assert(evidence.wrappedCPU.rows[1].key == 'Addon:Fn40')
assert(evidence.nativeProfiler.status == 'available' and #evidence.nativeProfiler.rows == 1)
assert(evidence.nativeProfiler.rows[1].CountTimeOver5Ms == 8)
assert(evidence.nativeProfiler.rows[1].CountTimeOver50Ms == nil)
assert(evidence.nativeProfiler.countUnit == 'ticks')
assert(#evidence.log == 8192 and evidence.log:sub(-6) == 'LATEST')
assert(evidence.samples[1].fps == 90 and evidence.samples[1].globalLuaHeapKB == 1234)
assert(F.tickers[1].interval == 30)
stats['Addon:Fn40'].total = 99999
assert(evidence.wrappedCPU.rows[1].total == 400) -- detached, not a live reference
for i = 1, 70 do F.clock = F.clock + 30; assert(D:Checkpoint('test')) end
assert(#DB.session.diagnostics.samples == 60)
enabled = false
assert(D:Checkpoint('disabled'))
assert(DB.session.diagnostics.nativeProfiler.status == 'disabled')
assert(DB.session.diagnostics.nativeProfiler.overallRecentMs == nil)
local before = nativeCalls
DB:GetSettings().enablePerfProfiling = false
assert(D:Checkpoint('setting'))
assert(nativeCalls == before)
DB:GetSettings().persistDiagnostics = false
local ticker = D._ticker
D:Init()
assert(ticker.cancelled and D._ticker == nil and D:Checkpoint('disabled') == false)
DB:GetSettings().persistDiagnostics = true
-- Existing session evidence survives a simulated reload through the real normalizer.
local sid = DB.sessionId
DB.raw, DB.session, DB.sessionId, DB._normalizedRoot = nil, nil, nil, nil
assert(DB:Init())
assert(DB.raw.sessions[2].id == sid and DB.raw.sessions[2].diagnostics)
assert(DB.raw.sessions[2].diagnostics.samples[60].fps == 90)
-- Only five recent sessions retain evidence; session metadata remains available.
for i = 1, 6 do
  D:Checkpoint('next-session')
  DB.raw, DB.session, DB.sessionId, DB._normalizedRoot = nil, nil, nil, nil
  assert(DB:Init())
end
D:Checkpoint('final')
assert(#DB:GetDiagnosticSessions() == 5)
assert(DB.raw.sessions[6].diagnostics == nil)
local snapshot = DB:GetDiagnosticSessions()
snapshot[1].diagnostics.coverage.handlerOwned = true
assert(DB.session.diagnostics.coverage.handlerOwned == false)
assert(DB:HandlePersistenceFailure('!RothDevLib'))
assert(D:Checkpoint('suspended') == false)
for _, session in ipairs(DB.raw.sessions) do assert(session.diagnostics == nil) end
print('agent diagnostic persistence tests: ok')
