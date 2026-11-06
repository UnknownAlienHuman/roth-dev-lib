local secret = setmetatable({}, {
  __tostring = function() error('secret tostring') end,
  __index = function() error('secret index') end,
})
function _G.canaccessvalue(v) return v ~= secret end
function _G.issecretvalue(v) return v == secret end
function _G.canaccesstable(v) return v ~= secret end
function _G.issecrettable(v) return v == secret end
function _G.canaccessallvalues(...) return true end

_G.RothDevLib = { Capture = {} }
local RDL = RothDevLib
local settings = {
  importBugGrabber = true,
  bugGrabberImportMaxPerPoll = 10,
  bugGrabberScanMax = 100,
}
RDL.DB = { GetSettings = function() return settings end }
assert(loadfile('Util/Util.lua'))()

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

_G.BugGrabberDB = {
  errors = {
    { message = 'boom', stack = 'Interface/AddOns/Demo/Core.lua:7', locals = { hidden = secret }, counter = 2 },
    secret,
  },
}
assert(loadfile('Capture/BugGrabber.lua'))()
local bug = assert(RDL.Capture.BugGrabber)
assert(bug:IsPresent())
assert(bug:ImportNew() == 2)
assert(stored == 2)
assert(built[1].kind == 'LUA_ERROR')
assert(built[1].message == 'boom')
assert(built[1].locals.hidden == '<inaccessible>')
assert(bug:ImportNew() == 0)

_G.BugGrabberDB.errors[1].counter = 3
assert(bug:ImportNew() == 1)
assert(stored == 3)

RDL.Capture.StoreEntry = function() return 'throttled' end
_G.BugGrabberDB.errors[1].counter = 4
assert(bug:ImportNew() == 0)

print('BugGrabber importer tests: ok')
