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

-- Default attach establishes a baseline instead of replaying history.
assert(bug:ImportNew() == 0)
assert(stored == 0)

_G.BugGrabberDB.errors[1].counter = 3
assert(bug:ImportNew() == 1)
assert(stored == 1)
assert(built[1].message == 'boom')
assert(built[1].locals.hidden == '<inaccessible>')

-- Reordering the list must not replay counters because keys are content-based.
_G.BugGrabberDB.errors[1], _G.BugGrabberDB.errors[2] =
  _G.BugGrabberDB.errors[2], _G.BugGrabberDB.errors[1]
assert(bug:ImportNew() == 0)
assert(stored == 1)

-- Explicit history import remains available for a fresh importer.
settings.importBugGrabberHistory = true
bug._counterByKey = {}
assert(bug:ImportNew() == 4)
assert(stored == 5)

-- A budget-limited partial scan must not delete counters for unseen records.
settings.importBugGrabberHistory = false
bug._counterByKey = {}
assert(bug:ImportNew() == 0)
local otherKey
for key in pairs(bug._counterByKey) do
  if key:find('other', 1, true) then otherKey = key end
end
assert(otherKey and bug._counterByKey[otherKey] == 1)
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

print('BugGrabber importer tests: ok')
