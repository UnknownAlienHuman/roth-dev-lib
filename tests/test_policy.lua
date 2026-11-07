local settings = {
  errorHandlerMode = 'exclusive',
  chainCallPrevHandler = false,
  maintainOwnership = true,
  lockErrorHandler = true,
  fallbackHookScriptErrors = true,
}

local ensureCalls = 0
_G.RothDevLibDB = { settings = settings }
_G.RothDevLib = {
  DB = {
    EnsureReady = function()
      ensureCalls = ensureCalls + 1
      return true
    end,
    GetSettings = function() return settings end,
  },
}

assert(loadfile('Capture/Policy.lua'))()
assert(ensureCalls == 0) -- file-load policy must not construct DB/session state
assert(RothDevLibDB.settings == settings)
assert(settings.errorHandlerMode == 'chain')
assert(settings.chainCallPrevHandler == true)
assert(settings.maintainOwnership == false)
assert(settings.lockErrorHandler == false)
assert(settings.fallbackHookScriptErrors == false)
assert(settings.importBugGrabberHistory == false)

print('capture policy tests: ok')
