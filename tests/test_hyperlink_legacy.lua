_G.LinkUtil = nil
_G.ItemRefTooltip = {
  shown = true,
  IsShown = function(self) return self.shown end,
  Hide = function(self) self.shown = false end,
}
_G.RothDevLib = {
  addonName = '!RothDevLib',
  UI = {},
  SecretGuard = {
    CanAccess = function() return true end,
    IsSecret = function() return false end,
  },
  Log = function() end,
}
local opened
RothDevLib.UI.OpenToSig = function(_, sig) opened = sig end
assert(loadfile('UI/Hyperlink.lua'))()
assert(RothDevLib.UI._hyperlinkDispatch == 'legacy')
local link = RothDevLib.UI:MakeSigLink('A|B:C', 'open')
local body = link:match('^|H(.-)|h')
SetItemRef_rothdevlib(body)
assert(opened == 'A|B:C')
assert(ItemRefTooltip.shown == false)
print('legacy hyperlink tests: ok')
