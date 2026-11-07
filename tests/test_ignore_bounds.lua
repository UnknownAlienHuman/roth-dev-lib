local now = 2000
_G.time = function() return now end
_G.RothDevLib = { addonName = '!RothDevLib', name = 'RothDevLib' }
local RDL = RothDevLib

_G.RothDevLibDB = {
  ignore = { sig = {}, addon = {} },
}
for index = 1, 1100 do
  RothDevLibDB.ignore.sig['sig-' .. index] = index
end
for index = 1, 600 do
  RothDevLibDB.ignore.addon['Addon' .. index] = index
end
RothDevLibDB.ignore.sig[string.rep('x', 5000)] = true
RothDevLibDB.ignore.sig.invalidFalse = false
RothDevLibDB.ignore.sig.invalidTable = {}
RothDevLibDB.ignore.addon[string.rep('a', 200)] = true

local initCalls = 0
local DB = {}
RDL.DB = DB
function DB:Init()
  initCalls = initCalls + 1
  self.raw = RothDevLibDB
  return true
end
function DB:EnsureReady()
  if self.raw then return true end
  return self:Init()
end
function DB:HandlePersistenceFailure(addonName)
  return addonName == '!RothDevLib'
end
function DB:IsIgnored(signature, addonName)
  local ignore = self.raw and self.raw.ignore
  return ignore and ((signature and ignore.sig[signature])
    or (addonName and ignore.addon[addonName])) and true or false
end

assert(loadfile('Core/IgnoreBounds.lua'))()

-- File-load normalization must not construct session/player DB state.
assert(initCalls == 0 and DB.raw == nil)
local earlySigCount, earlyAddonCount = 0, 0
for key, value in pairs(RothDevLibDB.ignore.sig) do
  earlySigCount = earlySigCount + 1
  assert(type(key) == 'string' and #key <= 4096)
  assert(value == true or type(value) == 'number')
end
for key, value in pairs(RothDevLibDB.ignore.addon) do
  earlyAddonCount = earlyAddonCount + 1
  assert(type(key) == 'string' and #key <= 128)
  assert(value == true or type(value) == 'number')
end
assert(earlySigCount == 1000 and earlyAddonCount == 512)
assert(RothDevLibDB.ignore.sig['sig-100'] == nil)
assert(RothDevLibDB.ignore.sig['sig-101'] == 101)
assert(RothDevLibDB.ignore.addon.Addon88 == nil)
assert(RothDevLibDB.ignore.addon.Addon89 == 89)

assert(DB:EnsureReady() == true and initCalls == 1)
local stats = DB:GetIgnoreStats()
assert(stats.signatures == stats.maxSignatures and stats.maxSignatures == 1000)
assert(stats.addons == stats.maxAddons and stats.maxAddons == 512)

-- Adding at the ceiling evicts the oldest timestamped rule, while toggling an
-- existing rule removes it without changing the public boolean contract.
assert(DB:ToggleIgnoreSig('new-signature') == true)
assert(DB.raw.ignore.sig['new-signature'] == now)
assert(DB.raw.ignore.sig['sig-101'] == nil)
assert(DB:IsIgnored('new-signature') == true)
assert(DB:ToggleIgnoreSig('new-signature') == false)
assert(DB:IsIgnored('new-signature') == false)
assert(DB:GetIgnoreStats().signatures == 999)

assert(DB:ToggleIgnoreAddon('NewestAddon') == true)
assert(DB.raw.ignore.addon.NewestAddon == now)
assert(DB.raw.ignore.addon.Addon89 == nil)
assert(DB:ToggleIgnoreAddon('NewestAddon') == false)
assert(DB:GetIgnoreStats().addons == 511)

assert(DB:ToggleIgnoreSig(string.rep('s', 4097)) == false)
assert(DB:ToggleIgnoreAddon(string.rep('a', 129)) == false)

-- Persistence failure applies a much smaller emergency bound without retrying
-- or clearing every useful ignore rule.
assert(DB:HandlePersistenceFailure('OtherAddon') == false)
assert(DB:HandlePersistenceFailure('!RothDevLib') == true)
stats = DB:GetIgnoreStats()
assert(stats.signatures <= 100 and stats.addons <= 64)
local compactSigCount, compactAddonCount = 0, 0
for _ in pairs(DB.raw.ignore.sig) do compactSigCount = compactSigCount + 1 end
for _ in pairs(DB.raw.ignore.addon) do compactAddonCount = compactAddonCount + 1 end
assert(compactSigCount == stats.signatures and compactAddonCount == stats.addons)

assert(DB:ClearIgnore() == true)
stats = DB:GetIgnoreStats()
assert(stats.signatures == 0 and stats.addons == 0 and stats.dropped == 0)
assert(next(DB.raw.ignore.sig) == nil and next(DB.raw.ignore.addon) == nil)

print('ignore registry bounds tests: ok')
