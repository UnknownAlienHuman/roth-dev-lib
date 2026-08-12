-- !RothDevLib/UI/MainFrame.lua
-- v3 rewrite: Proper Blizzard ButtonFrameTemplate with native tabs, portrait, inset.
-- No more "dark box" — real WoW dialog that players expect.

local RDL = _G.RothDevLib
RDL.UI = RDL.UI or {}
local UI = RDL.UI

local Skin -- resolved after UI.Skin is set

UI.isOpen = false
UI.selectedSig = nil
UI._lastSeenCount = 0

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

function UI:GetUnreadCount()
  local total = RDL.DB and RDL.DB:GetGroupCount() or 0
  local seen = self._lastSeenCount or 0
  return math.max(0, total - seen)
end

local function AddonFromSrcUI(src)
  if not src then return nil end
  src = tostring(src):gsub("^@", "")
  return src:match("Interface[/\\]AddOns[/\\]([^/\\]+)[/\\]") or src:match("AddOns[/\\]([^/\\]+)[/\\]")
end

---------------------------------------------------------------------------
-- Mode constants
---------------------------------------------------------------------------
local MODE_ERRORS  = "errors"
local MODE_MONITOR = "monitor"
local MODE_LOG     = "log"

local TAB_INDEX    = { [MODE_ERRORS] = 1, [MODE_MONITOR] = 2, [MODE_LOG] = 3 }
local TAB_MODE     = { MODE_ERRORS, MODE_MONITOR, MODE_LOG }

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
function UI:Init()
  Skin = UI.Skin
  if not Skin or not Skin.C then
    error("RothDevLib: Skin.lua must load before MainFrame.lua")
  end

  local C = Skin.C

  -----------------------------------------------------------------------
  -- Main frame: ButtonFrameTemplate — USE IT PROPERLY!
  -----------------------------------------------------------------------
  local f
  local usedButtonFrame = false
  do
    local ok = pcall(function()
      f = CreateFrame("Frame", "RothDevLibMainFrame", UIParent, "ButtonFrameTemplate")
      usedButtonFrame = true
    end)
    if not ok or not f then
      f = CreateFrame("Frame", "RothDevLibMainFrame", UIParent, "BackdropTemplate")
      usedButtonFrame = false
    end
  end

  self.frame = f
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetToplevel(true)
  f:SetMovable(true)
  f:EnableMouse(true)

  -- Restore size/position
  if Skin.RestoreFrameState then
    Skin:RestoreFrameState("main", f, 980, 640)
  else
    f:SetSize(980, 640)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  if Skin.AttachFrameStateHandlers then
    Skin:AttachFrameStateHandlers("main", f)
  end

  -----------------------------------------------------------------------
  -- Configure ButtonFrameTemplate elements (DON'T HIDE THEM!)
  -----------------------------------------------------------------------
  if usedButtonFrame then
    -- Portrait: set our bug icon
    if f.PortraitContainer and f.PortraitContainer.portrait then
      f.PortraitContainer.portrait:SetTexture("Interface\\AddOns\\!RothDevLib\\Media\\bug")
    elseif f.portrait then
      f.portrait:SetTexture("Interface\\AddOns\\!RothDevLib\\Media\\bug")
    elseif SetPortraitToTexture then
      pcall(function()
        local portrait = f.PortraitContainer and f.PortraitContainer.portrait or f.portrait
        if portrait then
          portrait:SetTexture("Interface\\AddOns\\!RothDevLib\\Media\\bug")
        end
      end)
    end

    -- Title
    if f.TitleContainer and f.TitleContainer.TitleText then
      f.TitleContainer.TitleText:SetText("RothDevLib " .. (RDL.version or ""))
    elseif f.TitleText then
      f.TitleText:SetText("RothDevLib " .. (RDL.version or ""))
    end

    -- Close button
    if f.CloseButton then
      f.CloseButton:SetScript("OnClick", function() UI:Toggle() end)
    end
  else
    -- Fallback: manual title/close for non-ButtonFrame
    Skin:ApplyWindow(f)

    local titleFs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleFs:SetPoint("TOP", f, "TOP", 0, -8)
    titleFs:SetText("RothDevLib " .. (RDL.version or ""))
    titleFs:SetTextColor(1, 0.82, 0)
    self._titleFs = titleFs

    local closeBtn = Skin:StyledButton(f, "X", 24, 22)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    closeBtn:SetScript("OnClick", function() UI:Toggle() end)
  end

  -----------------------------------------------------------------------
  -- Drag support (title area)
  -----------------------------------------------------------------------
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if Skin and Skin.SaveFrameState then pcall(function() Skin:SaveFrameState("main", self) end) end
  end)

  -----------------------------------------------------------------------
  -- Resize grip
  -----------------------------------------------------------------------
  do
    local resizeBtn
    local ok = pcall(function()
      resizeBtn = CreateFrame("Button", nil, f, "PanelResizeButtonTemplate")
    end)
    if ok and resizeBtn then
      f:SetResizable(true)
      if f.SetMinResize then f:SetMinResize(820, 520) end
      resizeBtn:ClearAllPoints()
      resizeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
      resizeBtn:SetFrameLevel((f:GetFrameLevel() or 0) + 20)
      self._resizeBtn = resizeBtn
    elseif Skin.CreateResizeGrip then
      Skin:CreateResizeGrip(f, 820, 520)
    end
  end

  f:Hide()

  -----------------------------------------------------------------------
  -- Status line (below title, above tabs — shows handler info)
  -----------------------------------------------------------------------
  local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  if usedButtonFrame and f.Inset then
    statusText:SetPoint("TOPLEFT", f, "TOPLEFT", 64, -24)
    statusText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -24)
  else
    statusText:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -28)
    statusText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -28)
  end
  statusText:SetJustifyH("LEFT")
  statusText:SetWordWrap(false)
  self.status = statusText

  -----------------------------------------------------------------------
  -- Blizzard-style PanelTab tabs (Errors / Monitor / Log)
  -----------------------------------------------------------------------
  local TAB_TEXTS = { "Errors", "Monitor", "Log" }

  for i, tabText in ipairs(TAB_TEXTS) do
    local tabName = "RothDevLibMainFrameTab" .. i
    local tab
    local ok = pcall(function()
      tab = CreateFrame("Button", tabName, f, "CharacterFrameTabButtonTemplate")
    end)
    if not ok or not tab then
      ok = pcall(function()
        tab = CreateFrame("Button", tabName, f, "PanelTabButtonTemplate")
      end)
    end
    if ok and tab then
      tab:SetID(i)
      tab:SetText(tabText)
      if i == 1 then
        tab:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, -30)
      else
        tab:SetPoint("LEFT", _G["RothDevLibMainFrameTab" .. (i - 1)], "RIGHT", -14, 0)
      end
      tab:SetScript("OnClick", function(btn)
        local idx = btn:GetID()
        local mode = TAB_MODE[idx]
        if mode and self._setMode then self._setMode(mode) end
      end)
      if PanelTemplates_TabResize then
        pcall(function() PanelTemplates_TabResize(tab, 0) end)
      end
    end
  end

  if PanelTemplates_SetNumTabs then
    pcall(function() PanelTemplates_SetNumTabs(f, #TAB_TEXTS) end)
  end

  -- Badge on Errors tab
  local errTab = _G["RothDevLibMainFrameTab1"]
  if errTab then
    local badge = errTab:CreateFontString(nil, "OVERLAY")
    badge:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    badge:SetPoint("RIGHT", errTab, "RIGHT", -10, 2)
    badge:SetTextColor(1, 0.3, 0.3, 1)
    badge:Hide()
    self._tabErrorsBadge = badge
  end

  -----------------------------------------------------------------------
  -- Content anchor: use ButtonFrameTemplate's Inset
  -----------------------------------------------------------------------
  local contentParent = f
  local contentInsetL, contentInsetR, contentInsetT, contentInsetB = 4, -4, -60, 4

  if usedButtonFrame and f.Inset then
    contentParent = f.Inset
    contentInsetL, contentInsetR, contentInsetT, contentInsetB = 0, 0, 0, 0
  end

  -----------------------------------------------------------------------
  -- Search box (top-right, inside content area)
  -----------------------------------------------------------------------
  local searchBox
  do
    local ok = pcall(function()
      searchBox = CreateFrame("EditBox", nil, f, "SearchBoxTemplate")
    end)
    if ok and searchBox then
      searchBox:SetSize(200, 20)
      searchBox:SetPoint("TOPRIGHT", contentParent, "TOPRIGHT", -8, -4)
      searchBox:SetAutoFocus(false)
      if searchBox.Instructions and searchBox.Instructions.SetText then
        searchBox.Instructions:SetText("Search...")
      end
      searchBox:SetScript("OnTextChanged", function(self)
        if SearchBoxTemplate_OnTextChanged then
          pcall(SearchBoxTemplate_OnTextChanged, self)
        end
        local t = self:GetText() or ""
        if self._onChanged then self._onChanged(t) end
      end)
      searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText(""); self:ClearFocus()
      end)
      searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    else
      searchBox = Skin:SearchBox(f, 200, 20)
      searchBox:SetPoint("TOPRIGHT", contentParent, "TOPRIGHT", -8, -4)
    end
  end
  self._searchBox = searchBox

  -----------------------------------------------------------------------
  -- Status bar (bottom of content area: summary + action buttons)
  -----------------------------------------------------------------------
  local STATUS_H = 30

  local statusBar = CreateFrame("Frame", nil, contentParent, "BackdropTemplate")
  statusBar:SetHeight(STATUS_H)
  statusBar:SetPoint("BOTTOMLEFT", contentParent, "BOTTOMLEFT", contentInsetL, contentInsetB)
  statusBar:SetPoint("BOTTOMRIGHT", contentParent, "BOTTOMRIGHT", contentInsetR, contentInsetB)
  Skin:DarkInset(statusBar)
  self._statusBar = statusBar

  -- Summary text
  local summaryText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  summaryText:SetPoint("LEFT", statusBar, "LEFT", 10, 0)
  summaryText:SetTextColor(unpack(C.textDim))
  self._summaryText = summaryText

  -- Action buttons (right side — proper Blizzard style)
  local btnClear = Skin:StyledButton(statusBar, "Clear All", 80, 22)
  btnClear:SetPoint("RIGHT", statusBar, "RIGHT", -8, 0)
  btnClear:SetScript("OnClick", function()
    if RDL.DB then RDL.DB:Clear() end
    UI.selectedSig = nil
    UI:Refresh()
  end)

  local btnIgnoreAddon = Skin:StyledButton(statusBar, "Ignore Addon", 110, 22)
  btnIgnoreAddon:SetPoint("RIGHT", btnClear, "LEFT", -4, 0)
  btnIgnoreAddon:SetScript("OnClick", function()
    if UI and UI.ToggleIgnoreAddon then UI:ToggleIgnoreAddon(nil) end
  end)
  self.btnIgnoreAddon = btnIgnoreAddon

  local btnIgnoreSig = Skin:StyledButton(statusBar, "Ignore Sig", 100, 22)
  btnIgnoreSig:SetPoint("RIGHT", btnIgnoreAddon, "LEFT", -4, 0)
  btnIgnoreSig:SetScript("OnClick", function()
    if UI and UI.ToggleIgnoreSig then UI:ToggleIgnoreSig(UI.selectedSig) end
  end)
  self.btnIgnoreSig = btnIgnoreSig

  local btnExport = Skin:StyledButton(statusBar, "Export", 80, 22)
  btnExport:SetPoint("RIGHT", btnIgnoreSig, "LEFT", -4, 0)

  local exportDD = CreateFrame("Frame", "RothDevLibExportDropDown", f, "UIDropDownMenuTemplate")
  if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton then
    UIDropDownMenu_Initialize(exportDD, function(_, level)
      local info = UIDropDownMenu_CreateInfo()
      info.notCheckable = true

      info.text = "Export All"
      info.func = function() if UI.OpenExportAll then UI:OpenExportAll() end end
      UIDropDownMenu_AddButton(info, level)

      info.text = "Export Selected"
      info.func = function() if UI.OpenExportSelected then UI:OpenExportSelected() end end
      UIDropDownMenu_AddButton(info, level)

      info.text = "GitHub Issue (Selected)"
      info.func = function() if UI.OpenExportGitHub then UI:OpenExportGitHub(UI.selectedSig) end end
      UIDropDownMenu_AddButton(info, level)

      info.text = "Validation Checklist"
      info.func = function() if UI.OpenValidationChecklist then UI:OpenValidationChecklist() end end
      UIDropDownMenu_AddButton(info, level)

      info.text = "Export JSON"
      info.func = function() if UI.OpenExportJSON then UI:OpenExportJSON() end end
      UIDropDownMenu_AddButton(info, level)

      info.text = "Pack (LLM)"
      info.func = function() if UI.OpenExportPacked then UI:OpenExportPacked() end end
      UIDropDownMenu_AddButton(info, level)
    end, "MENU")
  end
  btnExport:SetScript("OnClick", function()
    if ToggleDropDownMenu then
      ToggleDropDownMenu(1, nil, exportDD, btnExport, 0, 0)
    elseif UI.OpenExportAll then
      UI:OpenExportAll()
    end
  end)

  -----------------------------------------------------------------------
  -- Content areas (3 modes, anchored above status bar)
  -----------------------------------------------------------------------
  -- ERRORS: left panel (GroupGrid) + splitter + right panel (DetailView)
  local contentErrors = CreateFrame("Frame", nil, contentParent)
  contentErrors:SetPoint("TOPLEFT", contentParent, "TOPLEFT", contentInsetL, contentInsetT)
  contentErrors:SetPoint("BOTTOMRIGHT", statusBar, "TOPRIGHT", contentInsetR, 0)
  self._contentErrors = contentErrors

  -- MONITOR
  local contentMonitor = CreateFrame("Frame", nil, contentParent)
  contentMonitor:SetPoint("TOPLEFT", contentParent, "TOPLEFT", contentInsetL, contentInsetT)
  contentMonitor:SetPoint("BOTTOMRIGHT", statusBar, "TOPRIGHT", contentInsetR, 0)
  contentMonitor:Hide()
  self._contentMonitor = contentMonitor
  self._monitorBuilt = false

  -- LOG
  local contentLog = CreateFrame("Frame", nil, contentParent, "BackdropTemplate")
  contentLog:SetPoint("TOPLEFT", contentParent, "TOPLEFT", contentInsetL, contentInsetT)
  contentLog:SetPoint("BOTTOMRIGHT", statusBar, "TOPRIGHT", contentInsetR, 0)
  Skin:DarkInset(contentLog)
  contentLog:Hide()
  self._contentLog = contentLog

  local logScroll = CreateFrame("ScrollFrame", nil, contentLog, "UIPanelScrollFrameTemplate")
  logScroll:SetPoint("TOPLEFT", 8, -8)
  logScroll:SetPoint("BOTTOMRIGHT", -28, 8)

  local logEdit = CreateFrame("EditBox", nil, logScroll)
  logEdit:SetMultiLine(true)
  logEdit:SetAutoFocus(false)
  logEdit:SetFontObject(ChatFontNormal)
  logEdit:SetTextColor(unpack(C.text))
  logEdit:SetScript("OnEscapePressed", function() logEdit:ClearFocus() end)
  logEdit:SetText("")
  logScroll:SetScrollChild(logEdit)
  self._logEdit = logEdit

  local function UpdateLogWidth()
    local w = (contentLog:GetWidth() or 800) - 60
    if w < 300 then w = 300 end
    logEdit:SetWidth(w)
  end
  UpdateLogWidth()
  contentLog:HookScript("OnSizeChanged", UpdateLogWidth)

  local btnLogRefresh = Skin:StyledButton(contentLog, "Refresh", 80, 22)
  btnLogRefresh:SetPoint("TOPRIGHT", contentLog, "TOPRIGHT", -32, -4)
  btnLogRefresh:SetScript("OnClick", function() UI:RefreshLogContent() end)

  -----------------------------------------------------------------------
  -- Errors: GroupGrid (left) + Splitter + DetailView (right)
  -----------------------------------------------------------------------
  local PADDING = 4

  local listFrame = CreateFrame("Frame", nil, contentErrors, "BackdropTemplate")
  Skin:DarkInset(listFrame)
  self.listFrame = listFrame

  local detailFrame = CreateFrame("Frame", "RothDevLibDetailFrame", contentErrors, "BackdropTemplate")
  Skin:DarkInset(detailFrame)
  self.detailFrame = detailFrame

  -- Splitter
  local splitterW = 6
  local splitter = CreateFrame("Button", nil, contentErrors, "BackdropTemplate")
  splitter:SetWidth(splitterW)
  splitter:EnableMouse(true)
  splitter:SetFrameStrata("HIGH")
  splitter:SetBackdrop(Skin.BD.flat)
  splitter:SetBackdropColor(unpack(C.splitter))
  splitter:SetAlpha(0.5)
  self.mainSplitter = splitter

  if splitter.SetHitRectInsets then
    splitter:SetHitRectInsets(-6, -6, 0, 0)
  end

  -- Splitter center line
  local splitLine = splitter:CreateTexture(nil, "ARTWORK")
  splitLine:SetPoint("TOP", splitter, "TOP", 0, 0)
  splitLine:SetPoint("BOTTOM", splitter, "BOTTOM", 0, 0)
  splitLine:SetWidth(2)
  splitLine:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.8)
  splitter._line = splitLine

  local splitterDragging = false

  local function SplitterSetStyle(state)
    if state == "clamp" then
      splitter:SetBackdropColor(C.warning[1], C.warning[2], C.warning[3], 1)
      splitter._line:SetColorTexture(C.warning[1], C.warning[2], C.warning[3], 1)
      splitter:SetAlpha(1)
    elseif state == "drag" or state == "hover" then
      splitter:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 1)
      splitter._line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
      splitter:SetAlpha(1)
    else
      splitter:SetBackdropColor(unpack(C.splitter))
      splitter._line:SetColorTexture(C.border[1], C.border[2], C.border[3], 0.8)
      splitter:SetAlpha(0.5)
    end
  end

  splitter:SetScript("OnEnter", function()
    SplitterSetStyle("hover")
    if GameTooltip then
      GameTooltip:SetOwner(splitter, "ANCHOR_CURSOR")
      GameTooltip:AddLine("Drag to resize panels", 0.9, 0.9, 0.9, true)
      GameTooltip:Show()
    end
  end)
  splitter:SetScript("OnLeave", function()
    if GameTooltip and GameTooltip:IsOwned(splitter) then GameTooltip:Hide() end
    if not splitterDragging then SplitterSetStyle("idle") end
  end)

  -- Pane state
  local paneState = (Skin.GetPaneState and Skin:GetPaneState("mainShell")) or {}
  local splitRatio = Clamp(tonumber(paneState.splitRatio) or 0.42, 0.22, 0.70)
  local activeMode = paneState.activeMode or MODE_ERRORS

  local function SavePaneState()
    if Skin and Skin.SavePaneState then
      Skin:SavePaneState("mainShell", { splitRatio = splitRatio, activeMode = activeMode })
    end
  end

  -----------------------------------------------------------------------
  -- Layout engine
  -----------------------------------------------------------------------
  local function ApplyErrorsLayout()
    local w = contentErrors:GetWidth() or 800
    local listW = Clamp(math.floor(w * splitRatio + 0.5), 280, w - 300)
    splitRatio = Clamp(listW / math.max(w, 1), 0.22, 0.70)

    listFrame:ClearAllPoints()
    listFrame:SetPoint("TOPLEFT", contentErrors, "TOPLEFT", PADDING, -PADDING)
    listFrame:SetPoint("BOTTOMLEFT", contentErrors, "BOTTOMLEFT", PADDING, PADDING)
    listFrame:SetWidth(listW)

    splitter:ClearAllPoints()
    splitter:SetPoint("TOPLEFT", listFrame, "TOPRIGHT", 0, 0)
    splitter:SetPoint("BOTTOMLEFT", listFrame, "BOTTOMRIGHT", 0, 0)

    detailFrame:ClearAllPoints()
    detailFrame:SetPoint("TOPLEFT", splitter, "TOPRIGHT", 0, 0)
    detailFrame:SetPoint("BOTTOMRIGHT", contentErrors, "BOTTOMRIGHT", -PADDING, PADDING)

    if UI and UI.RequestGroupGridLayout then UI:RequestGroupGridLayout("reflow") end
  end

  contentErrors:SetScript("OnSizeChanged", function() ApplyErrorsLayout() end)

  -- Splitter drag
  local function StopSplitDrag(save)
    if not splitterDragging then return end
    splitterDragging = false
    splitter:SetScript("OnUpdate", nil)
    SplitterSetStyle("idle")
    if save then SavePaneState() end
  end

  local function UpdateSplitFromCursor()
    local scale = (f:GetEffectiveScale()) or 1
    if scale <= 0 then scale = 1 end
    local cx = GetCursorPosition()
    local left = contentErrors:GetLeft()
    if not cx or not left then return end
    local w = contentErrors:GetWidth() or 800
    local target = (cx / scale) - left - PADDING
    local minW, maxW = 280, (w - 300)
    local unclamped = target
    target = Clamp(target, minW, maxW)
    splitRatio = Clamp(target / math.max(w, 1), 0.22, 0.70)
    SplitterSetStyle(target ~= unclamped and "clamp" or "drag")
    ApplyErrorsLayout()
  end

  splitter:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" then return end
    splitterDragging = true
    SplitterSetStyle("drag")
    splitter:SetScript("OnUpdate", UpdateSplitFromCursor)
  end)
  splitter:SetScript("OnMouseUp", function() StopSplitDrag(true) end)
  splitter:SetScript("OnHide", function() StopSplitDrag(true) end)

  -----------------------------------------------------------------------
  -- Mode switching
  -----------------------------------------------------------------------
  local function SetMode(mode)
    activeMode = mode
    contentErrors:SetShown(mode == MODE_ERRORS)
    contentMonitor:SetShown(mode == MODE_MONITOR)
    contentLog:SetShown(mode == MODE_LOG)

    -- Blizzard tab selection
    local tabIdx = TAB_INDEX[mode] or 1
    if PanelTemplates_SetTab then
      pcall(function() PanelTemplates_SetTab(f, tabIdx) end)
    end

    -- Show/hide status bar buttons per mode
    btnIgnoreSig:SetShown(mode == MODE_ERRORS)
    btnIgnoreAddon:SetShown(mode == MODE_ERRORS)
    btnExport:SetShown(mode == MODE_ERRORS)
    if self._searchBox then self._searchBox:SetShown(mode == MODE_ERRORS) end

    if mode == MODE_ERRORS then
      ApplyErrorsLayout()
      if UI.StopMonitorEmbedTicker then UI:StopMonitorEmbedTicker() end
    elseif mode == MODE_MONITOR then
      if not UI._monitorBuilt then
        if UI.BuildMonitorContent then pcall(function() UI:BuildMonitorContent(contentMonitor) end) end
        UI._monitorBuilt = true
      end
      if UI.RefreshMonitor then pcall(function() UI:RefreshMonitor() end) end
      if UI.StartMonitorEmbedTicker then UI:StartMonitorEmbedTicker() end
    elseif mode == MODE_LOG then
      UI:RefreshLogContent()
      if UI.StopMonitorEmbedTicker then UI:StopMonitorEmbedTicker() end
    end

    SavePaneState()
  end
  self._setMode = SetMode

  -----------------------------------------------------------------------
  -- Search box wiring
  -----------------------------------------------------------------------
  searchBox._onChanged = function(text)
    if UI.groupGrid then
      UI.groupGrid.query = text or ""
      if UI.RequestRefresh then UI:RequestRefresh("search") end
    end
  end

  -----------------------------------------------------------------------
  -- Initial layout
  -----------------------------------------------------------------------
  ApplyErrorsLayout()

  -- Init submodules
  if self.InitGroupGrid then pcall(function() self:InitGroupGrid(listFrame) end) end
  if self.InitDetailView then pcall(function() self:InitDetailView(detailFrame) end) end

  -----------------------------------------------------------------------
  -- Frame hooks
  -----------------------------------------------------------------------
  f:HookScript("OnSizeChanged", function()
    if activeMode == MODE_ERRORS then ApplyErrorsLayout() end
  end)

  f:HookScript("OnHide", function()
    StopSplitDrag(false)
    SavePaneState()
    if Skin and Skin.SaveFrameState then Skin:SaveFrameState("main", f) end
  end)

  -- Apply initial mode + select tab
  SetMode(activeMode)
  self:Refresh()

  -----------------------------------------------------------------------
  -- Live updates
  -----------------------------------------------------------------------
  if type(RDL.RegisterCallback) == "function" then
    RDL:RegisterCallback("RDL_CAPTURE", "RDL_UI", function(entry, group)
      if not UI or type(UI.OnNewEntry) ~= "function" then return end
      if UI._liveDisabled then return end
      local ok, err = pcall(UI.OnNewEntry, UI, entry, group)
      if not ok then
        UI._liveDisabled = true
        UI._lastUIError = tostring(err)
        UI._lastUIErrorTs = time()
        if RDL and RDL.Log then
          pcall(function() RDL:Log("ERROR", "UI", "UI live updates disabled", { err = err }) end)
        end
      end
    end)
  end
end

---------------------------------------------------------------------------
-- Refresh Log
---------------------------------------------------------------------------
function UI:RefreshLogContent()
  if not self._logEdit then return end
  local logText = (RDL.Logger and RDL.Logger.GetText and RDL.Logger:GetText()) or ""
  if logText == "" then logText = "(no log lines)\n\nUse /rdev log to view in export window." end
  self._logEdit:SetText(logText)
  self._logEdit:SetCursorPosition(#logText)
  self._logEdit:ClearFocus()
end

---------------------------------------------------------------------------
-- Update title + status (compact — detailed info goes to tooltip)
---------------------------------------------------------------------------
function UI:UpdateTitle()
  if not self.frame then return end

  local cap = RDL.Capture
  if cap and cap.SyncOwnership then pcall(function() cap:SyncOwnership("ui") end) end

  local isOwned = (cap and cap.ownsHandler) and true or false

  if cap and cap.ProbeSetErrorHandler and (not isOwned) then
    local now = GetTime and GetTime() or 0
    if not self._lastSetEHProbeAt or (now - self._lastSetEHProbeAt) > 2.0 then
      self._lastSetEHProbeAt = now
      pcall(function() cap:ProbeSetErrorHandler() end)
    end
  end

  -- Compact status line
  if self.status then
    local col = isOwned and "|cff66ff66" or "|cffffaa33"
    local owned = isOwned and "owned" or "not owned"
    local st = col .. "ErrorHandler: " .. owned .. "|r"

    -- Fallback chain (compact)
    local fb = cap and cap._fallback or nil
    if fb then
      local t = {}
      if fb.scriptErrorsHooked then t[#t + 1] = "ScriptErrors" end
      if fb.blizzardLuaHandlerHooked then t[#t + 1] = "AddLua" end
      if fb.scriptErrorsFrameSyncEnabled then t[#t + 1] = "ScriptSync" end
      if fb.bugGrabberEnabled then t[#t + 1] = "BugGrabber" end
      if fb.chatTapHooked then t[#t + 1] = "ChatTap" end
      if #t > 0 then st = st .. "  |cff888888+" .. table.concat(t, "+") .. "|r" end
    end

    local unread = 0
    if self.GetUnreadCount then
      local ok, n = pcall(function() return self:GetUnreadCount() end)
      if ok then unread = tonumber(n) or 0 end
    end
    if unread > 0 then st = st .. "  |cffff6666+" .. tostring(unread) .. " new|r" end

    self.status:SetText(st)
  end

  -- Update window title
  local tf = self.frame.TitleContainer and self.frame.TitleContainer.TitleText or self.frame.TitleText or self._titleFs
  if tf then
    tf:SetText("RothDevLib " .. (RDL.version or ""))
  end
end

---------------------------------------------------------------------------
-- Update summary + badge
---------------------------------------------------------------------------
function UI:UpdateSummary()
  if not self._summaryText then return end
  local totalGroups = (RDL.DB and RDL.DB.GetGroupCount and RDL.DB:GetGroupCount()) or 0
  local totalOccurrences = 0
  if RDL.DB and RDL.DB.IterGroups then
    for _, g in RDL.DB:IterGroups() do
      totalOccurrences = totalOccurrences + (tonumber(g and g.count) or 0)
    end
  end
  self._summaryText:SetText(string.format("%d groups, %d occurrences", totalGroups, totalOccurrences))

  -- Tab badge
  if self._tabErrorsBadge then
    if totalGroups > 0 then
      self._tabErrorsBadge:SetText(tostring(totalGroups))
      self._tabErrorsBadge:Show()
    else
      self._tabErrorsBadge:Hide()
    end
  end
end

---------------------------------------------------------------------------
-- Ignore buttons
---------------------------------------------------------------------------
function UI:UpdateIgnoreButtons()
  if not self.btnIgnoreSig or not self.btnIgnoreAddon then return end
  local sig = self.selectedSig
  if not sig or not RDL.DB or not RDL.DB.raw then
    self.btnIgnoreSig:SetText("Ignore Sig")
    self.btnIgnoreAddon:SetText("Ignore Addon")
    return
  end
  local ig = RDL.DB.raw.ignore or { sig = {}, addon = {} }
  local isSig = ig.sig and ig.sig[sig] and true or false
  self.btnIgnoreSig:SetText(isSig and "Unignore Sig" or "Ignore Sig")
  local g = RDL.DB:GetGroup(sig)
  local addonName = g and g.addon or nil
  local isAddon = addonName and ig.addon and ig.addon[addonName] and true or false
  self.btnIgnoreAddon:SetText(isAddon and "Unignore Addon" or "Ignore Addon")
end

function UI:ToggleIgnoreSig(sig)
  sig = sig or self.selectedSig
  if not sig or not RDL.DB or not RDL.DB.ToggleIgnoreSig then return nil end
  local state = RDL.DB:ToggleIgnoreSig(sig)
  if self.RequestRefresh then self:RequestRefresh("ignore-sig") else self:Refresh() end
  print(state and ("|cffffff00RothDevLib|r ignoring sig: " .. tostring(sig))
    or ("|cffffff00RothDevLib|r un-ignored sig: " .. tostring(sig)))
  return state
end

function UI:ToggleIgnoreAddon(addonName)
  if (addonName == nil or addonName == "") and self.selectedSig and RDL.DB and RDL.DB.GetGroup then
    local g = RDL.DB:GetGroup(self.selectedSig)
    addonName = g and g.addon or nil
  end
  if not addonName or addonName == "" or not RDL.DB or not RDL.DB.ToggleIgnoreAddon then return nil end
  local state = RDL.DB:ToggleIgnoreAddon(addonName)
  if self.RequestRefresh then self:RequestRefresh("ignore-addon") else self:Refresh() end
  print(state and ("|cffffff00RothDevLib|r ignoring addon: " .. tostring(addonName))
    or ("|cffffff00RothDevLib|r un-ignored addon: " .. tostring(addonName)))
  return state
end

---------------------------------------------------------------------------
-- Throttled Refresh
---------------------------------------------------------------------------
function UI:RequestRefresh(reason)
  if not self.frame then return end
  local settings = (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or {}
  local delay = tonumber(settings.uiRefreshThrottleSec) or 0
  if delay <= 0 or not C_Timer or type(C_Timer.After) ~= "function" then
    return self:Refresh()
  end
  if self._refreshPending then
    self._refreshPendingReason = self._refreshPendingReason or reason
    return
  end
  self._refreshPending = true
  self._refreshPendingReason = reason
  C_Timer.After(delay, function()
    if not UI then return end
    UI._refreshPending = false
    UI._refreshPendingReason = nil
    if UI.frame then UI:Refresh() end
  end)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
function UI:Refresh()
  if not self.frame then return end
  local ok, err = pcall(function()
    if self.UpdateGroupGrid then self:UpdateGroupGrid() end
    local autoSelected = false
    if (not self.selectedSig) and self.groupGrid and type(self.groupGrid._groups) == "table" then
      local first = self.groupGrid._groups[1]
      local firstSig = first and (first.sig or first._sig) or nil
      if firstSig and firstSig ~= "" then
        self.selectedSig = firstSig
        autoSelected = true
      end
    end
    if self.selectedSig and RDL.DB and RDL.DB:GetGroup(self.selectedSig) then
      if self.UpdateDetailView then
        self:UpdateDetailView(self.selectedSig)
      elseif self.ShowGroup then
        self:ShowGroup(self.selectedSig)
      end
    else
      self.selectedSig = nil
      if self.SetDetailPlaceholder then
        self:SetDetailPlaceholder("No entries.\n\nTry: /rdev test alert\nTry: /rdev diag")
      end
    end
    if autoSelected and self.UpdateGroupGrid then self:UpdateGroupGrid() end
    if self.UpdateIgnoreButtons then self:UpdateIgnoreButtons() end
    if self.UpdateTitle then self:UpdateTitle() end
    if self.UpdateSummary then self:UpdateSummary() end
    if self.UpdateMinimapIconState then self:UpdateMinimapIconState() end
  end)
  if not ok then
    self._refreshError = tostring(err)
    self._refreshErrorTs = time()
    local now = time()
    local e = tostring(err)
    if (self._lastRefreshReportTs == nil) or (now - (self._lastRefreshReportTs or 0) > 2) or (e ~= self._lastRefreshReportErr) then
      self._lastRefreshReportTs = now
      self._lastRefreshReportErr = e
      if RDL and RDL.ReportError then
        pcall(function()
          RDL:ReportError(RDL.addonName, "UI refresh failed: " .. e, {
            func = "UI:Refresh",
            tag = "internal-ui",
            stack = debugstack(2, 40, 40),
            internal = true,
          })
        end)
      end
    end
    if RDL and RDL.Log then
      pcall(function() RDL:Log("ERROR", "UI", "Refresh failed", { err = err }) end)
    end
    if self.SetDetailPlaceholder then
      self:SetDetailPlaceholder("RothDevLib UI refresh failed:\n" .. tostring(err) .. "\n\nUse /rdev diag")
    end
  end
end

---------------------------------------------------------------------------
-- Show/Toggle/Open
---------------------------------------------------------------------------
function UI:ShowGroup(sig)
  if not sig then return end
  self.selectedSig = sig
  if self.UpdateDetailView then self:UpdateDetailView(sig) end
  if self.UpdateIgnoreButtons then self:UpdateIgnoreButtons() end
end

function UI:MarkAllRead()
  self._lastSeenCount = RDL.DB and RDL.DB:GetGroupCount() or 0
end

function UI:Toggle()
  if not self.frame then return end
  if self.frame:IsShown() then
    self.frame:Hide()
    self.isOpen = false
    if self.StopMonitorEmbedTicker then self:StopMonitorEmbedTicker() end
  else
    self.frame:Show()
    self.isOpen = true
    self:MarkAllRead()
    self:Refresh()
  end
end

function UI:Open()
  if not self.frame and self.Init then pcall(function() self:Init() end) end
  if not self.frame then return end
  if not self.frame:IsShown() then
    self.frame:Show()
    self.isOpen = true
    self:MarkAllRead()
    self:Refresh()
  end
end

function UI:OpenToSig(sig)
  self:Open()
  if not sig or sig == "" then return end
  self.selectedSig = sig
  if self._setMode then self._setMode(MODE_ERRORS) end
  if self.ShowGroup then pcall(function() self:ShowGroup(sig) end) end
  if self.RequestRefresh then
    pcall(function() self:RequestRefresh("open-to-sig") end)
  else
    self:Refresh()
  end
end

function UI:OnNewEntry(entry, group)
  if self._liveDisabled then return end
  local settings = RDL.DB and RDL.DB:GetSettings() or {}
  if settings.openOnErrorOutOfCombat and self.frame and not self.frame:IsShown() and not UnitAffectingCombat("player") then
    self:Toggle()
  end
  if self.frame and self.frame:IsShown() then
    if self.RequestRefresh then self:RequestRefresh("capture") else self:Refresh() end
  end
  if self.UpdateMinimapIconState then pcall(function() self:UpdateMinimapIconState() end) end
end

---------------------------------------------------------------------------
-- Export helpers
---------------------------------------------------------------------------
function UI:OpenExportAll()
  if not self.ShowExport or not self.BuildExportAllText then return end
  local text = self:BuildExportAllText({ includeOccurrences = true, includeLog = true })
  self:ShowExport("RothDevLib Export (All)", text)
end

function UI:OpenExportSelected()
  if not self.ShowExport or not self.BuildExportSelectedText then return end
  local sig = self.selectedSig
  if not sig then
    self:ShowExport("RothDevLib Export (Selected)", "No group selected.")
    return
  end
  local text = self:BuildExportSelectedText(sig, { includeOccurrences = true, includeLog = false })
  self:ShowExport("RothDevLib Export (Selected)", text)
end

function UI:OpenLog()
  if self._setMode then
    self._setMode(MODE_LOG); return
  end
  if not self.ShowExport then return end
  local logText = (RDL.Logger and RDL.Logger:GetText()) or ""
  self:ShowExport("RothDevLib Log", logText)
end
