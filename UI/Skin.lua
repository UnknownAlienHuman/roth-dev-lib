-- !RothDevLib/UI/Skin.lua
-- Shared UI styling helpers.
-- v3 rewrite: Blizzard-native look with proper templates.
-- Goals:
--   * Use Blizzard dialog/tooltip/panel backdrops as-is.
--   * Provide helpers that WORK WITH templates, not against them.
--   * Preserve all public API for submodules.

local RDL = _G.RothDevLib
if not RDL then return end

RDL.UI = RDL.UI or {}
local UI = RDL.UI

local Skin = {}
UI.Skin = Skin

---------------------------------------------------------------------------
-- Theme palette (v3: Blizzard-friendly — slightly brighter to match)
---------------------------------------------------------------------------
Skin.C = {
  bg          = { 0.07, 0.07, 0.09, 0.96 },
  bgAlt       = { 0.04, 0.04, 0.06, 0.92 },
  titleBg     = { 0.12, 0.12, 0.14, 1.00 },
  border      = { 0.40, 0.40, 0.40, 0.80 },
  tabActive   = { 0.22, 0.22, 0.26, 1.00 },
  tabInactive = { 0.12, 0.12, 0.14, 0.90 },
  tabHover    = { 0.18, 0.18, 0.22, 1.00 },
  splitter    = { 0.30, 0.30, 0.33, 1.00 },
  accent      = { 0.35, 0.55, 0.85, 1.00 },
  danger      = { 0.90, 0.25, 0.25, 1.00 },
  warning     = { 1.00, 0.76, 0.20, 1.00 },
  ok          = { 0.40, 0.85, 0.40, 1.00 },
  text        = { 0.85, 0.85, 0.85, 1.00 },
  textDim     = { 0.60, 0.60, 0.60, 1.00 },
  textBright  = { 1.00, 0.82, 0.00, 1.00 },  -- gold for headers
  textWhite   = { 1.00, 1.00, 1.00, 1.00 },
  rowAlt      = { 0.12, 0.12, 0.14, 0.80 },
  rowSelected = { 0.20, 0.34, 0.55, 0.65 },
  statusBar   = { 0.10, 0.10, 0.12, 1.00 },
  btnNormal   = { 0.18, 0.18, 0.20, 1.00 },
  btnHover    = { 0.26, 0.26, 0.30, 1.00 },
  btnPress    = { 0.10, 0.10, 0.12, 1.00 },
  inputBg     = { 0.05, 0.05, 0.07, 1.00 },
  badge       = { 0.85, 0.20, 0.20, 1.00 },
  badgeText   = { 1.00, 1.00, 1.00, 1.00 },
}

---------------------------------------------------------------------------
-- Theme (legacy compat)
---------------------------------------------------------------------------
Skin.Theme = {
  colors = {
    surface    = { 0.06, 0.06, 0.06, 0.95 },
    surfaceAlt = { 0.03, 0.03, 0.03, 0.70 },
    border     = { 0.40, 0.40, 0.40, 1.00 },
    accent     = { 0.24, 0.55, 0.92, 1.00 },
    danger     = { 0.95, 0.25, 0.25, 1.00 },
    warning    = { 1.00, 0.76, 0.20, 1.00 },
    ok         = { 0.40, 0.88, 0.40, 1.00 },
  },
  spacing = {
    xs = 4, sm = 6, md = 8, lg = 12, xl = 16, splitter = 6,
  },
}

---------------------------------------------------------------------------
-- Backdrop definitions (v3: proper Blizzard textures)
---------------------------------------------------------------------------
Skin.BD = {
  dialog = {
    bgFile   = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  },
  tooltip = {
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  },
  flat = {
    bgFile = "Interface/ChatFrame/ChatFrameBackground",
  },
  flatBorder = {
    bgFile   = "Interface/ChatFrame/ChatFrameBackground",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  },
}

---------------------------------------------------------------------------
-- Safe helpers
---------------------------------------------------------------------------
local function SafeCall(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and RDL and RDL.Log then
    pcall(function() RDL:Log("ERROR", "UI", "Skin helper failed", { err = tostring(err) }) end)
  end
  return ok
end

local function CanBackdrop(frame)
  return frame and type(frame.SetBackdrop) == "function"
end

function Skin:GetColor(name)
  local c = self.Theme and self.Theme.colors and self.Theme.colors[name]
  if type(c) == "table" then
    return tonumber(c[1]) or 1, tonumber(c[2]) or 1, tonumber(c[3]) or 1, tonumber(c[4]) or 1
  end
  return 1, 1, 1, 1
end

function Skin:GetSpacing(name, fallback)
  local v = self.Theme and self.Theme.spacing and self.Theme.spacing[name]
  return tonumber(v) or tonumber(fallback) or 0
end

---------------------------------------------------------------------------
-- Frame styling helpers (v3: Blizzard-native)
---------------------------------------------------------------------------

-- Apply proper Blizzard dialog window look.
function Skin:ApplyWindow(frame)
  if not CanBackdrop(frame) then return end
  SafeCall(function()
    frame:SetBackdrop(self.BD.dialog)
    frame:SetBackdropColor(0, 0, 0, 0.85)
    if frame.SetBackdropBorderColor then
      frame:SetBackdropBorderColor(1, 1, 1, 1)
    end
  end)
  if frame.SetClampedToScreen then frame:SetClampedToScreen(true) end
end

-- Apply tooltip-style inset for sub-panels.
function Skin:ApplyInset(frame)
  if not CanBackdrop(frame) then return end
  SafeCall(function()
    frame:SetBackdrop(self.BD.tooltip)
    frame:SetBackdropColor(0, 0, 0, 0.75)
    if frame.SetBackdropBorderColor then
      frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
    end
  end)
end

-- DarkFrame = tooltip-bordered dark panel (used for content areas)
function Skin:DarkFrame(frame, bdKey)
  if not frame or type(frame.SetBackdrop) ~= "function" then return end
  frame:SetBackdrop(self.BD[bdKey or "tooltip"])
  frame:SetBackdropColor(unpack(self.C.bg))
  if frame.SetBackdropBorderColor then
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.9)
  end
end

-- DarkInset = darker inner panel
function Skin:DarkInset(frame)
  if not frame or type(frame.SetBackdrop) ~= "function" then return end
  frame:SetBackdrop(self.BD.tooltip)
  frame:SetBackdropColor(unpack(self.C.bgAlt))
  if frame.SetBackdropBorderColor then
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
  end
end

---------------------------------------------------------------------------
-- Title + Status helpers (legacy compat)
---------------------------------------------------------------------------
function Skin:CreateTitle(frame, text)
  if not frame then return nil end
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", frame, "TOP", 0, -8)
  title:SetText(text or "")
  return title
end

function Skin:CreateStatus(frame)
  if not frame then return nil end
  local status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOP", frame, "TOP", 0, -30)
  status:SetJustifyH("CENTER")
  status:SetText("")
  return status
end

---------------------------------------------------------------------------
-- Frame state persistence (unchanged from v2)
---------------------------------------------------------------------------
local function GetFramesTable()
  local settings = (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or nil
  if not settings then return nil end
  settings.uiFrames = settings.uiFrames or {}
  return settings.uiFrames
end

local function GetPanesTable()
  local settings = (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or nil
  if not settings then return nil end
  settings.uiPanes = settings.uiPanes or {}
  return settings.uiPanes
end

function Skin:GetPaneState(paneKey)
  if not paneKey or paneKey == "" then return nil end
  local t = GetPanesTable()
  if not t then return nil end
  local src = t[paneKey]
  if type(src) ~= "table" then return nil end
  local out = {}
  for k, v in pairs(src) do out[k] = v end
  return out
end

function Skin:SavePaneState(paneKey, state)
  if not paneKey or paneKey == "" or type(state) ~= "table" then return end
  local t = GetPanesTable()
  if not t then return end
  t[paneKey] = t[paneKey] or {}
  for k, v in pairs(state) do t[paneKey][k] = v end
end

function Skin:SaveFrameState(frameKey, frame)
  if not frameKey or not frame then return end
  local t = GetFramesTable()
  if not t then return end
  local p, _, rp, x, y = frame:GetPoint(1)
  if not p then p, rp, x, y = "CENTER", "CENTER", 0, 0 end
  local w = frame.GetWidth and frame:GetWidth() or nil
  local h = frame.GetHeight and frame:GetHeight() or nil
  t[frameKey] = t[frameKey] or {}
  local s = t[frameKey]
  s.point = tostring(p)
  s.relPoint = tostring(rp or p)
  s.x = math.floor((tonumber(x) or 0) + 0.5)
  s.y = math.floor((tonumber(y) or 0) + 0.5)
  if w and h then
    s.w = math.floor(w + 0.5)
    s.h = math.floor(h + 0.5)
  end
end

function Skin:RestoreFrameState(frameKey, frame, defaultW, defaultH)
  if not frameKey or not frame then return end
  local t = GetFramesTable()
  local s = t and t[frameKey] or nil
  if defaultW and defaultH and frame.SetSize then
    frame:SetSize(defaultW, defaultH)
  end
  if s and frame.ClearAllPoints and frame.SetPoint then
    frame:ClearAllPoints()
    frame:SetPoint(s.point or "CENTER", UIParent, s.relPoint or "CENTER",
                   tonumber(s.x) or 0, tonumber(s.y) or 0)
    if s.w and s.h and frame.SetSize then
      frame:SetSize(tonumber(s.w) or defaultW or 0, tonumber(s.h) or defaultH or 0)
    end
    -- Reset if off-screen
    local left = frame.GetLeft and frame:GetLeft() or nil
    if left then
      local right  = (frame.GetRight  and frame:GetRight())  or 0
      local top    = (frame.GetTop    and frame:GetTop())    or 0
      local bottom = (frame.GetBottom and frame:GetBottom()) or 0
      local pw = UIParent and UIParent:GetWidth() or 0
      local ph = UIParent and UIParent:GetHeight() or 0
      if pw > 0 and ph > 0 then
        if right < 30 or left > (pw - 30) or top < 30 or bottom > (ph - 30) then
          frame:ClearAllPoints()
          frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
      end
    end
  else
    if frame.SetPoint then frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
  end
end

function Skin:AttachFrameStateHandlers(frameKey, frame)
  if not frameKey or not frame or frame._rdlStateHandlersAttached then return end
  frame._rdlStateHandlersAttached = true
  local function ScheduleSave()
    if frame._rdlSavePending then return end
    frame._rdlSavePending = true
    if C_Timer and type(C_Timer.After) == "function" then
      C_Timer.After(0.20, function()
        frame._rdlSavePending = false
        if UI and UI.Skin then UI.Skin:SaveFrameState(frameKey, frame) end
      end)
    else
      frame._rdlSavePending = false
      Skin:SaveFrameState(frameKey, frame)
    end
  end
  frame:HookScript("OnDragStop", ScheduleSave)
  frame:HookScript("OnSizeChanged", ScheduleSave)
end

---------------------------------------------------------------------------
-- Resize grip
---------------------------------------------------------------------------
function Skin:CreateResizeGrip(frame, minW, minH)
  if not frame or not frame.SetResizable then return nil end
  frame:SetResizable(true)
  if minW and minH and frame.SetMinResize then frame:SetMinResize(minW, minH) end
  local g = CreateFrame("Button", nil, frame)
  g:SetSize(16, 16)
  g:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
  g:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
  g:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
  g:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
  g:SetScript("OnMouseDown", function() if frame.StartSizing then frame:StartSizing("BOTTOMRIGHT") end end)
  g:SetScript("OnMouseUp", function() if frame.StopMovingOrSizing then frame:StopMovingOrSizing() end end)
  return g
end

---------------------------------------------------------------------------
-- v3: Blizzard-style button using UIPanelButtonTemplate
---------------------------------------------------------------------------
function Skin:BlizzButton(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 80, h or 22)
  b:SetText(text or "")
  return b
end

-- Flat dark button (fallback for compact areas like status bar)
function Skin:StyledButton(parent, text, w, h)
  -- Try Blizzard template first for nice look
  local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
  if ok and b then
    b:SetSize(w, h)
    b:SetText(text or "")
    return b
  end
  -- Fallback: flat styled button
  b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h)
  b:SetBackdrop(self.BD.flatBorder)
  b:SetBackdropColor(unpack(self.C.btnNormal))
  b:SetBackdropBorderColor(unpack(self.C.border))
  local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("CENTER", 0, 0)
  label:SetText(text or "")
  label:SetTextColor(unpack(self.C.text))
  b._label = label
  b.SetText = function(_, t) label:SetText(t or "") end
  b.GetText = function(_) return label:GetText() end
  local C = self.C
  b:SetScript("OnEnter", function(self) self:SetBackdropColor(unpack(C.btnHover)) end)
  b:SetScript("OnLeave", function(self) self:SetBackdropColor(unpack(C.btnNormal)) end)
  b:SetScript("OnMouseDown", function(self) self:SetBackdropColor(unpack(C.btnPress)) end)
  b:SetScript("OnMouseUp", function(self) self:SetBackdropColor(unpack(C.btnHover)) end)
  return b
end

---------------------------------------------------------------------------
-- v3: Tab button (used by DetailView sub-tabs + GroupGrid filters)
-- Thin, compact, dark-themed — sits inside Blizzard insets.
---------------------------------------------------------------------------
function Skin:TabButton(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h)
  b:SetBackdrop(self.BD.flatBorder)
  b:SetBackdropColor(unpack(self.C.tabInactive))
  b:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.6)

  local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("CENTER", 0, 0)
  label:SetText(text or "")
  label:SetTextColor(unpack(self.C.textDim))
  b._label = label
  b._isActiveTab = false
  b.SetText = function(_, t) label:SetText(t or "") end
  b.GetText = function(_) return label:GetText() end

  -- Badge (hidden by default)
  local badge = b:CreateFontString(nil, "OVERLAY")
  badge:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
  badge:SetPoint("LEFT", label, "RIGHT", 4, 0)
  badge:SetTextColor(unpack(self.C.danger))
  badge:Hide()
  b._badge = badge

  function b:SetBadge(count)
    count = tonumber(count) or 0
    if count > 0 then badge:SetText(tostring(count)); badge:Show()
    else badge:Hide() end
  end

  local C = self.C
  function b:SetActive(active)
    b._isActiveTab = active
    if active then
      b:SetBackdropColor(unpack(C.tabActive))
      b:SetBackdropBorderColor(unpack(C.accent))
      label:SetTextColor(1, 1, 1)
    else
      b:SetBackdropColor(unpack(C.tabInactive))
      b:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.6)
      label:SetTextColor(unpack(C.textDim))
    end
  end

  b:SetScript("OnEnter", function(self)
    if not self._isActiveTab then
      self:SetBackdropColor(unpack(C.tabHover))
      label:SetTextColor(unpack(C.text))
    end
  end)
  b:SetScript("OnLeave", function(self)
    if not self._isActiveTab then
      self:SetBackdropColor(unpack(C.tabInactive))
      label:SetTextColor(unpack(C.textDim))
    end
  end)

  return b
end

---------------------------------------------------------------------------
-- UIDropDownMenu skinning (legacy compat — used by GroupGrid fallback)
---------------------------------------------------------------------------
function Skin:SkinUIDropDown(dd, w)
  if not dd then return end
  if w and type(UIDropDownMenu_SetWidth) == "function" then
    pcall(function() UIDropDownMenu_SetWidth(dd, w) end)
  end
end

---------------------------------------------------------------------------
-- Badge helper
---------------------------------------------------------------------------
function Skin:Badge(parent, size)
  size = size or 18
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetSize(size, size)
  f:SetBackdrop(self.BD.flat)
  f:SetBackdropColor(unpack(self.C.badge))
  local label = f:CreateFontString(nil, "OVERLAY")
  label:SetFont("Fonts\\FRIZQT__.TTF", size > 16 and 9 or 8, "OUTLINE")
  label:SetPoint("CENTER", 0, 0)
  label:SetTextColor(unpack(self.C.badgeText))
  f._label = label
  function f:SetCount(n)
    n = tonumber(n) or 0
    if n > 0 then label:SetText(n > 99 and "99+" or tostring(n)); f:Show()
    else f:Hide() end
  end
  f:Hide()
  return f
end

---------------------------------------------------------------------------
-- Search box (dark themed)
---------------------------------------------------------------------------
function Skin:SearchBox(parent, w, h)
  local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
  box:SetSize(w or 180, h or 22)
  box:SetBackdrop(self.BD.flatBorder)
  box:SetBackdropColor(unpack(self.C.inputBg))
  box:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
  box:SetFontObject(ChatFontSmall)
  box:SetTextColor(unpack(self.C.text))
  box:SetAutoFocus(false)
  box:SetTextInsets(6, 20, 0, 0)

  local ph = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ph:SetPoint("LEFT", 6, 0)
  ph:SetText("Search...")
  ph:SetTextColor(unpack(self.C.textDim))
  box._placeholder = ph

  local clearBtn = CreateFrame("Button", nil, box)
  clearBtn:SetSize(14, 14)
  clearBtn:SetPoint("RIGHT", -3, 0)
  clearBtn:SetNormalTexture("Interface/Buttons/UI-StopButton")
  clearBtn:SetAlpha(0.5)
  clearBtn:Hide()
  clearBtn:SetScript("OnClick", function() box:SetText(""); box:ClearFocus() end)
  clearBtn:SetScript("OnEnter", function(s) s:SetAlpha(1) end)
  clearBtn:SetScript("OnLeave", function(s) s:SetAlpha(0.5) end)
  box._clearBtn = clearBtn

  box:SetScript("OnTextChanged", function(self)
    local t = self:GetText() or ""
    ph:SetShown(t == "")
    clearBtn:SetShown(t ~= "")
    if self._onChanged then self._onChanged(t) end
  end)
  box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return box
end
