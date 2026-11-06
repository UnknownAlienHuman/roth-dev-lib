local secret = setmetatable({}, {
  __tostring = function() error('secret tostring') end,
  __index = function() error('secret index') end,
})
function _G.canaccessvalue(v) return v ~= secret end
function _G.issecretvalue(v) return v == secret end
function _G.canaccesstable(v) return v ~= secret end
function _G.issecrettable(v) return v == secret end
function _G.canaccessallvalues(...) return true end
_G.C_Timer = { NewTicker = function(_, fn) return { Cancel = function() end, Run = fn } end }

_G.RothDevLib = { Capture = {} }
local RDL = RothDevLib
local settings = {
  importBugGrabber = true,
  importBugGrabberHistory = false,
  bugGrabberImportMaxPerPoll = 10,
  bugGrabberScanMax = 100,
}
RDL.DB = { GetSettings = function() return settings end }
assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/BoundedCopy.lua'))()

local built, stored = {}, 0
RDL.Capture.BuildEntry = function(kind, message, stack, locals, addon, func, extra)
  local entry = { kind = kind, message = message, stack = stack, locals = locals, extra = extra }
  built[#built + 1] = entry
  return entry
end
RDL.Capture.StoreEntry = function()
  stored = stored + 1
  return 'stored'
end
RDL.Capture.ownsHandler = false

local errors = {
  { message = 'boom', stack = 'Interface/AddOns/Demo/Core.lua:7', locals = { hidden = secret }, counter = 2 },
  { message = 'other', stack = 'Interface/AddOns/Demo/Other.lua:9', counter = 1 },
}
setmetatable(errors, {
  __len = function() error('foreign __len must not run') end,
  __pairs = function() error('foreign __pairs must not run') end,
})
_G.BugGrabberDB = { errors = errors }

assert(loadfile('Capture/BugGrabber.lua'))()
local bug = assert(RDL.Capture.BugGrabber)
assert(bug:IsPresent())
assert(bug:Enable() == true and bug._enabled == true and bug._ticker ~= nil)
bug:Disable()

-- Default attach establishes one baseline instead of replaying history.
assert(bug:ImportNew() == 0)
assert(stored == 0 and bug._baselineComplete == true)

-- Once attached, the first occurrence of a new logical error must import now,
-- not only after BugGrabber increments its counter a second time.
_G.BugGrabberDB.errors[3] = {
  message = 'fresh',
  stack = 'Interface/AddOns/Demo/Fresh.lua:11',
  counter = 1,
}
assert(bug:ImportNew() == 1)
assert(stored == 1 and built[1].message == 'fresh')
_G.BugGrabberDB.errors[3] = nil
assert(bug:ImportNew() == 0)

_G.BugGrabberDB.errors[1].counter = 3
assert(bug:ImportNew() == 1)
assert(stored == 2)
assert(built[2].message == 'boom')
assert(built[2].locals.hidden == '<inaccessible>')

-- Reordering the list must not replay counters because keys are content-based.
_G.BugGrabberDB.errors[1], _G.BugGrabberDB.errors[2] =
  _G.BugGrabberDB.errors[2], _G.BugGrabberDB.errors[1]
assert(bug:ImportNew() == 0)
assert(stored == 2)

-- Explicit history import remains available and starts a fresh mode contract.
settings.importBugGrabberHistory = true
assert(bug:ImportNew() == 4)
assert(stored == 6)

-- Returning to normal mode baselines once without replaying imported history.
settings.importBugGrabberHistory = false
assert(bug:ImportNew() == 0 and bug._baselineComplete == true)
local otherKey
for key in pairs(bug._counterByKey) do
  if key:find('other', 1, true) then otherKey = key end
end
assert(otherKey and bug._counterByKey[otherKey] == 1)

-- An incomplete raw-key scan must never prune counters it did not observe.
bug._counterByKey.__sentinel = 7
for index = 1, 20 do errors['metadata' .. index] = true end
settings.bugGrabberScanMax = 5
assert(bug:ImportNew() == 0)
assert(bug._counterByKey.__sentinel == 7)
for index = 1, 20 do errors['metadata' .. index] = nil end
settings.bugGrabberScanMax = 100
assert(bug:ImportNew() == 0)
assert(bug._counterByKey.__sentinel == nil)

-- A budget-limited partial import must not delete counters for unseen records.
settings.bugGrabberImportMaxPerPoll = 1
_G.BugGrabberDB.errors[1].counter = _G.BugGrabberDB.errors[1].counter + 2
_G.BugGrabberDB.errors[2].counter = _G.BugGrabberDB.errors[2].counter + 1
RDL.Capture.StoreEntry = function() stored = stored + 1; return 'stored' end
assert(bug:ImportNew() == 1)
assert(bug._counterByKey[otherKey] ~= nil)
settings.bugGrabberImportMaxPerPoll = 10

RDL.Capture.StoreEntry = function() return 'throttled' end
for _, record in ipairs(_G.BugGrabberDB.errors) do record.counter = record.counter + 1 end
assert(bug:ImportNew() == 0)

RDL.Capture.ownsHandler = true
bug._enabled = true
assert(bug:ImportNew() == 0 and bug._enabled == false)
assert(bug._baselineComplete == false and next(bug._counterByKey) == nil)

print('BugGrabber importer tests: ok')
