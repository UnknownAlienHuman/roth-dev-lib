_G.RothDevLib = { addonName = '!RothDevLib', version = 'fallback' }
_G.C_AddOns = {
  GetAddOnMetadata = function(addon, key)
    assert(addon == '!RothDevLib')
    if key == 'Version' then return '1.0.0-alpha.20.0' end
    if key == 'Interface' then return '120105' end
  end,
}
assert(loadfile('Core/Version.lua'))()
assert(RothDevLib.version == '1.0.0-alpha.20.0')
assert(RothDevLib.interfaceVersion == '120105')
print('version metadata tests: ok')
