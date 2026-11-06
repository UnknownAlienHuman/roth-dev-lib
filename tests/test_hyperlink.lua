local registered = {}
_G.LinkProcessorResponse = { Unhandled = 1, Handled = 2 }
_G.LinkUtil = {
  IsLinkHandlerRegistered = function(kind) return registered[kind] ~= nil end,
  RegisterLinkHandler = function(kind, fn) registered[kind] = fn end,
  FormatLink = function(kind, text, ...)
    local args = {...}
    return '|H' .. kind .. ':' .. table.concat(args, ':') .. '|h' .. text .. '|h'
  end,
}
_G.RothDevLib = {
  addonName = '!RothDevLib',
  UI = {},
  SecretGuard = {
    CanAccess = function() return true end,
    IsSecret = function() return false end,
    CanAccessTable = function(_, v) return type(v) == 'table' end,
  },
  Internal = {
    Call = function(_, _, _, fn, self, ...)
      fn(self, ...)
      return true
    end,
  },
  Log = function() end,
}
local opened
RothDevLib.UI.OpenToSig = function(_, sig) opened = sig end
assert(loadfile('UI/Hyperlink.lua'))()
assert(RothDevLib.UI._hyperlinkDispatch == 'LinkUtil')
assert(type(registered.rothdevlib) == 'function')

local signature = 'LUA_ERROR|Addon/File.lua:#: bad value: a b%z'
local link = RothDevLib.UI:MakeSigLink(signature, 'op|en')
assert(link:match('^|Hrothdevlib:sig:'))
assert(link:find('%7C', 1, true), link)
assert(link:find('%3A', 1, true), link)
assert(link:find('%20', 1, true), link)
assert(link:find('[op||en]', 1, true), link)

local body = link:match('^|H(.-)|h')
local options = body:match('^rothdevlib:(.+)$')
local response = registered.rothdevlib(body, '[open]', { options = options })
assert(response == LinkProcessorResponse.Handled)
assert(opened == signature, tostring(opened))

opened = nil
registered.rothdevlib('rothdevlib:' .. options, nil, nil)
assert(opened == signature)
opened = nil
local hostileLinkData = setmetatable({}, { __index = function() error('hostile index') end })
assert(pcall(registered.rothdevlib, body, '[open]', hostileLinkData) == true)
assert(opened == signature)

assert(RothDevLib.UI:MakeSigLink(string.rep('x', 1025), 'open') == '')
print('hyperlink tests: ok')
