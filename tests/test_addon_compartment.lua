local owner
local hides = 0
_G.GameTooltip = {
  SetOwner = function(_, value) owner = value end,
  GetOwner = function() return owner end,
  SetText = function() end,
  AddLine = function() end,
  Show = function() end,
  Hide = function() hides = hides + 1; owner = nil end,
}
local toggles = 0
_G.RothDevLib = {
  addonName = '!RothDevLib',
  UI = {
    Toggle = function() toggles = toggles + 1 end,
    GetUnreadCount = function() return 2 end,
  },
  Internal = { Call = function(_, _, _, fn, self, ...) fn(self, ...); return true end },
}
assert(loadfile('UI/AddonCompartment.lua'))()
local button = {}
RothDevLib_OnAddonCompartmentClick()
assert(toggles == 1)
RothDevLib_OnAddonCompartmentEnter(nil, button)
assert(owner == button)
RothDevLib_OnAddonCompartmentLeave(nil, {})
assert(hides == 0)
RothDevLib_OnAddonCompartmentLeave(nil, button)
assert(hides == 1)
print('addon compartment tests: ok')
