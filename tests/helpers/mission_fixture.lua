-- Small ordinary-client fixture; production code is loaded unmodified by callers.
local F = { clock = 100, epoch = 1700000000, timers = {}, tickers = {} }
_G.RothDevLib = { name = 'RothDevLib', addonName = '!RothDevLib', version = 'test' }
_G.RothDevLibDB = nil
_G.time = function() return F.epoch + math.floor(F.clock) end
_G.GetTime = function() return F.clock end
_G.GetTimePreciseSec = GetTime
_G.date = os.date
_G.GetBuildInfo = function() return '12.1.5', '70783', 'date', 120105 end
_G.GetLocale = function() return 'enUS' end
_G.UnitName = function() return 'Tester' end
_G.UnitClass = function() return 'Mage', 'MAGE', 8 end
_G.GetRealmName = function() return 'Realm' end
_G.IsInInstance = function() return false, 'none' end
_G.GetInstanceInfo = function() return 'Zone', 'none', 0, '', 0, 0, false, 0 end
_G.UnitAffectingCombat = function() return false end
_G.IsEncounterInProgress = function() return false end
_G.GetRealZoneText = function() return 'Zone' end
_G.GetSubZoneText = function() return '' end
_G.InCombatLockdown = function() return false end
_G.GetFramerate = function() return 90 end
_G.wipe = function(t) for k in pairs(t) do t[k] = nil end; return t end
_G.debugstack = function() return 'Interface/AddOns/Observer/Event.lua:71: in function observer' end
local handler = function() end
_G.geterrorhandler = function() return handler end
_G.seterrorhandler = function(fn) handler = fn end
_G.hooksecurefunc = function() end
F.secret = setmetatable({}, { __index = function() error('secret read') end,
  __tostring = function() error('secret stringify') end })
_G.canaccessvalue = function(v) return v ~= F.secret end
_G.issecretvalue = function(v) return v == F.secret end
_G.canaccesstable = function(v) return v ~= F.secret end
_G.issecrettable = function(v) return v == F.secret end
_G.canaccessallvalues = function(...) for i = 1, select('#', ...) do
  if select(i, ...) == F.secret then return false end
end; return true end
_G.C_Timer = {
  After = function(delay, fn) F.timers[#F.timers + 1] = { delay = delay, fn = fn } end,
  NewTicker = function(interval, fn)
    local ticker = { interval = interval, fn = fn }
    function ticker:Cancel() self.cancelled = true end
    F.tickers[#F.tickers + 1] = ticker
    return ticker
  end,
}
function F.RunTimer(delay)
  for i, timer in ipairs(F.timers) do
    if timer.delay == delay then table.remove(F.timers, i); timer.fn(); return true end
  end
  return false
end
function F.Load(path) return assert(loadfile(path))() end
F.Load('Util/SecretGuard.lua')
F.Load('Util/Util.lua')
F.Load('Util/BoundedCopy.lua')
F.Load('Core/DB.lua')
F.Load('Core/DBLifecycle.lua')
RothDevLib.DB:MarkPlayerReady()
assert(RothDevLib.DB:Init())
F.Load('Integration/Callbacks.lua')
return F
