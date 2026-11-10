local F = assert(loadfile('tests/helpers/mission_fixture.lua'))()
local R, DB = RothDevLib, RothDevLib.DB
F.Load('Doctor/Validation.lua')
R.Validation:Init()
F.Load('Capture/Engine.lua')
F.Load('Capture/Taint.lua')
F.Load('Capture/Reported.lua')
F.Load('Capture/Screenshots.lua')
local capture, screenshots = R.Capture, R.Screenshots
_G.Screenshot = function() screenshots:OnEvent('SCREENSHOT_SUCCEEDED') end
screenshots:Init()
assert(screenshots:SetEnabled(true))
local callbackCount = 0
R:RegisterCallback('RDL_CAPTURE', 'verify-committed', function(entry, group)
  callbackCount = callbackCount + 1
  local saved = DB:GetGroup(entry.sig)
  assert(saved and saved.occurrences[1].compact)
  assert(DB:GetSessionIndex(entry.sessionId)[entry.sig])
  assert(group.occurrences[1].compact and group.occurrences[1].locals == nil)
end)
local state = assert(capture:OnRestrictionStateChanged('ADDON_RESTRICTION_STATE_CHANGED', 1, 2))
assert(DB.session.taints == 0 and DB.session.restrictionChanges == 1)
assert(screenshots._pending == nil)
assert(state.origin == nil and state.ctx.extra.observerOrigin.addon == 'Observer')
assert(state.ctx.extra.evidence.stackProvenance == 'event-observer')
_G.debugstack = function() return 'Interface/AddOns/!RothDevLib/Capture/Taint.lua:71' end
local taint = assert(capture:OnTaintEvent('ADDON_ACTION_BLOCKED', 'Target', 'SetPoint'))
assert(DB.session.taints == 1 and taint.addon == 'Target')
assert(R.Validation.taint.selfBlocked == 0 and R.Validation.taint.selfState == 0)
assert(taint.origin == nil and taint.ctx.extra.blocked == 'SetPoint')
assert(taint.ctx.extra.evidence.rootCause == 'not-established')
assert(taint.ctx.extra.faultAddon == nil and taint.ctx.extra.reportedAddon == 'Target')
assert(screenshots._pending.signature == taint.sig)
F.RunTimer(0.1)
local savedTaint = DB:GetGroup(taint.sig)
assert(savedTaint.occurrences[1].evidence.blocked == 'SetPoint')
assert(savedTaint.occurrences[1].evidence.evidence.stackProvenance == 'event-observer')
local hidden = capture.BuildEntry('LUA_ERROR', 'Interface/AddOns/Target/Core.lua:9: attempt to compare a secret value',
  'Interface/AddOns/Target/Core.lua:9', { value = F.secret }, nil, nil, { observed = F.secret })
assert(hidden.ctx.extra.evidence.category == 'SECRET_ACCESS_MESSAGE')
assert(hidden.ctx.extra.evidence.classification == 'message-heuristic')
assert(hidden.locals.value == '<inaccessible>')
assert(capture.StoreEntry(hidden) == 'stored')
assert(DB:GetGroup(hidden.sig).ctx.extra.observed == '<inaccessible>')
-- Per-occurrence evidence must not be overwritten by the latest occurrence.
for i = 1, 2 do
  local entry = capture.BuildEntry('ANOMALY', 'layout differs', '', nil, 'Target', 'Layout',
    { expected = 'visible', observed = 'hidden-' .. i })
  assert(capture.StoreEntry(entry) == 'stored')
end
local anomalySig = capture._lastStoredSig
local anomaly = DB:GetGroup(anomalySig)
assert(anomaly.occurrences[1].evidence.observed == 'hidden-2')
assert(anomaly.occurrences[2].evidence.observed == 'hidden-1')
assert(callbackCount == 5 and R._callbacks.RDL_CAPTURE['verify-committed'])
-- Export carries saved performance/screenshot evidence without live module dependence.
assert(DB:SaveDiagnostics({ schema = 1, ts = time(), coverage = { handlerOwned = true },
  wrappedCPU = { status = 'available', rows = { { key = 'Target:Layout', total = 12, n = 3 } } },
  nativeProfiler = { status = 'available', timeUnit = 'ms', countUnit = 'ticks',
    rows = { { addon = 'Target', RecentAverageTime = 2 } } } }))
F.Load('Util/JSON.lua')
F.Load('Export/Export.lua')
F.Load('Export/Packer.lua')
local full = R.Export:BuildFullObject({ includeOccurrences = true })
assert(full.session.id == DB.sessionId and full.session.diagnostics == nil)
assert(#full.diagnosticSessions == 1)
assert(full.diagnosticSessions[1].screenshots.records[1].signature == taint.sig)
local found
for _, group in ipairs(full.groups) do if group.sig == anomalySig then found = group end end
assert(found and found.occurrences[2].evidence.observed == 'hidden-1')
local packed = R.Export.Packer:BuildPackedJSON({ maxBytes = 32000 })
assert(#packed <= 32000 and packed:find('Target:Layout', 1, true))
assert(packed:find('success-event-observed', 1, true))
assert(packed:find('event-observer', 1, true))
local small = R.Export.Packer:BuildPackedJSON({ maxBytes = 4096, maxGroups = 50 })
assert(#small <= 4096 and not small:find('pack_budget_exhausted', 1, true))
assert(small:find('"diagnostics"', 1, true)) -- summary or explicit omission marker
-- A callback that clears the database must not charge the new session for an old error.
R:UnregisterCallback('RDL_CAPTURE', 'verify-committed')
R:RegisterCallback('RDL_CAPTURE', 'clear-after-commit', function() DB:Clear() end)
local oldSession = DB.session
local entry = capture.BuildEntry('LUA_ERROR', 'clear in callback', '', nil, 'Target')
assert(capture.StoreEntry(entry) == 'stored')
assert(DB.session ~= oldSession and DB.session.errors == 0)
assert(oldSession.errors > 0)
R:UnregisterCallback('RDL_CAPTURE', 'clear-after-commit')
capture:OnTaintEvent('ADDON_ACTION_FORBIDDEN', '!RothDevLib', 'SetPoint')
assert(R.Validation.taint.selfForbidden == 1)
local observed = capture.BuildEntry('TAINT_BLOCKED', 'Interface/AddOns/Other/Frame.lua:5',
  debugstack(), nil, 'Target', nil, { stackProvenance = 'event-observer', evidence = { note = 'reporter-data' } })
assert(observed.addon == 'Target' and observed.ctx.extra.reportedEvidence.note == 'reporter-data')
print('agent evidence pipeline tests: ok')
