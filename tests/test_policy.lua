local settings = {
  errorHandlerMode = 'exclusive',
  chainCallPrevHandler = false,
  maintainOwnership = true,
  lockErrorHandler = true,
  fallbackHookScriptErrors = true,
}

_G.RothDevLib = {
  DB = {
    EnsureReady = function() return true end,
    GetSettings = function() return settings end,
  },
}

assert(loadfile('Capture/Policy.lua'))()
assert(settings.errorHandlerMode == 'chain')
assert(settings.chainCallPrevHandler == true)
assert(settings.maintainOwnership == false)
assert(settings.lockErrorHandler == false)
assert(settings.fallbackHookScriptErrors == false)
assert(settings.importBugGrabberHistory == false)

print('capture policy tests: ok')
