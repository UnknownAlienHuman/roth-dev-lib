_G.RothDevLib = { UI = {} }
local RDL = RothDevLib
RDL.UI.Skin = nil
RDL.UI.Menu = nil
RDL.UI.Table = nil

assert(loadfile('UI/Monitor.lua'))()
local UI = RDL.UI
assert(UI:BuildMonitorContent(nil) == false)

local calls = 0
UI._BuildMonitorPanels = function()
  calls = calls + 1
  return nil
end
assert(UI:BuildMonitorContent({}) == false)
assert(UI._monitor.embedded == nil and calls == 1)

local instance = { ok = true }
UI._BuildMonitorPanels = function()
  calls = calls + 1
  return instance
end
assert(UI:BuildMonitorContent({}) == true)
assert(UI._monitor.embedded == instance and calls == 2)
assert(UI:BuildMonitorContent({}) == true)
assert(calls == 2)

print('monitor build-state tests: ok')
