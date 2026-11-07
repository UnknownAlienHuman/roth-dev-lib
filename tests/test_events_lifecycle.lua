_G.RothDevLib = { addonName = '!RothDevLib', name = 'RothDevLib', version = 'test' }
local RDL = RothDevLib
local order, registered, delayed = {}, {}, {}
local frame = {}
function frame:RegisterEvent(event) registered[event] = true end
function frame:SetScript(name, fn) self[name] = fn end
_G.CreateFrame = function() return frame end
_G.time = function() return 100 end
_G.C_Timer = { After = function(_, fn) delayed[#delayed + 1] = fn end }
_G.print = function() end

local function mark(name, result)
  return function()
    order[#order + 1] = name
    return result
  end
end

local dbInitAttempts = 0
RDL.DB = {
  MarkPlayerReady = mark('db-ready'),
  Init = function()
    order[#order + 1] = 'db-init'
    dbInitAttempts = dbInitAttempts + 1
    return dbInitAttempts > 1
  end,
  EnsureReady = mark('db-ensure'),
  OnShutdown = mark('db-shutdown'),
  HandlePersistenceFailure = function(_, addonName)
    order[#order + 1] = 'persistence:' .. addonName
    return true
  end,
}
RDL.Logger = { Init = mark('logger-init') }
RDL.Doctor = { Init = mark('doctor-init') }
RDL.Validation = {
  Init = mark('validation-init'),
  MaybeContinueReloadLoop = mark('reload-loop'),
}
RDL.Bus = { Init = mark('bus-init') }
RDL.Mem = { StartWatcher = mark('mem-start'), StopWatcher = mark('mem-stop') }

local captureInitAttempts = 0
RDL.Capture = {
  EarlyInit = mark('capture-early'),
  Init = function()
    order[#order + 1] = 'capture-init'
    captureInitAttempts = captureInitAttempts + 1
    if captureInitAttempts == 1 then error('capture init failed') end
    return false -- not owning the handler is a valid initialized fallback state
  end,
  FlushBootQueue = mark('capture-flush', 2),
  InstallFallbackHooks = mark('fallback-refresh'),
  OnLuaWarning = function(_, value) order[#order + 1] = 'warning:' .. value end,
  OnTaintEvent = mark('taint'),
  OnRestrictionStateChanged = mark('restriction'),
  OnLeaveCombat = mark('leave-combat'),
  BugGrabber = { Disable = mark('bug-disable') },
  ChatTap = { _active = { pending = true }, _timerToken = 4 },
  ownsHandler = false,
}
RDL.Suppress = { SuppressAll = mark('suppress') }
RDL.UI = {
  Init = mark('ui-init'),
  UpdateTitle = function()
    order[#order + 1] = 'ui-title'
    error('optional title failure')
  end,
  InitMinimapButton = mark('minimap-init'),
}
RDL.SelfCheckEarly = function(_, stage) order[#order + 1] = 'check:' .. stage end
RDL.Log = mark('log')

assert(loadfile('Core/Events.lua'))()
assert(registered.ADDON_LOADED and registered.PLAYER_LOGIN and registered.LUA_WARNING)
assert(registered.ADDONS_UNLOADING and registered.SAVED_VARIABLES_TOO_LARGE)
local dispatch = assert(frame.OnEvent)

dispatch(frame, 'ADDON_LOADED', '!RothDevLib')
assert(table.concat(order, ',') == 'logger-init,validation-init,capture-early,check:ADDON_LOADED')
for _, value in ipairs(order) do
  assert(value ~= 'db-ready' and value ~= 'db-init' and value ~= 'db-ensure')
end

-- A root DB failure must not start consumers or permanently mark the addon initialized.
order = {}
dispatch(frame, 'PLAYER_LOGIN')
assert(order[1] == 'db-ready' and order[2] == 'db-init')
assert(not table.concat(order, ','):find('capture-init', 1, true))
assert(not table.concat(order, ','):find('mem-start', 1, true))
assert(RDL._initialized ~= true and RDL._initializing == false)
assert(RDL._initFailure and RDL._initFailure.stage == 'DB:Init')

-- A throwing capture owner is essential: do not flush, initialize UI, start
-- watchers or leave a false successful state. Partial capture consumers are torn down.
order = {}
dispatch(frame, 'PLAYER_LOGIN')
local failedCaptureOrder = table.concat(order, ',')
assert(failedCaptureOrder:find('capture-init', 1, true))
assert(failedCaptureOrder:find('bug-disable', 1, true))
assert(failedCaptureOrder:find('mem-stop', 1, true))
assert(not failedCaptureOrder:find('capture-flush', 1, true))
assert(not failedCaptureOrder:find('ui-init', 1, true))
assert(not failedCaptureOrder:find('mem-start', 1, true))
assert(RDL._initialized ~= true and RDL._initializing == false)
assert(RDL._initFailure and RDL._initFailure.stage == 'Capture:Init')

-- A later lifecycle retry completes cleanly even when handler ownership is false.
order = {}
dispatch(frame, 'PLAYER_LOGIN')
local joined = table.concat(order, ',')
assert(joined:find('capture-init', 1, true))
assert(joined:find('capture-flush', 1, true))
assert(joined:find('suppress', 1, true))
assert(joined:find('ui-init', 1, true))
assert(joined:find('mem-start', 1, true))
assert(not joined:find('minimap-init', 1, true)) -- delayed and generation-gated
assert(RDL._initialized == true and RDL._initFailure == nil)
assert(type(RDL._initWarnings) == 'table' and #RDL._initWarnings == 1)
assert(RDL._initWarnings[1].stage == 'UI:UpdateTitle')
assert(#delayed == 1)
delayed[1]()
assert(order[#order] == 'minimap-init')

-- Loading BugGrabber after login refreshes fallback once; BugSack status alone
-- does not churn the fallback while RothDevLib owns the handler.
order = {}
dispatch(frame, 'ADDON_LOADED', '!BugGrabber')
assert(table.concat(order, ',') == 'fallback-refresh')
RDL.Capture.ownsHandler = true
order = {}
dispatch(frame, 'ADDON_LOADED', 'BugSack')
assert(#order == 0)
RDL.Capture.ownsHandler = false

local count = #order
dispatch(frame, 'PLAYER_LOGIN')
-- InitAll is idempotent; only post-login self-check/reload continuation repeat.
assert(#order == count + 2)

-- Persistence failure is handled only for this addon's SavedVariables owner.
order = {}
dispatch(frame, 'SAVED_VARIABLES_TOO_LARGE', 'OtherAddon')
assert(#order == 0)
dispatch(frame, 'SAVED_VARIABLES_TOO_LARGE', '!RothDevLib')
assert(table.concat(order, ',') == 'persistence:!RothDevLib')

order = {}
dispatch(frame, 'LUA_WARNING', 'demo')
assert(order[1] == 'warning:demo')
local tokenBeforeShutdown = RDL.Capture.ChatTap._timerToken
dispatch(frame, 'ADDONS_UNLOADING', true)
assert(table.concat(order, ',') == 'warning:demo,bug-disable,mem-stop,db-shutdown')
assert(RDL.Capture.ChatTap._active == nil)
assert(RDL.Capture.ChatTap._timerToken == tokenBeforeShutdown + 1)
assert(RDL._initialized == false)

-- Delayed callbacks become inert after final shutdown.
local beforeDelayedRetry = #order
delayed[1]()
assert(#order == beforeDelayedRetry)

-- PLAYER_LOGOUT and ADDONS_UNLOADING share one idempotent final teardown.
local shutdownCount = #order
dispatch(frame, 'PLAYER_LOGOUT')
assert(#order == shutdownCount)

print('event lifecycle tests: ok')
