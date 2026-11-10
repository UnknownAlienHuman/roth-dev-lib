local F = assert(loadfile('tests/helpers/mission_fixture.lua'))()
local R, DB = RothDevLib, RothDevLib.DB
local registered, frame = {}, {}
function frame:RegisterEvent(event) registered[event] = true end
function frame:SetScript(name, fn) self[name] = fn end
_G.CreateFrame = function() return frame end
R.Capture = {
  Init = function() return true end, FlushBootQueue = function() return 0 end,
  _fallback = { kind = 'owned' }, ownsHandler = true,
}
F.Load('Capture/Screenshots.lua')
F.Load('Core/Diagnostics.lua')
F.Load('Core/Events.lua')
assert(registered.SCREENSHOT_SUCCEEDED and registered.SCREENSHOT_FAILED)
frame.OnEvent(frame, 'PLAYER_LOGIN')
assert(R._initialized and R.Diagnostics._ticker and DB.session.diagnostics)
local ticker = R.Diagnostics._ticker
frame.OnEvent(frame, 'PLAYER_LOGIN')
assert(R.Diagnostics._ticker == ticker) -- one sampler owner
frame.OnEvent(frame, 'ADDON_LOADED', 'AnotherAddon')
assert(R.Diagnostics._inventoryDirty)
_G.Screenshot = function() frame.OnEvent(frame, 'SCREENSHOT_FAILED') end
assert(R.Screenshots:Request('manual'))
F.RunTimer(0.1)
assert(DB.session.screenshots.records[1].status == 'failure-event-observed')
-- Persistence failure stops new data producers, clear resumes them once.
frame.OnEvent(frame, 'SAVED_VARIABLES_TOO_LARGE', '!RothDevLib')
assert(ticker.cancelled and R.Diagnostics._ticker == nil and R.Screenshots._stopped)
assert(DB.session.diagnostics == nil and DB.session.screenshots == nil)
DB:Clear()
assert(not R.Screenshots._stopped and R.Diagnostics._ticker and not DB:IsWriteSuspended())
local resumed = R.Diagnostics._ticker
frame.OnEvent(frame, 'PLAYER_LOGOUT')
assert(resumed.cancelled and R.Diagnostics._ticker == nil)
assert(DB.session.ended and DB.session.diagnostics.reason == 'PLAYER_LOGOUT')
local final = DB.session.diagnostics
resumed.fn() -- stale tick is inert
frame.OnEvent(frame, 'ADDONS_UNLOADING', true)
assert(DB.session.diagnostics == final)
print('diagnostics event lifecycle tests: ok')
