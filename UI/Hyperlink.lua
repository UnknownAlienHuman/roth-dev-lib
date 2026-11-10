-- !RothDevLib/UI/Hyperlink.lua
-- Custom hyperlinks for opening RothDevLib UI from chat/logs.
-- Link format: |Hrothdevlib:sig:<percent-encoded-signature>|h[open]|h

local RDL = _G.RothDevLib
if not RDL then return end

RDL.UI = RDL.UI or {}
local UI = RDL.UI

local LINK_TYPE = "rothdevlib"
local ACTION_SIG = "sig"
local MAX_SIG_BYTES = 1024
local MAX_OPTIONS_BYTES = 4096

local function IsAccessible(value)
  local SG = RDL.SecretGuard
  if SG and type(SG.CanAccess) == "function" then
    return SG:CanAccess(value)
  end

  local fn = _G.canaccessvalue
  if type(fn) == "function" then
    local ok, allowed = pcall(fn, value)
    return ok and allowed == true
  end

  local isSecret = _G.issecretvalue
  if type(isSecret) == "function" then
    local ok, secret = pcall(isSecret, value)
    return ok and secret == false
  end
  return true
end

local function IsSecret(value)
  local SG = RDL.SecretGuard
  if SG and type(SG.IsSecret) == "function" then
    return SG:IsSecret(value)
  end

  local fn = _G.issecretvalue
  if type(fn) ~= "function" then return false end
  local ok, secret = pcall(fn, value)
  return ok and secret == true
end

local function OrdinaryString(value, maxBytes, allowPrimitive)
  if not IsAccessible(value) or IsSecret(value) then return nil end
  if value == nil then return nil end

  local valueType = type(value)
  if valueType ~= "string" then
    if not allowPrimitive or (valueType ~= "number" and valueType ~= "boolean") then
      return nil
    end
    value = tostring(value)
  end

  if maxBytes and #value > maxBytes then return nil end
  return value
end

local function EncodeComponent(value)
  return (value:gsub("([^%w%-%._~])", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

local function DecodeComponent(value)
  value = OrdinaryString(value, MAX_OPTIONS_BYTES, false)
  if not value then return nil end

  local decoded = value:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  if #decoded > MAX_SIG_BYTES or decoded:find("%z") then return nil end
  return decoded
end

local function ParseSigOptions(options)
  options = OrdinaryString(options, MAX_OPTIONS_BYTES, false)
  if not options then return nil end

  local encoded = options:match("^" .. ACTION_SIG .. ":(.+)$")
  if not encoded then return nil end
  local sig = DecodeComponent(encoded)
  if not sig or sig == "" then return nil end
  return sig
end

local function OpenSignature(sig)
  if not sig or sig == "" then return end

  local fn, funcName
  if UI and type(UI.OpenToSig) == "function" then
    fn, funcName = UI.OpenToSig, "UI:OpenToSig"
  elseif UI and type(UI.Open) == "function" then
    fn, funcName = UI.Open, "UI:Open"
  else
    return
  end

  if RDL.Internal and type(RDL.Internal.Call) == "function" then
    RDL.Internal:Call(RDL.addonName, funcName, fn, UI, sig)
  else
    local ok = pcall(fn, UI, sig)
    if not ok and RDL.Log then
      RDL:Log("ERROR", "HYPERLINK", "Failed to open hyperlink", {})
    end
  end
end

local function OptionsFromLinkData(linkData)
  if not IsAccessible(linkData) or IsSecret(linkData) then return nil end
  if linkData == nil or type(linkData) ~= "table" then return nil end

  local SG = RDL.SecretGuard
  if SG and type(SG.CanAccessTable) == "function" and not SG:CanAccessTable(linkData) then
    return nil
  end

  local ok, options = pcall(function() return linkData.options end)
  if not ok then return nil end
  return OrdinaryString(options, MAX_OPTIONS_BYTES, false)
end

local function HandleLink(link, _text, linkData)
  local options = OptionsFromLinkData(linkData)
  if not options then
    local linkText = OrdinaryString(link, MAX_OPTIONS_BYTES + #LINK_TYPE + 1, false)
    if linkText then options = linkText:match("^" .. LINK_TYPE .. ":(.+)$") end
  end

  OpenSignature(ParseSigOptions(options))

  local responses = _G.LinkProcessorResponse
  return responses and responses.Handled or nil
end

local function RegisterHandler()
  local linkUtil = _G.LinkUtil
  if type(linkUtil) == "table" and type(linkUtil.RegisterLinkHandler) == "function" then
    local registered = false
    if type(linkUtil.IsLinkHandlerRegistered) == "function" then
      local ok, value = pcall(linkUtil.IsLinkHandlerRegistered, LINK_TYPE)
      registered = ok and value == true
    end

    if registered then
      UI._hyperlinkDispatch = "conflict"
      if RDL.Log then
        RDL:Log("WARN", "HYPERLINK", "Link type is already registered", { linkType = LINK_TYPE })
      end
      return
    end

    local ok, err = pcall(linkUtil.RegisterLinkHandler, LINK_TYPE, HandleLink)
    if ok then
      UI._hyperlinkDispatch = "LinkUtil"
    else
      UI._hyperlinkDispatch = "error"
      if RDL.Log then
        local message = RDL.Util and RDL.Util.SafeToString and RDL.Util:SafeToString(err) or "<error>"
        RDL:Log("ERROR", "HYPERLINK", "Failed to register link handler", { error = message })
      end
    end
    return
  end

  -- Compatibility fallback for older clients that still dispatch custom
  -- link types through SetItemRef_<type> globals.
  _G.SetItemRef_rothdevlib = function(link)
    local linkText = OrdinaryString(link, MAX_OPTIONS_BYTES + #LINK_TYPE + 1, false)
    local options = linkText and linkText:match("^" .. LINK_TYPE .. ":(.+)$") or nil
    OpenSignature(ParseSigOptions(options))

    local tooltip = _G.ItemRefTooltip
    if tooltip and type(tooltip.IsShown) == "function" and type(tooltip.Hide) == "function" then
      local ok, shown = pcall(tooltip.IsShown, tooltip)
      if ok and shown then pcall(tooltip.Hide, tooltip) end
    end
  end
  UI._hyperlinkDispatch = "legacy"
end
-- Public helper to format a clickable link.
function UI:MakeSigLink(sig, label)
  sig = OrdinaryString(sig, MAX_SIG_BYTES, true)
  if not sig or sig == "" then return "" end

  label = OrdinaryString(label, 48, true) or "open"
  label = label:gsub("[%c]", " "):gsub("|", "||")

  local options = ACTION_SIG .. ":" .. EncodeComponent(sig)
  local linkUtil = _G.LinkUtil
  if type(linkUtil) == "table" and type(linkUtil.FormatLink) == "function" then
    local ok, formatted = pcall(linkUtil.FormatLink, LINK_TYPE, "[" .. label .. "]", options)
    formatted = ok and OrdinaryString(formatted, MAX_OPTIONS_BYTES + 128, false) or nil
    if formatted then return formatted end
  end

  return string.format("|H%s:%s|h[%s]|h", LINK_TYPE, options, label)
end

RegisterHandler()
