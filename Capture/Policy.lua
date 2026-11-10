-- !RothDevLib/Capture/Policy.lua
-- One-time file-load policy. SavedVariables are available through
-- LoadSavedVariablesFirst, but DB/session initialization remains a PLAYER_LOGIN
-- responsibility.

local RDL = _G.RothDevLib
if not RDL then return end

if type(_G.RothDevLibDB) ~= "table" then _G.RothDevLibDB = {} end
local raw = _G.RothDevLibDB
if type(raw.settings) ~= "table" then raw.settings = {} end
local settings = raw.settings

settings.errorHandlerMode = "chain"
settings.chainCallPrevHandler = true
settings.maintainOwnership = false
settings.lockErrorHandler = false
settings.fallbackHookScriptErrors = false
if type(settings.importBugGrabberHistory) ~= "boolean" then
  settings.importBugGrabberHistory = false
end
