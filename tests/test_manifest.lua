local file = assert(io.open('!RothDevLib.toc', 'rb'))
local toc = file:read('*a')
file:close()

assert(toc:find('## Interface: 120105', 1, true))
assert(toc:find('## SavedVariables: RothDevLibDB', 1, true))
assert(toc:find('## LoadSavedVariablesFirst: 1', 1, true))

local boundedCopy = assert(toc:find('Util\\BoundedCopy.lua', 1, true))
local callSafety = assert(toc:find('Core\\CallSafety.lua', 1, true))
local policy = assert(toc:find('Capture\\Policy.lua', 1, true))
local engine = assert(toc:find('Capture\\Engine.lua', 1, true))
local safety = assert(toc:find('Capture\\Safety.lua', 1, true))
local bugGrabber = assert(toc:find('Capture\\BugGrabber.lua', 1, true))

assert(boundedCopy < callSafety)
assert(callSafety < policy)
assert(policy < engine and engine < safety and safety < bugGrabber)

print('manifest/load-order tests: ok')
