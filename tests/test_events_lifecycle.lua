_G.RothDevLib = { addonName = '!RothDevLib', version = 'test' }
local RDL = RothDevLib
local order, registered = {}, {}
local frame = {}
function frame:RegisterEvent(event) registered[event] = true end
function frame:SetScript(name, fn) self[name] = fn end
_G.CreateFrame = function() return frame end
_G.time = function() return 100 end
_G.C_Timer = { After = function(_, fn) fn() end }

local function mark(name)
  return function() order[#order + 1] = name end
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
}
RDL.Logger = { Init = mark('logger-init') }
RDL.Doctor = { Init = mark('doctor-init') }
RDL.Validation = {
  Init = mark('validation-init'),
  MaybeContinueReloadLoop = mark('reload-loop'),
}
RDL.Bus = { Init = mark('bus-init') }
RDL.Mem = { StartWatcher = mark('mem-start'), StopWatcher = mark('mem-stop') }
RDL.Capture = {
  EarlyInit = mark('capture-early'),
  Init = mark('capture-init'),
  FlushBootQueue = mark('capture-flush'),
  OnLuaWarning = function(_, value) order[#order + 1] = 'warning:' .. value end,
  OnTaintEvent = mark('taint'),
  OnRestrictionStateChanged = mark('restriction'),
  OnLeaveCombat = mark('leave-combat'),
  BugGrabber = { Disable = mark('bug-disable') },
  ChatTap = { _active = { pending = true }, _timerToken = 4 },
}
RDL.Suppress = { SuppressAll = mark('suppress') }
RDL.UI = {
  Init = mark('ui-init'),
  UpdateTitle = mark('ui-title'),
  InitMinimapButton = mark('minimap-init'),
}
RDL.SelfCheckEarly = function(_, stage) order[#order + 1] = 'check:' .. stage end
RDL.Log = mark('log')

assert(loadfile('Core/Events.lua'))()
assert(registered.ADDON_LOADED and registered.PLAYER_LOGIN and registered.LUA_WARNING)
assert(registered.ADDONS_UNLOADING)
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
assert(table.concat(order, ',') == 'db-ready,db-init,log')
assert(RDL._initialized ~= true and RDL._initializing == false)
assert(RDL._initFailure and RDL._initFailure.stage == 'DB:Init')

-- A later authoritative lifecycle retry can complete initialization cleanly.
order = {}
dispatch(frame, 'PLAYER_LOGIN')
assert(order[1] == 'db-ready' and order[2] == 'db-init')
local joined = table.concat(order, ',')
assert(joined:find('capture-init', 1, true))
assert(joined:find('capture-flush', 1, true))
assert(joined:find('suppress', 1, true))
assert(joined:find('minimap-init', 1, true))
assert(joined:find('check:PLAYER_LOGIN', 1, true))
assert(RDL._initialized == true and RDL._initFailure == nil)

local count = #order
dispatch(frame, 'PLAYER_LOGIN')
-- InitAll is idempotent; only post-login self-check/reload continuation repeat.
assert(#order == count + 2)

order = {}
dispatch(frame, 'LUA_WARNING', 'demo')
assert(order[1] == 'warning:demo')
dispatch(frame, 'ADDONS_UNLOADING', true)
assert(table.concat(order, ',') == 'warning:demo,bug-disable,mem-stop,db-shutdown')
assert(RDL.Capture.ChatTap._active == nil and RDL.Capture.ChatTap._timerToken == 5)

-- PLAYER_LOGOUT and ADDONS_UNLOADING share one idempotent final teardown.
local shutdownCount = #order
dispatch(frame, 'PLAYER_LOGOUT')
assert(#order == shutdownCount)

print('event lifecycle tests: ok')
