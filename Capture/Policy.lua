-- !RothDevLib/Capture/Policy.lua
-- One-time ownership policy applied before Engine.lua performs EarlyInit.
-- The addon chains the handler once, never locks the global setter, and never
-- fights later owners automatically. Explicit /rdev reclaim remains available.

local RDL = _G.RothDevLib
if not (RDL and RDL.DB) then return end

if type(RDL.DB.EnsureReady) == "function" then
  pcall(RDL.DB.EnsureReady, RDL.DB)
end

local settings
if type(RDL.DB.GetSettings) == "function" then
  local ok, value = pcall(RDL.DB.GetSettings, RDL.DB)
  if ok and type(value) == "table" then settings = value end
end
if not settings then return end

-- Compatibility-first ownership. Engine.lua reads these values during
-- file-load EarlyInit, before the rest of the Capture modules are initialized.
settings.errorHandlerMode = "chain"
settings.chainCallPrevHandler = true
settings.maintainOwnership = false
settings.lockErrorHandler = false

-- The legacy fallback implementation tries secure-only Blizzard internals and
-- private ScriptErrorsFrame hooks. Safety.lua installs the supported
-- BugGrabber-only fallback after all Capture modules have loaded.
settings.fallbackHookScriptErrors = false

-- Do not replay the entire pre-existing BugGrabber database when fallback is
-- attached after RothDevLib loses ownership. Only future counter deltas import
-- unless the user deliberately opts into history.
if settings.importBugGrabberHistory == nil then
  settings.importBugGrabberHistory = false
end
