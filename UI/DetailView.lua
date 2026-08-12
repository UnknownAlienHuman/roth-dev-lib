-- !RothDevLib/UI/DetailView.lua
-- v3 rewrite: Blizzard-native styling for detail panel sub-tabs & buttons.
-- Logic unchanged from v2. Only UI creation uses Blizzard templates.

local RDL = _G.RothDevLib
RDL.UI = RDL.UI or {}
local UI = RDL.UI

local TAB_DEFS = {
  { key = "message", label = "Message" },
  { key = "stack",   label = "Stack" },
  { key = "locals",  label = "Locals" },
  { key = "doctor",  label = "Doctor" },
  { key = "occ",     label = "Occur" },
}

local function EscapeForEditBox(text)
  local U = RDL.Util
  local shown = text or ""
  if U and U.EscapePipes then
    shown = U:EscapePipes(shown)
  else
    shown = tostring(shown):gsub("|", "||")
  end
  return shown
end

local function SafeDate(ts)
  return date("%Y-%m-%d %H:%M:%S", ts or time())
end

local function BuildTabBadges(g)
  local badges = {
    message = 0, stack = 0, locals = 0, doctor = 0, occ = 0,
  }
  if type(g) ~= "table" then return badges end

  if tostring(g.message or "") ~= "" then badges.message = 1 end
  if tostring(g.stack or "") ~= "" then badges.stack = 1 end
  if tostring(g.locals or "") ~= "" then badges.locals = 1 end

  local doctor = 0
  if g.origin and (g.origin.file or g.origin.addon) then doctor = doctor + 1 end
  if g.ctx and g.ctx.top then doctor = doctor + 1 end
  if g.ctx and g.ctx.chain then doctor = doctor + 1 end
  if g.ctx and g.ctx.extra then doctor = doctor + 1 end
  if g.sys then doctor = doctor + 1 end
  if g.bus and g.bus.breadcrumbs and #g.bus.breadcrumbs > 0 then doctor = doctor + 1 end
  if g.bus and g.bus.metrics then doctor = doctor + 1 end
  badges.doctor = doctor

  local occ = g.occurrences
  if type(occ) == "table" then badges.occ = #occ end

  return badges
end

---------------------------------------------------------------------------
-- v3: Tab presentation — Blizzard toggle style
---------------------------------------------------------------------------
local function ApplyTabPresentation(dv, activeTab, badges)
  if not dv or not dv.tabButtons then return end
  activeTab = tonumber(activeTab) or 1

  for i, def in ipairs(dv.tabs or TAB_DEFS) do
    local tab = dv.tabButtons[i]
    if tab then
      local base = def.label or ""
      local n = badges and tonumber(badges[def.key]) or 0
      local text = base
      if n and n > 0 then
        text = string.format("%s (%d)", base, n)
      end
      tab:SetText(text)

      -- v3: visual active state
      local isActive = (i == activeTab)
      if tab.SetActive then
        tab:SetActive(isActive)
      end
      -- For Blizzard buttons: checked state
      if tab.SetChecked then
        tab:SetChecked(isActive)
      end
      -- Font emphasis
      if tab.SetNormalFontObject then
        tab:SetNormalFontObject(isActive and GameFontHighlightSmall or GameFontNormalSmall)
      end
    end
  end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
function UI:InitDetailView(detailFrame)
  if self.detailView or not detailFrame then return end

  local Skin = UI.Skin
  local C = Skin and Skin.C

  local dv = {}
  self.detailView = dv
  dv.frame = detailFrame
  dv.tabs = TAB_DEFS
  dv.occIndex = 1
  dv._lastOccFilter = ""
  dv._lastSig = nil

  self.detailTab = tonumber(self.detailTab) or 1
  if self.detailTab < 1 or self.detailTab > #TAB_DEFS then
    self.detailTab = 1
  end

  ---------------------------------------------------------------------------
  -- Header (signature + meta lines)
  ---------------------------------------------------------------------------
  local header = CreateFrame("Frame", nil, detailFrame)
  header:SetPoint("TOPLEFT", detailFrame, "TOPLEFT", 8, -8)
  header:SetPoint("TOPRIGHT", detailFrame, "TOPRIGHT", -8, -8)
  header:SetHeight(80)
  dv.header = header

  local sig = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  sig:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
  sig:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
  sig:SetJustifyH("LEFT")
  sig:SetJustifyV("TOP")
  sig:SetText("No selection")
  dv.sigText = sig

  local meta1 = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  meta1:SetPoint("TOPLEFT", sig, "BOTTOMLEFT", 0, -4)
  meta1:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, -4)
  meta1:SetJustifyH("LEFT")
  meta1:SetText("")
  dv.meta1 = meta1

  local meta2 = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  meta2:SetPoint("TOPLEFT", meta1, "BOTTOMLEFT", 0, -2)
  meta2:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, -2)
  meta2:SetJustifyH("LEFT")
  meta2:SetText("")
  dv.meta2 = meta2

  ---------------------------------------------------------------------------
  -- Tabs row (sub-tabs left, action buttons right)
  ---------------------------------------------------------------------------
  local tabsRow = CreateFrame("Frame", nil, detailFrame)
  tabsRow:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
  tabsRow:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)
  tabsRow:SetHeight(28)
  dv.tabsRow = tabsRow

  -- v3: Action buttons → Skin:BlizzButton (UIPanelButtonTemplate)
  local function MakeActionBtn(parent, text, w)
    if Skin and Skin.BlizzButton then
      return Skin:BlizzButton(parent, text, w, 22)
    elseif Skin and Skin.StyledButton then
      return Skin:StyledButton(parent, text, w, 22)
    else
      local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
      b:SetSize(w, 22)
      b:SetText(text)
      return b
    end
  end

  local btnExport = MakeActionBtn(tabsRow, "Export View", 100)
  btnExport:SetPoint("TOPRIGHT", tabsRow, "TOPRIGHT", -2, -2)
  btnExport:SetScript("OnClick", function()
    if UI and UI.OpenGridExport then
      UI:OpenGridExport({ includeOccurrences = true, includeLog = false })
    elseif UI and UI.OpenFilteredExport then
      local grid = UI.groupGrid
      local opts = {}
      if grid and grid.addon and grid.addon ~= "ALL" then opts.addon = grid.addon end
      if grid and grid.kind and grid.kind ~= "ALL" then opts.kind = grid.kind end
      UI:OpenFilteredExport(opts)
    end
  end)
  dv.btnExportFiltered = btnExport

  -- Copy dropdown
  local function CopyPayload(copyKind)
    if not UI or not UI.selectedSig or not RDL.DB then return end
    local g = RDL.DB:GetGroup(UI.selectedSig)
    if not g or not UI.ShowExport then return end

    if copyKind == "sig" then
      UI:ShowExport("RothDevLib Copy Signature", UI.selectedSig)
    elseif copyKind == "msg" then
      UI:ShowExport("RothDevLib Copy Message", tostring(g.message or ""))
    elseif copyKind == "stack" then
      UI:ShowExport("RothDevLib Copy Stack", tostring(g.stack or ""))
    elseif copyKind == "locals" then
      UI:ShowExport("RothDevLib Copy Locals", (g.locals and tostring(g.locals)) or "<no locals captured>")
    elseif copyKind == "all" then
      if UI.BuildExportSelectedText then
        local text = UI:BuildExportSelectedText(UI.selectedSig, { includeOccurrences = true, includeLog = false })
        UI:ShowExport("RothDevLib Copy All", text or "")
      else
        local fallback = table.concat({
          "Signature: " .. tostring(UI.selectedSig), "",
          "--- Message ---", tostring(g.message or ""), "",
          "--- Stack ---", tostring(g.stack or ""), "",
          "--- Locals ---", (g.locals and tostring(g.locals)) or "<no locals captured>",
        }, "\n")
        UI:ShowExport("RothDevLib Copy All", fallback)
      end
    end
  end

  local btnCopy = MakeActionBtn(tabsRow, "Copy", 80)
  btnCopy:SetPoint("RIGHT", btnExport, "LEFT", -4, 0)
  dv.btnCopy = btnCopy

  local copyDD = CreateFrame("Frame", "RothDevLibDetailCopyDropDown", detailFrame, "UIDropDownMenuTemplate")
  if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton then
    UIDropDownMenu_Initialize(copyDD, function(_, level)
      local info = UIDropDownMenu_CreateInfo()
      info.notCheckable = true

      info.text = "Copy Signature"
      info.func = function() CopyPayload("sig") end
      UIDropDownMenu_AddButton(info, level)

      info.text = "Copy Message"
      info.func = function() CopyPayload("msg") end
      UIDropDownMenu_AddButton(info, level)

      info.text = "Copy Stack"
      info.func = function() CopyPayload("stack") end
      UIDropDownMenu_AddButton(info, level)

      info.text = "Copy Locals"
      info.func = function() CopyPayload("locals") end
      UIDropDownMenu_AddButton(info, level)

      info.text = "Copy All"
      info.func = function() CopyPayload("all") end
      UIDropDownMenu_AddButton(info, level)
    end, "MENU")
  end
  btnCopy:SetScript("OnClick", function()
    if ToggleDropDownMenu then
      ToggleDropDownMenu(1, nil, copyDD, btnCopy, 0, 0)
    else
      CopyPayload("all")
    end
  end)

  local btnActions = MakeActionBtn(tabsRow, "Actions", 86)
  btnActions:SetPoint("RIGHT", btnCopy, "LEFT", -4, 0)
  dv.btnActions = btnActions

  -- Tabs container (left) clips so tab buttons never overlap right-side actions.
  local tabsArea = CreateFrame("Frame", nil, tabsRow)
  tabsArea:SetPoint("TOPLEFT", tabsRow, "TOPLEFT", 2, -2)
  tabsArea:SetPoint("BOTTOMLEFT", tabsRow, "BOTTOMLEFT", 2, 2)
  tabsArea:SetPoint("RIGHT", btnActions, "LEFT", -6, 0)
  if tabsArea.SetClipsChildren then tabsArea:SetClipsChildren(true) end
  dv.tabsArea = tabsArea

  local actionsDD = CreateFrame("Frame", "RothDevLibDetailActionsDropDown", detailFrame, "UIDropDownMenuTemplate")
  if UIDropDownMenu_Initialize and UIDropDownMenu_CreateInfo and UIDropDownMenu_AddButton then
    UIDropDownMenu_Initialize(actionsDD, function(_, level)
      local info = UIDropDownMenu_CreateInfo()
      info.notCheckable = true

      info.text = "Open Sig"
      info.func = function()
        if UI and UI.OpenToSig then UI:OpenToSig(UI.selectedSig) end
      end
      UIDropDownMenu_AddButton(info, level)

      local sigIgnored = false
      local addonIgnored = false
      if UI and UI.selectedSig and RDL.DB and RDL.DB.raw and RDL.DB.raw.ignore then
        local ig = RDL.DB.raw.ignore
        sigIgnored = ig.sig and ig.sig[UI.selectedSig] and true or false
        local gg = RDL.DB.GetGroup and RDL.DB:GetGroup(UI.selectedSig) or nil
        local addonName = gg and gg.addon or nil
        addonIgnored = addonName and ig.addon and ig.addon[addonName] and true or false
      end

      info.text = sigIgnored and "Unignore Sig" or "Ignore Sig"
      info.func = function()
        if UI and UI.ToggleIgnoreSig then UI:ToggleIgnoreSig(UI.selectedSig) end
      end
      UIDropDownMenu_AddButton(info, level)

      info.text = addonIgnored and "Unignore Addon" or "Ignore Addon"
      info.func = function()
        if UI and UI.ToggleIgnoreAddon then UI:ToggleIgnoreAddon(nil) end
      end
      UIDropDownMenu_AddButton(info, level)
    end, "MENU")
  end
  btnActions:SetScript("OnClick", function()
    if ToggleDropDownMenu then
      ToggleDropDownMenu(1, nil, actionsDD, btnActions, 0, 0)
    end
  end)

  ---------------------------------------------------------------------------
  -- Selection UI enable/disable
  ---------------------------------------------------------------------------
  local function UpdateSelectionUI(hasSelection)
    dv._hasSelection = hasSelection and true or false
    local alpha = dv._hasSelection and 1 or 0.45
    local function Tune(btn)
      if not btn then return end
      if btn.SetEnabled then btn:SetEnabled(dv._hasSelection) end
      if btn.SetAlpha then btn:SetAlpha(alpha) end
    end
    Tune(btnExport)
    Tune(btnCopy)
    Tune(btnActions)
  end
  dv.UpdateSelectionUI = UpdateSelectionUI

  ---------------------------------------------------------------------------
  -- v3: Sub-tab buttons — Blizzard toggle style
  -- Uses BlizzButton with checked-state highlighting for active tab.
  ---------------------------------------------------------------------------
  dv.tabButtons = {}
  for i, def in ipairs(TAB_DEFS) do
    local tab
    -- Try CheckButton for proper toggle look, fallback to regular button
    local ok = pcall(function()
      tab = CreateFrame("CheckButton", nil, tabsArea, "UIPanelButtonTemplate")
    end)
    if not ok or not tab then
      if Skin and Skin.BlizzButton then
        tab = Skin:BlizzButton(tabsArea, def.label, 70, 22)
      elseif Skin and Skin.TabButton then
        tab = Skin:TabButton(tabsArea, def.label, 70, 22)
      else
        tab = CreateFrame("Button", nil, tabsArea, "UIPanelButtonTemplate")
        tab:SetSize(70, 22)
        tab:SetText(def.label)
      end
    end
    if tab.SetSize then tab:SetSize(70, 22) end
    if tab.SetText then tab:SetText(def.label) end
    tab._baseLabel = def.label

    if i == 1 then
      tab:SetPoint("BOTTOMLEFT", tabsArea, "BOTTOMLEFT", 0, 0)
    else
      tab:SetPoint("LEFT", dv.tabButtons[i - 1], "RIGHT", 2, 0)
    end

    tab:SetScript("OnClick", function()
      if UI and UI.SetDetailTab then UI:SetDetailTab(i) end
    end)

    dv.tabButtons[i] = tab
  end

  ApplyTabPresentation(dv, self.detailTab, nil)

  ---------------------------------------------------------------------------
  -- Content area: scroll + EditBox (Blizzard inset)
  ---------------------------------------------------------------------------
  local content = CreateFrame("Frame", nil, detailFrame, "BackdropTemplate")
  content:SetPoint("TOPLEFT", tabsRow, "BOTTOMLEFT", 0, -4)
  content:SetPoint("BOTTOMRIGHT", detailFrame, "BOTTOMRIGHT", -4, 4)
  -- v3: prefer Blizzard inset over dark inset
  if Skin and Skin.ApplyInset then
    Skin:ApplyInset(content)
  elseif Skin and Skin.DarkInset then
    Skin:DarkInset(content)
  end
  dv.content = content

  ---------------------------------------------------------------------------
  -- Occur bar (search + prev/next) lives inside the content inset.
  ---------------------------------------------------------------------------
  local occurBar = CreateFrame("Frame", nil, content, "BackdropTemplate")
  occurBar:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -6)
  occurBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -6, -6)
  occurBar:SetHeight(24)
  if Skin and Skin.ApplyInset then
    pcall(function() Skin:ApplyInset(occurBar) end)
  end
  occurBar:Hide()
  dv.occurBar = occurBar

  local searchLabel = occurBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  searchLabel:SetPoint("LEFT", occurBar, "LEFT", 8, 0)
  searchLabel:SetText("Occur filter:")
  dv.searchLabel = searchLabel

  local search
  if Skin and Skin.SearchBox then
    search = Skin:SearchBox(occurBar, 160, 20)
  else
    search = CreateFrame("EditBox", nil, occurBar, "BackdropTemplate")
    search:SetSize(160, 20)
    search:SetAutoFocus(false)
    search:SetFontObject(ChatFontSmall)
    search:SetTextInsets(4, 4, 0, 0)
  end
  search:SetPoint("LEFT", searchLabel, "RIGHT", 4, 0)
  search._onChanged = nil
  search:SetScript("OnTextChanged", function(box)
    local newFilter = box:GetText() or ""
    if newFilter ~= (dv._lastOccFilter or "") then
      dv.occIndex = 1
      dv._lastOccFilter = newFilter
    end
    if box._placeholder then
      box._placeholder:SetShown(newFilter == "")
    end
    if box._clearBtn then
      box._clearBtn:SetShown(newFilter ~= "")
    end
    if UI and UI.UpdateDetailView then UI:UpdateDetailView(UI.selectedSig) end
  end)
  search:SetScript("OnEscapePressed", function(box)
    box:SetText("")
    box:ClearFocus()
  end)
  dv.searchBox = search

  -- v3: Occur nav buttons → Blizzard style
  local function MakeSmallBtn(parent, text, w)
    if Skin and Skin.BlizzButton then
      return Skin:BlizzButton(parent, text, w, 20)
    else
      local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
      b:SetSize(w, 20)
      b:SetText(text)
      return b
    end
  end

  local btnOccPrev = MakeSmallBtn(occurBar, "<", 24)
  local btnOccNext = MakeSmallBtn(occurBar, ">", 24)
  btnOccPrev:SetPoint("LEFT", search, "RIGHT", 6, 0)
  btnOccNext:SetPoint("LEFT", btnOccPrev, "RIGHT", 2, 0)
  btnOccPrev:SetScript("OnClick", function()
    if not dv then return end
    dv.occIndex = math.max(1, (tonumber(dv.occIndex) or 1) - 1)
    if UI.UpdateDetailView then UI:UpdateDetailView(UI.selectedSig) end
  end)
  btnOccNext:SetScript("OnClick", function()
    if not dv then return end
    dv.occIndex = (tonumber(dv.occIndex) or 1) + 1
    if UI.UpdateDetailView then UI:UpdateDetailView(UI.selectedSig) end
  end)
  dv.btnOccPrev = btnOccPrev
  dv.btnOccNext = btnOccNext

  local occIndexLabel = occurBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  occIndexLabel:SetPoint("LEFT", btnOccNext, "RIGHT", 6, 0)
  occIndexLabel:SetText("0/0")
  dv.occIndexLabel = occIndexLabel

  local scroll = CreateFrame("ScrollFrame", "RothDevLibDetailScroll", content, "UIPanelScrollFrameTemplate")
  dv.ApplyContentLayout = function(_, isOccShown)
    if not scroll then return end
    scroll:ClearAllPoints()
    if isOccShown and dv.occurBar and dv.occurBar:IsShown() then
      scroll:SetPoint("TOPLEFT", dv.occurBar, "BOTTOMLEFT", 0, -6)
    else
      scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 6, -6)
    end
    scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -30, 6)
  end
  dv:ApplyContentLayout(false)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(ChatFontNormal)

  local function UpdateWidth()
    local w = (content.GetWidth and content:GetWidth() or 600) - 60
    if w < 420 then w = 420 end
    edit:SetWidth(w)
  end
  UpdateWidth()
  if content.HookScript then content:HookScript("OnSizeChanged", UpdateWidth) end

  edit:SetScript("OnEscapePressed", function() edit:ClearFocus() end)
  edit:SetText("")
  scroll:SetScrollChild(edit)

  dv.scroll = scroll
  dv.edit = edit

  ---------------------------------------------------------------------------
  -- Toolbar visibility manager
  ---------------------------------------------------------------------------
  dv._placeholder = "No entries.\n\nTry: /rdev test alert\nTry: /rdev diag"

  dv.UpdateToolbar = function()
    if not dv._hasSelection then
      if dv.occurBar then dv.occurBar:Hide() end
      if dv.ApplyContentLayout then dv:ApplyContentLayout(false) end
      return
    end

    local tab = tonumber(UI.detailTab) or 1
    local def = dv.tabs and dv.tabs[tab] or nil
    local isOcc = def and def.key == "occ"
    if dv.occurBar then dv.occurBar:SetShown(isOcc) end
    if dv.ApplyContentLayout then dv:ApplyContentLayout(isOcc) end
  end

  UpdateSelectionUI(false)
  dv.UpdateToolbar()
  self:SetDetailPlaceholder(dv._placeholder)
end

---------------------------------------------------------------------------
-- Placeholder
---------------------------------------------------------------------------
function UI:SetDetailPlaceholder(text)
  local dv = self.detailView
  if not dv or not dv.edit then return end

  if dv.UpdateSelectionUI then dv.UpdateSelectionUI(false) end
  if dv.UpdateToolbar then dv.UpdateToolbar() end

  dv.sigText:SetText("No selection")
  dv.meta1:SetText("")
  dv.meta2:SetText("")
  dv.occIndex = 1
  dv._lastSig = nil
  if dv.occIndexLabel then dv.occIndexLabel:SetText("0/0") end

  dv.edit:SetText(EscapeForEditBox(text or ""))
  dv.edit:SetCursorPosition(0)
  dv.edit:ClearFocus()
  ApplyTabPresentation(dv, self.detailTab, nil)
end

---------------------------------------------------------------------------
-- Set active tab
---------------------------------------------------------------------------
function UI:SetDetailTab(tab)
  tab = tonumber(tab) or 1
  if tab < 1 then tab = 1 end
  if self.detailView and self.detailView.tabs then
    local max = #self.detailView.tabs
    if tab > max then tab = max end
  end

  self.detailTab = tab

  local dv = self.detailView
  if dv and dv.UpdateToolbar then dv.UpdateToolbar() end
  if dv then
    local g = (self.selectedSig and RDL.DB and RDL.DB.GetGroup) and RDL.DB:GetGroup(self.selectedSig) or nil
    ApplyTabPresentation(dv, tab, BuildTabBadges(g))
  end

  self:UpdateDetailView(self.selectedSig)
end

---------------------------------------------------------------------------
-- Doctor text builder
---------------------------------------------------------------------------
local function BuildDoctorText(g)
  local U = RDL.Util
  local out = {}

  if g.origin and (g.origin.file or g.origin.addon) then
    local o = g.origin
    table.insert(out, ("Origin: addon=%s file=%s line=%s"):format(
      tostring(o.addon or "<?>"), tostring(o.file or "<?>"), tostring(o.line or "<?>")))
    table.insert(out, "")
  end

  if g.ctx and g.ctx.top then
    table.insert(out, "Doctor Top:")
    table.insert(out, U and U:SafeSerializeTable(g.ctx.top) or tostring(g.ctx.top))
    table.insert(out, "")
  end

  if g.ctx and g.ctx.chain then
    table.insert(out, "Doctor Chain:")
    table.insert(out, U and U:SafeSerializeTable(g.ctx.chain) or tostring(g.ctx.chain))
    table.insert(out, "")
  end

  if g.ctx and g.ctx.extra then
    table.insert(out, "Extra:")
    table.insert(out, U and U:SafeSerializeTable(g.ctx.extra) or tostring(g.ctx.extra))
    table.insert(out, "")
  end

  if g.sys then
    table.insert(out, "System Snapshot:")
    table.insert(out, U and U:SafeSerializeTable(g.sys) or tostring(g.sys))
    table.insert(out, "")
  end

  if g.bus then
    local b = g.bus
    if b.breadcrumbs and #b.breadcrumbs > 0 then
      table.insert(out, "Breadcrumbs (newest first):")
      for _, bc in ipairs(b.breadcrumbs) do
        local ts = bc.ts and date("%H:%M:%S", bc.ts) or "<?>"
        table.insert(out, string.format("  - %s [%s] %s", ts, tostring(bc.cat or "<?>"), tostring(bc.msg or "")))
        if bc.data and bc.data ~= "" then
          table.insert(out, "      data=" .. tostring(bc.data))
        end
      end
      table.insert(out, "")
    end

    if b.metrics then
      table.insert(out, "Metrics:")
      table.insert(out, U and U:SafeSerializeTable(b.metrics) or tostring(b.metrics))
      table.insert(out, "")
    end
  end

  if #out == 0 then table.insert(out, "<no doctor context>") end
  return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- Occurrence helpers
---------------------------------------------------------------------------
local function BuildOccurrenceIndexes(g, filter)
  local occ = g and g.occurrences
  if type(occ) ~= "table" or #occ == 0 then return {}, 0 end

  local indices = {}
  local filterLower = (filter and filter ~= "") and filter:lower() or nil
  for i, o in ipairs(occ) do
    local match = true
    if filterLower then
      local hay = (tostring(o.message or "") .. tostring(o.stack or "") .. tostring(o.locals or "")):lower()
      match = hay:find(filterLower, 1, true) ~= nil
    end
    if match then indices[#indices + 1] = i end
  end
  return indices, #occ
end

local function BuildOccurrenceText(g, realIndex, visibleIndex, visibleTotal, filter)
  local occ = g and g.occurrences
  if type(occ) ~= "table" then return "<no occurrences stored>" end
  local o = occ[realIndex]
  if not o then return "<no occurrence>" end

  local out = {}
  table.insert(out, ("Occurrence %d/%d (source index %d)"):format(visibleIndex, visibleTotal, realIndex))
  if filter and filter ~= "" then
    table.insert(out, ('Filter: "%s"'):format(filter))
  end
  table.insert(out, "")
  table.insert(out, ("Time: %s"):format(SafeDate(o.ts)))
  table.insert(out, ("Kind: %s"):format(tostring(o.kind or "<?>")))
  table.insert(out, ("Addon: %s"):format(tostring(o.addon or "<?>")))
  table.insert(out, ("Func: %s"):format(tostring(o.func or "<?>")))
  table.insert(out, ("Session: %s"):format(tostring(o.sessionId or "?")))
  table.insert(out, "")

  table.insert(out, "--- Message ---")
  table.insert(out, tostring(o.message or ""))
  table.insert(out, "")

  table.insert(out, "--- Stack ---")
  table.insert(out, tostring(o.stack or ""))
  table.insert(out, "")

  table.insert(out, "--- Locals ---")
  if o.locals and o.locals ~= "" then
    table.insert(out, tostring(o.locals))
  else
    table.insert(out, "<no locals captured>")
  end

  if o.sys then
    local U = RDL.Util
    table.insert(out, "")
    table.insert(out, "--- Sys ---")
    table.insert(out, U and U:SafeSerializeTable(o.sys) or tostring(o.sys))
  end

  return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- UpdateDetailView
---------------------------------------------------------------------------
function UI:UpdateDetailView(sig)
  local dv = self.detailView
  if not dv or not dv.edit then return end

  if not sig or not RDL.DB then
    return self:SetDetailPlaceholder(dv._placeholder or "")
  end

  local g = RDL.DB:GetGroup(sig)
  if not g then
    return self:SetDetailPlaceholder(dv._placeholder or "")
  end

  if dv.UpdateSelectionUI then dv.UpdateSelectionUI(true) end
  if dv.UpdateToolbar then dv.UpdateToolbar() end
  if dv._lastSig ~= sig then
    dv._lastSig = sig
    dv.occIndex = 1
  end

  local U = RDL.Util
  local showSig = tostring(sig)
  if U and U.EscapePipes then
    showSig = U:EscapePipes(showSig)
  else
    showSig = showSig:gsub("|", "||")
  end

  dv.sigText:SetText(("Signature: %s"):format(showSig))

  local meta1Text = ("Kind: %s   Count: %d   First: %s   Last: %s"):format(
    tostring(g.kind or "<?>"),
    tonumber(g.count) or 0,
    SafeDate(g.firstSeen),
    SafeDate(g.lastSeen)
  )
  local meta2Text = ("Addon: %s   Func: %s"):format(tostring(g.addon or "<?>"), tostring(g.func or "<?>"))
  local ex = g.ctx and g.ctx.extra
  if ex then
    if ex.wrapperAddon and tostring(ex.wrapperAddon) ~= tostring(g.addon or "<?>") then
      meta2Text = meta2Text .. ("   Via: %s"):format(tostring(ex.wrapperAddon))
    end
    if ex.handlerAddon and tostring(ex.handlerAddon) ~= tostring(g.addon or "<?>") then
      meta2Text = meta2Text .. ("   Handler: %s"):format(tostring(ex.handlerAddon))
    end
  end

  dv.meta1:SetText(EscapeForEditBox(meta1Text))
  dv.meta2:SetText(EscapeForEditBox(meta2Text))

  local tabIdx = tonumber(self.detailTab) or 1
  local def = dv.tabs and dv.tabs[tabIdx] or dv.tabs[1]
  local key = def and def.key or "message"
  ApplyTabPresentation(dv, tabIdx, BuildTabBadges(g))

  local body = ""
  if key == "message" then
    body = tostring(g.message or "")
  elseif key == "stack" then
    body = tostring(g.stack or "")
  elseif key == "locals" then
    body = (g.locals and g.locals ~= "") and tostring(g.locals) or "<no locals captured>"
  elseif key == "doctor" then
    body = BuildDoctorText(g)
  elseif key == "occ" then
    local filter = dv.searchBox and dv.searchBox:GetText() or ""
    dv._lastOccFilter = filter
    local indices, rawTotal = BuildOccurrenceIndexes(g, filter)
    local visibleTotal = #indices
    if visibleTotal <= 0 then
      body = rawTotal > 0 and "No matches for current occurrence filter." or "<no occurrences stored>"
      if dv.occIndexLabel then dv.occIndexLabel:SetText("0/0") end
      dv.occIndex = 1
    else
      local idx = tonumber(dv.occIndex) or 1
      if idx < 1 then idx = 1 end
      if idx > visibleTotal then idx = visibleTotal end
      dv.occIndex = idx
      local realIndex = indices[idx]
      body = BuildOccurrenceText(g, realIndex, idx, visibleTotal, filter)
      if dv.occIndexLabel then
        dv.occIndexLabel:SetText(("%d/%d"):format(idx, visibleTotal))
      end
    end
  elseif dv.occIndexLabel then
    dv.occIndexLabel:SetText("0/0")
  end

  dv.edit:SetText(EscapeForEditBox(body))
  dv.edit:SetCursorPosition(0)
  dv.edit:ClearFocus()
end
