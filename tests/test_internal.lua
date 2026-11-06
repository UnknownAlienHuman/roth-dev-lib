_G.RothDevLib = { addonName = '!RothDevLib' }
_G.debugstack = function() return 'stack' end
_G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }

local RDL = RothDevLib
local tokens, leaves = {}, {}
RDL.Doctor = {
  Enter = function(_, addon, func, ctx)
    local token = { addon = addon, func = func, ctx = ctx }
    tokens[#tokens + 1] = token
    return token
  end,
  Leave = function(_, token) leaves[#leaves + 1] = token end,
}
RDL.Util = {
  SafeToString = function(_, value)
    return type(value) == 'string' and value or '<value>'
  end,
  FilterSecretEscapes = function(_, value) return value end,
}
local captured
RDL.Capture = {
  OnSuppressedError = function(_, err, stack, locals, addon, func, extra)
    captured = { err = err, stack = stack, addon = addon, func = func, extra = extra }
  end,
}

assert(loadfile('Core/Internal.lua'))()
local I = RDL.Internal

local result = table.pack(I:Call('Addon', 'returns', function()
  return 1, nil, 3, 4, nil, 6, 7, 8
end))
assert(result.n == 9 and result[1] == true and result[9] == 8)
assert(leaves[#leaves] == tokens[#tokens])

local ok, err = I:Call('Addon', 'fails', function() error('boom') end)
assert(ok == false and type(err) == 'string' and err:find('boom', 1, true))
assert(type(captured.err) == 'string' and captured.err:find('boom', 1, true) and captured.func == 'fails')
assert(leaves[#leaves] == tokens[#tokens])

RDL.CPU = { Measure = function() error('profiler failed') end }
local before = #leaves
local infraOK, infraErr = I:Call('Addon', 'infra', function() return true end)
assert(infraOK == false and type(infraErr) == 'string' and infraErr:find('profiler failed', 1, true))
assert(#leaves == before + 1 and leaves[#leaves] == tokens[#tokens])
assert(I._depth == 0)

print('internal call tests: ok')
