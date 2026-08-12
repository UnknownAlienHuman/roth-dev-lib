-- !RothDevLib/UI/ExportFrame.lua
-- v3 rewrite: Blizzard-native dialog (ButtonFrameTemplate) for export/copy.
-- Logic unchanged. Only UI shell converted to proper Blizzard template.

local RDL = _G.RothDevLib
local UI = RDL.UI

function UI:EnsureExportFrame()
  if self.exportFrame then return end

  local Skin = UI.Skin
  local C = Skin and Skin.C

  ---------------------------------------------------------------------------
  -- Frame shell: ButtonFrameTemplate (native portrait + title + close)
  ---------------------------------------------------------------------------
  local f
  local usedButtonFrame = false
  do
    local ok = pcall(function()
      f = CreateFrame("Frame", "RothDevLibExportFrame", UIParent, "ButtonFrameTemplate")
      usedButtonFrame = true
    end)
    if not ok or not f then
      f = CreateFrame("Frame", "RothDevLibExportFrame", UIParent, "BackdropTemplate")
      usedButtonFrame = false
    end
  end

  self.exportFrame = f
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetToplevel(true)
  f:SetMovable(true)
  f:EnableMouse(true)

  if Skin and Skin.RestoreFrameState then
    Skin:RestoreFrameState("export", f, 980, 680)
  else
    f:SetSize(980, 680)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  if Skin and Skin.AttachFrameStateHandlers then
    Skin:AttachFrameStateHandlers("export", f)
  end
  f:Hide()

  if f.HookScript then
    f:HookScript("OnHide", function()
      if Skin and Skin.SaveFrameState then
        Skin:SaveFrameState("export", f)
      end
    end)
  end

  ---------------------------------------------------------------------------
  -- Configure ButtonFrameTemplate elements
  ---------------------------------------------------------------------------
  if usedButtonFrame then
    -- Portrait: clipboard/export icon
    if f.PortraitContainer and f.PortraitContainer.portrait then
      f.PortraitContainer.portrait:SetTexture("Interface\\AddOns\\!RothDevLib\\Media\\bug")
    elseif f.portrait then
      f.portrait:SetTexture("Interface\\AddOns\\!RothDevLib\\Media\\bug")
    end

    -- Title (will be updated per-export)
    local titleWidget = (f.TitleContainer and f.TitleContainer.TitleText) or f.TitleText
    if titleWidget then
      titleWidget:SetText("Export")
      self.exportTitle = titleWidget
    end

    -- Close button
    if f.CloseButton then
      f.CloseButton:SetScript("OnClick", function() f:Hide() end)
    end
  else
    -- Fallback: manual title/close
    if Skin and Skin.ApplyWindow then
      Skin:ApplyWindow(f)
    end

    local titleFs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("TOP", f, "TOP", 0, -8)
    titleFs:SetText("Export")
    titleFs:SetTextColor(1, 0.82, 0)
    self.exportTitle = titleFs

    local closeBtn
    if Skin and Skin.BlizzButton then
      closeBtn = Skin:BlizzButton(f, "X", 24, 22)
    else
      closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
      closeBtn:SetSize(24, 22)
      closeBtn:SetText("X")
    end
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
  end

  ---------------------------------------------------------------------------
  -- Drag support
  ---------------------------------------------------------------------------
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if Skin and Skin.SaveFrameState then
      pcall(function() Skin:SaveFrameState("export", self) end)
    end
  end)

  ---------------------------------------------------------------------------
  -- Resize grip
  ---------------------------------------------------------------------------
  do
    local resizeBtn
    local ok = pcall(function()
      resizeBtn = CreateFrame("Button", nil, f, "PanelResizeButtonTemplate")
    end)
    if ok and resizeBtn then
      f:SetResizable(true)
      if f.SetMinResize then f:SetMinResize(820, 560) end
      resizeBtn:ClearAllPoints()
      resizeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
      resizeBtn:SetFrameLevel((f:GetFrameLevel() or 0) + 20)
    elseif Skin and Skin.CreateResizeGrip then
      Skin:CreateResizeGrip(f, 820, 560)
    end
  end

  ---------------------------------------------------------------------------
  -- Bottom bar (action buttons)
  ---------------------------------------------------------------------------
  local BOTTOM_H = 36

  local bottomBar = CreateFrame("Frame", nil, f)
  bottomBar:SetHeight(BOTTOM_H)
  bottomBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  bottomBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

  local function MakeBtn(parent, text, w)
    if Skin and Skin.BlizzButton then
      return Skin:BlizzButton(parent, text, w, 22)
    else
      local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
      b:SetSize(w, 22)
      b:SetText(text)
      return b
    end
  end

  local btnSelectAll = MakeBtn(bottomBar, "Select All", 100)
  local btnCopy      = MakeBtn(bottomBar, "Copy (Ctrl+C)", 120)
  local btnClose     = MakeBtn(bottomBar, "Close", 80)

  btnSelectAll:SetPoint("LEFT", bottomBar, "LEFT", 12, 0)
  btnCopy:SetPoint("LEFT", btnSelectAll, "RIGHT", 6, 0)
  btnClose:SetPoint("RIGHT", bottomBar, "RIGHT", -12, 0)

  btnSelectAll:SetScript("OnClick", function()
    if self.exportEdit then
      self.exportEdit:SetFocus()
      self.exportEdit:HighlightText(0)
    end
  end)
  btnCopy:SetScript("OnClick", function()
    if self.exportEdit then
      self.exportEdit:SetFocus()
      self.exportEdit:HighlightText(0)
    end
  end)
  btnClose:SetScript("OnClick", function() f:Hide() end)

  ---------------------------------------------------------------------------
  -- Body (Blizzard inset + scroll + EditBox)
  ---------------------------------------------------------------------------
  local TOP_OFFSET = usedButtonFrame and 60 or 32

  local body = CreateFrame("Frame", nil, f, "BackdropTemplate")
  body:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -(TOP_OFFSET + 4))
  body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, BOTTOM_H + 2)
  if Skin and Skin.ApplyInset then
    Skin:ApplyInset(body)
  elseif Skin and Skin.DarkInset then
    Skin:DarkInset(body)
  end

  local scroll = CreateFrame("ScrollFrame", "RothDevLibExportScroll", body, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -30, 6)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(ChatFontNormal)
  edit:SetMaxLetters(99999)

  local function UpdateWidth()
    local w = (body.GetWidth and body:GetWidth() or 900) - 60
    if w < 420 then w = 420 end
    edit:SetWidth(w)
  end
  UpdateWidth()
  if body.HookScript then body:HookScript("OnSizeChanged", UpdateWidth) end

  edit:SetScript("OnEscapePressed", function() edit:ClearFocus() end)
  edit:SetText("")
  scroll:SetScrollChild(edit)

  self.exportEdit = edit
end

function UI:ShowExport(title, text)
  self:EnsureExportFrame()
  if self.exportTitle then
    if self.exportTitle.SetText then
      self.exportTitle:SetText(title or "Export")
    end
  end
  local U = RDL.Util
  local shown = text or ""
  if U and U.EscapePipes then
    shown = U:EscapePipes(shown)
  else
    shown = tostring(shown):gsub("|", "||")
  end
  self.exportFrame:Show()
  self.exportEdit:SetText(shown)
  self.exportEdit:SetCursorPosition(0)
  self.exportEdit:SetFocus()
  self.exportEdit:HighlightText(0)
end
