local loadCount = 0
local created = {}
_G.MenuUtil = nil
_G.UIParent = {}
_G.C_AddOns = {
  LoadAddOn = function(name)
    assert(name == 'Blizzard_Menu')
    loadCount = loadCount + 1
    _G.MenuUtil = { CreateContextMenu = function() end }
    return true
  end,
}
_G.CreateFrame = function(frameType, name, parent, template)
  local frame = { frameType=frameType, name=name, parent=parent, template=template }
  function frame:Hide() self.hidden = true end
  function frame:SetWidth(value) self.width = value end
  function frame:SetDefaultText(value) self.defaultText = value end
  created[#created+1] = frame
  return frame
end
_G.RothDevLib = {
  UI = {},
  Util = {
    Scrub = function(_, v) return v end,
    SafeToString = function(_, v) return tostring(v) end,
  },
}
assert(loadfile('UI/Menu.lua'))()
local menu = RothDevLib.UI.Menu
assert(menu:EnsureLoaded() == true)
assert(loadCount == 1)
assert(menu:SupportsWowStyleDropdown() == true)
local dd = menu:CreateFilterDropdown({}, 'Test', 170, 'All')
assert(dd and dd.width == 170 and dd.defaultText == 'All')
assert(loadCount == 1)
print('menu tests: ok')
