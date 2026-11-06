_G.RothDevLib = { Capture = {} }
local RDL = RothDevLib
function _G.canaccessvalue() return true end
function _G.issecretvalue() return false end
function _G.canaccesstable() return true end
function _G.issecrettable() return false end
assert(loadfile('Util/Util.lua'))()
assert(loadfile('Util/BoundedCopy.lua'))()
RDL.Log = function() end
RDL.DB = { GetSettings = function() return { forwardToDefaultErrorHandler = true } end }

local forwarded = 0
RDL.Capture.prevErrorHandler = function() forwarded = forwarded + 1 end
RDL.Capture.OnLuaError = function(self)
  self._inHandler = true
  error('bootstrap intake failed')
end
RDL.Capture.BuildEntry = function()
  return { sig = 'x', addon = 'Test', func = 'Fn' }
end
RDL.Capture.StoreEntry = function() return 'stored' end
RDL.Capture.CaptureLocals = function() return nil end

assert(loadfile('Capture/Safety.lua'))()
-- The final implementation must clear flags even when BuildEntry later fails.
RDL.Capture.BuildEntry = function() error('build failed') end
local ok = pcall(RDL.Capture.OnLuaError, RDL.Capture, 'boom', 'stack', false)
assert(ok == true)
assert(RDL.Capture._inHandler == false)
assert(RDL.Capture._inChainWrapper == false)
assert(forwarded == 1)

-- Failed/throttled stores are not reported as captured.
RDL.Capture.BuildEntry = function() return { sig = 'x', addon = 'Test', func = 'Fn' } end
RDL.Capture.StoreEntry = function() return 'throttled' end
local captured = RDL.Capture:OnLuaError('boom', 'stack', true)
assert(captured == false)
assert(RDL.Capture._inHandler == false)

print('capture safety guard tests: ok')
