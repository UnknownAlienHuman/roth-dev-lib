-- !RothDevLib/UI/Hyperlink.lua
-- Custom hyperlinks for opening RothDevLib UI from chat/logs.
-- Link format: |Hrothdevlib:sig:<signature>|h[open]|h

local RDL = _G.RothDevLib
if not RDL then return end

RDL.UI = RDL.UI or {}
local UI = RDL.UI

-- Public helper to format a clickable link.
function UI:MakeSigLink(sig, label)
  sig = tostring(sig or "")
  if sig == "" then return "" end
  label = tostring(label or "open")
  return string.format("|Hrothdevlib:sig:%s|h[%s]|h", sig, label)
end

local function ParseSig(link)
  if type(link) ~= "string" then return nil end
  -- link passed to SetItemRef_* handlers usually includes the whole link body.
  local sig = link:match("^rothdevlib:sig:(.+)$")
  if sig and sig ~= "" then
    return sig
  end
  return nil
end

-- Handler entry point used by Blizzard hyperlink dispatch.
-- SetItemRef() will call SetItemRef_<linkType> if it exists.
_G.SetItemRef_rothdevlib = function(link, text, button, chatFrame)
  local sig = ParseSig(link)
  if not sig or sig == "" then return end

  if UI and UI.OpenToSig then
    pcall(function() UI:OpenToSig(sig) end)
  elseif UI and UI.Open then
    pcall(function() UI:Open() end)
  end

  -- Avoid showing item-ref tooltip for our links.
  if _G.ItemRefTooltip and _G.ItemRefTooltip:IsShown() then
    pcall(function() _G.ItemRefTooltip:Hide() end)
  end
end
