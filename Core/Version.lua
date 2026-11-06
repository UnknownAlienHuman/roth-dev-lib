-- !RothDevLib/Core/Version.lua
-- The TOC is the single source of truth for release metadata.

local RDL = _G.RothDevLib
if not RDL then return end

local function Metadata(key)
  local addons = _G.C_AddOns
  local getter = addons and addons.GetAddOnMetadata
  if type(getter) ~= "function" then return nil end

  local ok, value = pcall(getter, RDL.addonName, key)
  if not ok or type(value) ~= "string" or value == "" then return nil end
  return value
end

RDL.version = Metadata("Version") or "1.0.0-alpha.20.0"
RDL.interfaceVersion = Metadata("Interface") or "120105"
