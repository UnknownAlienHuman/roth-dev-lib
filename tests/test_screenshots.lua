local F = assert(loadfile('tests/helpers/mission_fixture.lua'))()
local R, DB = RothDevLib, RothDevLib.DB
F.Load('Capture/Screenshots.lua')
local S = R.Screenshots
local calls = 0
_G.Screenshot = function() calls = calls + 1 end
S:Init()
assert(DB:GetSettings().autoScreenshots == false)
R:Fire('RDL_CAPTURE', { kind = 'LUA_ERROR', sig = 'off' })
assert(#F.timers == 0 and calls == 0)
assert(S:SetEnabled(true))
R:Fire('RDL_CAPTURE', { kind = 'TAINT_STATE', sig = 'state' })
assert(#F.timers == 0) -- normal transitions must not trigger pictures
R:Fire('RDL_CAPTURE', { kind = 'LUA_ERROR', sig = 'first' })
assert(calls == 0 and S._pending.status == 'queued')
assert(DB.session.screenshots.records[1].signature == 'first')
assert(S:Request('manual') == false) -- one in flight
assert(F.RunTimer(0.1) and calls == 1)
S:OnEvent('SCREENSHOT_SUCCEEDED')
assert(S._pending == nil)
assert(DB.session.screenshots.records[1].status == 'success-event-observed')
assert(DB.session.screenshots.records[1].filename == nil)
local ok, why = S:Request('manual')
assert(not ok and why == 'cooldown')
F.clock = F.clock + 31
ok, why = S:Request('duplicate', 'first', true)
assert(not ok and why == 'already-requested')
-- Cancel queued work on opt-out, leaving the timer as a harmless no-op.
assert(S:Request('second', 'second', true))
assert(S:SetEnabled(false))
F.RunTimer(0.1)
assert(calls == 1 and DB.session.screenshots.records[2].status == 'cancelled-before-request')
-- Manual request remains available with automation disabled; synchronous events work.
F.clock = F.clock + 31
_G.Screenshot = function() calls = calls + 1; S:OnEvent('SCREENSHOT_SUCCEEDED') end
assert(S:Request(F.secret, F.secret, false))
assert(F.RunTimer(0.1))
assert(S._pending == nil and calls == 2)
assert(DB.session.screenshots.records[3].reason == '<inaccessible>')
-- No event: record uncertainty, do not retry or assert success.
F.clock = F.clock + 31
_G.Screenshot = function() calls = calls + 1 end
assert(S:Request('no-event'))
F.RunTimer(0.1)
while F.RunTimer(10) do end
assert(DB.session.screenshots.records[4].status == 'completion-unconfirmed')
-- API failure is terminal and does not recurse through error intake.
F.clock = F.clock + 31
_G.Screenshot = function() error('denied') end
assert(S:Request('failure'))
F.RunTimer(0.1)
assert(DB.session.screenshots.records[5].status == 'call-failed')
-- Stop invalidates queued requests, including delayed callbacks from older generations.
F.clock = F.clock + 31
assert(S:Request('stop'))
S:Stop()
F.RunTimer(0.1)
assert(DB.session.screenshots.records[6].status == 'interrupted')
S:Init()
-- The total attempt budget cannot be bypassed by /rdev clear.
local attempts = S._attempts
DB:Clear()
assert(S._attempts == attempts and #DB.session.screenshots.records == 0)
_G.Screenshot = function() S:OnEvent('SCREENSHOT_FAILED') end
while S._attempts < 20 do
  F.clock = F.clock + 31
  assert(S:Request('limit'))
  F.RunTimer(0.1)
end
F.clock = F.clock + 31
ok, why = S:Request('overflow')
assert(not ok and why == 'session-limit')
assert(#DB.session.screenshots.records == 20 - attempts)
assert(DB:HandlePersistenceFailure('!RothDevLib'))
assert(S:Request('suspended') == false)
print('screenshot lifecycle tests: ok')
