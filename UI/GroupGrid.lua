-- !RothDevLib/UI/GroupGrid.lua
-- Phase 5 / v3 rewrite: Simple row pool + Slider (no ScrollBox dependency).
-- Reliable in ALL WoW versions.
--
-- v3 changes:
--   * Removed WowScrollBoxList/ScrollBox/DataProvider dependency
--   * Simple row Button pool + UIPanelScrollBarTemplate slider
--   * Manual offset-based rendering: always works
--   * All filter/sort/column resize logic preserved from v2

local RDL = _G.RothDevLib
RDL.UI = RDL.UI or {}
local UI = RDL.UI

local ROW_H = 20
local ROW_GAP = 1
local HEADER_H = 18
local FILTER_H = 30
local DOUBLE_CLICK_SEC = 0.35
local MAX_ROW_POOL = 60

local COLS = {
  { key = "kind",  label = "Kind",  w = 90,  min = 70,  max = 200 },
  { key = "addon", label = "Addon", w = 120, min = 80,  max = 260 },
  { key = "count", label = "Count", w = 60,  min = 50,  max = 120 },
  { key = "last",  label = "Last",  w = 70,  min = 60,  max = 140 },
  { key = "msg",   label = "Message", w = 999 }, -- fill
}

local function KindToRGB(kind)
  kind = tostring(kind or "")
  if kind == "LUA_ERROR" then return 1.00, 0.20, 0.20 end
  if kind == "TAINT_BLOCKED" or kind == "TAINT_FORBIDDEN" or kind == "TAINT_STATE" then return 1.00, 0.85, 0.20 end
  if kind == "LUA_WARNING" then return 1.00, 0.60, 0.20 end
  if kind == "SUPPRESSED" then return 0.80, 0.80, 1.00 end
  if kind == "ALERT" then return 1.00, 0.75, 0.00 end
  if kind == "ASSERT" then return 1.00, 0.40, 0.70 end
  return 1.00, 1.00, 1.00
end

local function NormalizeKindFilter(kind)
  kind = tostring(kind or "ALL")
  if kind == "" then kind = "ALL" end
  return kind
end

local function MatchKind(filterKind, groupKind)
  filterKind = NormalizeKindFilter(filterKind)
  groupKind = tostring(groupKind or "")
  if filterKind == "ALL" then return true end
  if filterKind == "TAINT" then
    return groupKind == "TAINT_BLOCKED" or groupKind == "TAINT_FORBIDDEN" or groupKind == "TAINT_STATE"
  end
  return groupKind == filterKind
end

local function ResolveSessionContext(db, sessionFilter)
  local filter = sessionFilter
  if filter == nil or filter == "" then filter = "ALL" end

  local scoped = false
  local sessionId = nil

  if filter == "CURRENT" then
    scoped = true
    sessionId = tonumber(db and db.sessionId) or (db and db.sessionId)
  elseif filter == "PREV" then
    scoped = true
    local sessions = db and db.GetSessions and db:GetSessions() or nil
    if sessions and sessions[2] then
      sessionId = tonumber(sessions[2].id) or sessions[2].id
    end
  elseif type(filter) == "number" then
    scoped = true
    sessionId = filter
  elseif filter ~= "ALL" then
    filter = "ALL"
  end

  return filter, scoped, sessionId
end

local function BuildSessionFilterLabel(sessionFilter)
  if sessionFilter == nil or sessionFilter == "" or sessionFilter == "ALL" then
    return "All sessions"
  end
  if sessionFilter == "CURRENT" then return "Current session" end
  if sessionFilter == "PREV" then return "Previous session" end
  if type(sessionFilter) == "number" then
    return string.format("Session #%d", sessionFilter)
  end
  return "All sessions"
end

local function BuildSessionEntryLabel(s)
  if type(s) ~= "table" then return "Session" end
  local sid = tonumber(s.id) or s.id or "?"
  local who = tostring(s.character or "?")
  return string.format("#%s %s", tostring(sid), who)
end

local function Lower(s)
  if s == nil then return "" end
  return string.lower(tostring(s))
end

local function TruncOneLine(s, max)
  s = tostring(s or "")
  s = s:gsub("\n", " ")
  if #s > max then return s:sub(1, max) .. "..." end
  return s
end

local function SetSolid(tex, r, g, b, a)
  if not tex then return end
  if tex.SetColorTexture then
    tex:SetColorTexture(r, g, b, a)
  else
    tex:SetTexture("Interface/Tooltips/UI-Tooltip-Background")
    tex:SetVertexColor(r, g, b, a)
  end
end

local function BuildSearchHay(g)
  local top = ""
  if g and g.stack then
    top = tostring(g.stack):match("([^\n]*)") or ""
  end
  return table.concat({
    g and g.sig or "",
    g and g.kind or "",
    g and g.addon or "",
    g and g.func or "",
    g and g.message or "",
    top,
  }, " ")
end

local function SetSortArrow(btn, active, asc)
  if not btn or not btn.txt then return end
  local base = btn._label or ""
  if not active then
    btn.txt:SetText(base)
    return
  end
  btn.txt:SetText(base .. (asc and " ^" or " v"))
end

local function PassesFilters(sig, g, kindFilter, addonFilter, showIgnored, wantQuery, q)
  if not g then return false end
  if (not showIgnored) and RDL.DB.IsIgnored and RDL.DB:IsIgnored(sig, g.addon, g.message) then
    return false
  end
  if addonFilter ~= "ALL" and tostring(g.addon or "") ~= addonFilter then
    return false
  end
  if not MatchKind(kindFilter, g.kind) then
    return false
  end
  if wantQuery then
    local hay = Lower(BuildSearchHay(g))
    if not string.find(hay, q, 1, true) then
      return false
    end
  end
  return true
end

--------------------------------------------------------------------------
-- Row helpers (v3: simple pool approach)
--------------------------------------------------------------------------
function UI:_ApplyRowLayout(row)
  if not row or not row.cols then return end
  local grid = self.groupGrid
  local widths = grid and grid._colWidths or nil

  local gap = 4
  local x = 2

  local wKind  = (widths and widths.kind)  or COLS[1].w
  local wAddon = (widths and widths.addon) or COLS[2].w
  local wCount = (widths and widths.count) or COLS[3].w
  local wLast  = (widths and widths.last)  or COLS[4].w

  local function Place(fs, w, isLast)
    if not fs then return end
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", row, "LEFT", x, 0)
    if isLast then
      fs:SetPoint("RIGHT", row, "RIGHT", -4, 0)
      if fs.SetWidth then fs:SetWidth(0) end
    else
      if fs.SetWidth then fs:SetWidth(w) end
    end
    x = x + (w or 0) + gap
  end

  Place(row.cols.kind,  wKind)
  Place(row.cols.addon, wAddon)
  Place(row.cols.count, wCount)
  Place(row.cols.last,  wLast)
  Place(row.cols.msg,   0, true)
end

function UI:_InitRow(row, parent)
  if not row or row._inited then return end
  row._inited = true

  local Skin = UI.Skin
  local C = Skin and Skin.C

  if row.SetHeight then row:SetHeight(ROW_H) end
  row:EnableMouse(true)
  if row.RegisterForClicks then
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  end
  row:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight")

  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints(row)
  SetSolid(row.bg, 0, 0, 0, 0)

  row.sel = row:CreateTexture(nil, "BORDER")
  row.sel:SetAllPoints(row)
  if C then
    SetSolid(row.sel, C.rowSelected[1], C.rowSelected[2], C.rowSelected[3], C.rowSelected[4])
  else
    SetSolid(row.sel, 0.18, 0.30, 0.50, 0.60)
  end
  row.sel:Hide()

  row.cols = {}
  for _, c in ipairs(COLS) do
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
    if fs.SetMaxLines then fs:SetMaxLines(1) end
    row.cols[c.key] = fs
  end

  row:SetScript("OnSizeChanged", function()
    if UI and UI._ApplyRowLayout then
      UI:_ApplyRowLayout(row)
    end
  end)

  local function ActivateRow(source)
    local sig = row.sig
    if not sig or sig == "" then return end
    UI.selectedSig = sig
    if UI.ShowGroup then UI:ShowGroup(sig) end
    if UI._FillVisibleRows then UI:_FillVisibleRows() end

    if source == "click" then
      local now = (type(GetTime) == "function") and GetTime() or 0
      local lastSig = UI._gridLastClickSig
      local lastAt = tonumber(UI._gridLastClickAt) or 0
      UI._gridLastClickSig = sig
      UI._gridLastClickAt = now
      if lastSig == sig and (now - lastAt) <= DOUBLE_CLICK_SEC then
        if UI.OpenExportSelected then UI:OpenExportSelected() end
        UI._gridLastClickSig = nil
        UI._gridLastClickAt = 0
      end
    end
  end

  row:SetScript("OnClick", function()
    row._lastOnClickAt = (type(GetTime) == "function") and GetTime() or 0
    ActivateRow("click")
  end)
  row:SetScript("OnMouseUp", function(_, btn)
    if btn ~= "LeftButton" then return end
    local now = (type(GetTime) == "function") and GetTime() or 0
    if row._lastOnClickAt and (now - row._lastOnClickAt) <= 0.05 then return end
    ActivateRow("mouseup")
  end)

  self:_ApplyRowLayout(row)
end

function UI:_UpdateRow(row, g, idx)
  if not row or not g then return end

  local Skin = UI.Skin
  local C = Skin and Skin.C

  row.group = g
  row.sig = g.sig or g._sig

  -- Zebra stripes
  if row.bg then
    if C then
      if (idx % 2) == 0 then
        SetSolid(row.bg, C.rowAlt[1], C.rowAlt[2], C.rowAlt[3], C.rowAlt[4])
      else
        SetSolid(row.bg, C.bg[1], C.bg[2], C.bg[3], 0.3)
      end
    else
      local a = ((idx % 2) == 0) and 0.10 or 0.04
      SetSolid(row.bg, 0, 0, 0, a)
    end
  end

  if row.sel then
    if UI.selectedSig and row.sig == UI.selectedSig then row.sel:Show() else row.sel:Hide() end
  end

  local kind = tostring(g.kind or "")
  local addon = tostring(g.addon or "")
  local count = tostring(g.count or 0)
  local last = g.lastSeen and date("%H:%M:%S", g.lastSeen) or ""
  local msg = TruncOneLine(g.message or "", 80)

  if RDL.Util and RDL.Util.EscapePipes then
    kind = RDL.Util:EscapePipes(kind)
    addon = RDL.Util:EscapePipes(addon)
    count = RDL.Util:EscapePipes(count)
    last = RDL.Util:EscapePipes(last)
    msg = RDL.Util:EscapePipes(msg)
  else
    kind = kind:gsub("|", "||")
    addon = addon:gsub("|", "||")
    msg = msg:gsub("|", "||")
  end

  if row.cols.kind then row.cols.kind:SetText(kind) end
  if row.cols.addon then row.cols.addon:SetText(addon) end
  if row.cols.count then row.cols.count:SetText(count) end
  if row.cols.last then row.cols.last:SetText(last) end
  if row.cols.msg then row.cols.msg:SetText(msg) end

  local r, gg, bb = KindToRGB(g.kind)
  if row.cols.kind then row.cols.kind:SetTextColor(r, gg, bb) end
  if row.cols.addon then row.cols.addon:SetTextColor(1, 1, 1) end
  if row.cols.count then row.cols.count:SetTextColor(1, 1, 1) end
  if row.cols.last then row.cols.last:SetTextColor(0.9, 0.9, 0.9) end
  if row.cols.msg then row.cols.msg:SetTextColor(r, gg, bb) end

  self:_ApplyRowLayout(row)
end

--------------------------------------------------------------------------
-- Fill visible rows from offset (core rendering)
--------------------------------------------------------------------------
function UI:_FillVisibleRows()
  local grid = self.groupGrid
  if not grid or not grid.rowParent then return end

  local groups = grid._groups or {}
  local total = #groups
  local offset = grid.scrollOffset or 0

  local parentH = grid.rowParent:GetHeight() or 300
  local visibleCount = math.floor(parentH / (ROW_H + ROW_GAP))
  if visibleCount < 1 then visibleCount = 1 end

  -- Clamp offset
  local maxOffset = math.max(0, total - visibleCount)
  if offset > maxOffset then offset = maxOffset end
  if offset < 0 then offset = 0 end
  grid.scrollOffset = offset

  -- Update scroll bar range
  if grid.scrollBar then
    grid.scrollBar:SetMinMaxValues(0, maxOffset)
    -- Only set value if it differs to avoid infinite loops
    local curVal = grid.scrollBar:GetValue() or 0
    if math.abs(curVal - offset) > 0.5 then
      grid.scrollBar:SetValue(offset)
    end
  end

  -- Fill rows
  for i = 1, MAX_ROW_POOL do
    local row = grid.rowPool and grid.rowPool[i]
    if not row then break end

    local dataIdx = offset + i
    if i <= visibleCount and dataIdx <= total then
      local g = groups[dataIdx]
      if g then
        row:Show()
        self:_UpdateRow(row, g, dataIdx)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", grid.rowParent, "TOPLEFT", 2, -((i - 1) * (ROW_H + ROW_GAP)))
        row:SetPoint("RIGHT", grid.rowParent, "RIGHT", -2, 0)
      else
        row:Hide()
      end
    else
      row:Hide()
    end
  end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
function UI:InitGroupGrid(listFrame)
  if not listFrame or self.groupGrid then return end

  local Skin = UI.Skin
  local C = Skin and Skin.C

  local grid = {}
  self.groupGrid = grid

  grid.listFrame = listFrame

  grid.query = ""
  grid.kind = "ALL"
  grid.addon = "ALL"
  grid.sessionFilter = "ALL"
  grid.showIgnored = false
  grid.sortKey = "lastSeen"
  grid.sortAsc = false
  grid.scrollOffset = 0

  -- Column widths (persisted in settings.uiGroupGridCols).
  do
    local s = RDL.DB and RDL.DB.raw and RDL.DB.raw.settings or nil
    local saved = s and s.uiGroupGridCols
    grid.colW = {}
    for _, c in ipairs(COLS) do
      if c.key ~= "msg" then
        local v = saved and saved[c.key]
        v = tonumber(v) or c.w
        if c.min and v < c.min then v = c.min end
        if c.max and v > c.max then v = c.max end
        grid.colW[c.key] = v
      end
    end
  end

  -----------------------------------------------------------------------
  -- Filter row (compact): Kind dropdown + Addon dropdown + Ignored checkbox
  -----------------------------------------------------------------------

  local Menu = UI.Menu
  if Menu and Menu.EnsureLoaded then
    pcall(function() Menu:EnsureLoaded() end)
  end

  local function SafeGenerate(ddObj)
    if Menu and Menu.SafeGenerate then
      pcall(function() Menu:SafeGenerate(ddObj) end)
    elseif ddObj and ddObj.GenerateMenu then
      pcall(function() ddObj:GenerateMenu() end)
    end
  end

  local useNew = false
  if Menu and Menu.SupportsWowStyleDropdown then
    local ok, result = pcall(function() return Menu:SupportsWowStyleDropdown() end)
    useNew = ok and result
  end

  if useNew then
    ---------------------------------------------------------------------
    -- Kind dropdown (WowStyle)
    ---------------------------------------------------------------------
    local dd = Menu:CreateFilterDropdown(listFrame, 'RothDevLibKindDropDown', 130, 'All', 'WowStyle1FilterDropdownTemplate')
    if dd then
      dd:SetPoint('TOPLEFT', listFrame, 'TOPLEFT', 6, -6)
      grid.kindDropDown = dd

      local function SetKind(k)
        grid.kind = NormalizeKindFilter(k)
        SafeGenerate(dd)
        if UI and UI.RequestRefresh then UI:RequestRefresh('kind') end
      end

      local function IsSelected(val)
        return NormalizeKindFilter(grid.kind) == NormalizeKindFilter(val)
      end

      local function Generator(owner, rootDescription)
        rootDescription:CreateTitle('Kind')
        local items = {
          { label = 'All',         value = 'ALL' },
          { label = 'LUA_ERROR',   value = 'LUA_ERROR' },
          { label = 'TAINT',       value = 'TAINT' },
          { label = 'LUA_WARNING', value = 'LUA_WARNING' },
          { label = 'SUPPRESSED',  value = 'SUPPRESSED' },
          { label = 'ALERT',       value = 'ALERT' },
          { label = 'ASSERT',      value = 'ASSERT' },
        }
        for _, it in ipairs(items) do
          rootDescription:CreateRadio(it.label, IsSelected, SetKind, it.value)
        end
      end

      dd._rdlMenuGenerator = Generator
      dd:SetupMenu(Generator)
      SafeGenerate(dd)
    end

    ---------------------------------------------------------------------
    -- Addon dropdown (WowStyle)
    ---------------------------------------------------------------------
    local ddAddon = Menu:CreateFilterDropdown(listFrame, 'RothDevLibAddonDropDown', 170, 'All addons', 'WowStyle1FilterDropdownTemplate')
    if ddAddon then
      if dd then
        ddAddon:SetPoint('LEFT', dd, 'RIGHT', 8, 0)
      else
        ddAddon:SetPoint('TOPLEFT', listFrame, 'TOPLEFT', 6, -6)
      end
      grid.addonDropDown = ddAddon

      local function SetAddon(a)
        a = tostring(a or 'ALL')
        if a == '' then a = 'ALL' end
        grid.addon = a
        SafeGenerate(ddAddon)
        if UI and UI.RequestRefresh then UI:RequestRefresh('addon') end
      end

      local function IsSelected(val)
        return tostring(grid.addon or 'ALL') == tostring(val or 'ALL')
      end

      local function Generator(owner, rootDescription)
        rootDescription:CreateTitle('Addon')

        local list = grid._addonList
        if not list then
          if UI and UI._RebuildAddonDropdown then UI:_RebuildAddonDropdown() end
          list = grid._addonList or { 'ALL' }
        end

        local maxFlat = 40
        if #list <= maxFlat then
          for _, a in ipairs(list) do
            local label = (a == 'ALL') and 'All addons' or a
            rootDescription:CreateRadio(label, IsSelected, SetAddon, a)
          end
          return
        end

        rootDescription:CreateRadio('All addons', IsSelected, SetAddon, 'ALL')

        local buckets = {}
        for i = 2, #list do
          local a = list[i]
          local first = tostring(a):sub(1, 1)
          first = first:match('%a') and first:upper() or '#'
          buckets[first] = buckets[first] or {}
          buckets[first][#buckets[first] + 1] = a
        end

        local keys = {}
        for k in pairs(buckets) do keys[#keys + 1] = k end
        table.sort(keys)

        for _, k in ipairs(keys) do
          local sub = rootDescription:CreateButton(k)
          local t = buckets[k]
          table.sort(t, function(x, y) return Lower(x) < Lower(y) end)
          for _, a in ipairs(t) do
            sub:CreateRadio(a, IsSelected, SetAddon, a)
          end
        end
      end

      ddAddon._rdlMenuGenerator = Generator
      ddAddon:SetupMenu(Generator)
      SafeGenerate(ddAddon)
    end

    ---------------------------------------------------------------------
    -- Show ignored checkbox
    ---------------------------------------------------------------------
    local chkShow = CreateFrame('CheckButton', nil, listFrame, 'UICheckButtonTemplate')
    if ddAddon then
      chkShow:SetPoint('LEFT', ddAddon, 'RIGHT', 6, 0)
    elseif dd then
      chkShow:SetPoint('LEFT', dd, 'RIGHT', 6, 0)
    else
      chkShow:SetPoint('TOPLEFT', listFrame, 'TOPLEFT', 6, -6)
    end
    chkShow:SetSize(22, 22)
    do
      local t = chkShow.text or chkShow.Text
      if t and t.SetText then
        t:SetText('Ign')
        if t.SetFontObject then t:SetFontObject('GameFontNormalSmall') end
      end
    end
    chkShow:SetChecked(false)
    chkShow:SetScript('OnClick', function(btn)
      grid.showIgnored = btn:GetChecked() and true or false
      if UI and UI.RequestRefresh then UI:RequestRefresh('ignored') end
    end)
    grid.showIgnoredCheck = chkShow

    ---------------------------------------------------------------------
    -- Session dropdown (hidden by default)
    ---------------------------------------------------------------------
    local ddSession = Menu:CreateFilterDropdown(listFrame, 'RothDevLibSessionDropDown', 190, BuildSessionFilterLabel(grid.sessionFilter), 'WowStyle1FilterDropdownTemplate')
    if ddSession then
      ddSession:SetPoint('LEFT', chkShow, 'RIGHT', 26, 0)
      ddSession:Hide()
      grid.sessionDropDown = ddSession

      local function SetSession(val)
        if val == nil or val == '' then val = 'ALL' end
        if type(val) ~= 'number' then
          val = tostring(val)
          if val ~= 'ALL' and val ~= 'CURRENT' and val ~= 'PREV' then val = 'ALL' end
        end
        grid.sessionFilter = val
        SafeGenerate(ddSession)
        if UI and UI.RequestRefresh then UI:RequestRefresh('session') end
      end

      local function IsSelected(val)
        return grid.sessionFilter == val
      end

      local function Generator(owner, rootDescription)
        rootDescription:CreateTitle('Session')
        rootDescription:CreateRadio('All sessions', IsSelected, SetSession, 'ALL')
        rootDescription:CreateRadio('Current session', IsSelected, SetSession, 'CURRENT')

        local sessions = (RDL.DB and RDL.DB.GetSessions and RDL.DB:GetSessions()) or {}
        if sessions[2] and sessions[2].id ~= nil then
          rootDescription:CreateRadio('Previous session', IsSelected, SetSession, 'PREV')
        end

        local maxOlder = 5
        local added = 0
        for i = 3, #sessions do
          local s = sessions[i]
          local sid = s and (tonumber(s.id) or s.id)
          if sid ~= nil then
            rootDescription:CreateRadio(BuildSessionEntryLabel(s), IsSelected, SetSession, sid)
            added = added + 1
            if added >= maxOlder then break end
          end
        end
      end

      ddSession._rdlMenuGenerator = Generator
      ddSession:SetupMenu(Generator)
      SafeGenerate(ddSession)
    end

  else
    ---------------------------------------------------------------------
    -- Legacy UIDropDownMenuTemplate fallback
    ---------------------------------------------------------------------

    local dd = CreateFrame('Frame', 'RothDevLibKindDropDown', listFrame, 'UIDropDownMenuTemplate')
    dd:SetPoint('TOPLEFT', listFrame, 'TOPLEFT', -10, -4)
    UIDropDownMenu_SetWidth(dd, 80)
    UIDropDownMenu_SetText(dd, 'All')
    grid.kindDropDown = dd
    if Skin and Skin.SkinUIDropDown then
      pcall(function() Skin:SkinUIDropDown(dd, 80) end)
    end

    local function SetKind(k)
      grid.kind = NormalizeKindFilter(k)
      local label = k
      if k == 'ALL' then label = 'All' end
      UIDropDownMenu_SetText(dd, label)
      if UI and UI.RequestRefresh then UI:RequestRefresh('kind') end
    end

    UIDropDownMenu_Initialize(dd, function(_, level)
      local info = UIDropDownMenu_CreateInfo()
      local items = {
        { text = 'All',         value = 'ALL' },
        { text = 'LUA_ERROR',   value = 'LUA_ERROR' },
        { text = 'TAINT',       value = 'TAINT' },
        { text = 'LUA_WARNING', value = 'LUA_WARNING' },
        { text = 'SUPPRESSED',  value = 'SUPPRESSED' },
        { text = 'ALERT',       value = 'ALERT' },
        { text = 'ASSERT',      value = 'ASSERT' },
      }
      for _, it in ipairs(items) do
        info.notCheckable = true
        info.text = it.text
        info.value = it.value
        info.func = function() SetKind(it.value) end
        info.checked = (grid.kind == it.value)
        UIDropDownMenu_AddButton(info, level)
      end
    end)

    local ddAddon = CreateFrame('Frame', 'RothDevLibAddonDropDown', listFrame, 'UIDropDownMenuTemplate')
    ddAddon:SetPoint('LEFT', dd, 'RIGHT', -10, 0)
    UIDropDownMenu_SetWidth(ddAddon, 110)
    UIDropDownMenu_SetText(ddAddon, 'All addons')
    grid.addonDropDown = ddAddon
    if Skin and Skin.SkinUIDropDown then
      pcall(function() Skin:SkinUIDropDown(ddAddon, 110) end)
    end

    local function SetAddon(a)
      a = tostring(a or 'ALL')
      if a == '' then a = 'ALL' end
      grid.addon = a
      UIDropDownMenu_SetText(ddAddon, (a == 'ALL') and 'All addons' or a)
      if UI and UI.RequestRefresh then UI:RequestRefresh('addon') end
    end

    UIDropDownMenu_Initialize(ddAddon, function(_, level)
      local info = UIDropDownMenu_CreateInfo()
      local list = grid._addonList
      if not list then
        if UI and UI._RebuildAddonDropdown then UI:_RebuildAddonDropdown() end
        list = grid._addonList or { 'ALL' }
      end
      for _, a in ipairs(list) do
        info.notCheckable = true
        info.text = (a == 'ALL') and 'All addons' or a
        info.value = a
        info.func = function() SetAddon(a) end
        info.checked = (grid.addon == a)
        UIDropDownMenu_AddButton(info, level)
      end
    end)

    local chkShow = CreateFrame('CheckButton', nil, listFrame, 'UICheckButtonTemplate')
    chkShow:SetPoint('LEFT', ddAddon, 'RIGHT', 2, 0)
    chkShow:SetSize(22, 22)
    do
      local t = chkShow.text or chkShow.Text
      if t and t.SetText then
        t:SetText('Ign')
        if t.SetFontObject then t:SetFontObject('GameFontNormalSmall') end
      end
    end
    chkShow:SetChecked(false)
    chkShow:SetScript('OnClick', function(btn)
      grid.showIgnored = btn:GetChecked() and true or false
      if UI and UI.RequestRefresh then UI:RequestRefresh('ignored') end
    end)
    grid.showIgnoredCheck = chkShow

    local ddSession = CreateFrame('Frame', 'RothDevLibSessionDropDown', listFrame, 'UIDropDownMenuTemplate')
    ddSession:SetPoint('LEFT', chkShow, 'RIGHT', 30, 0)
    UIDropDownMenu_SetWidth(ddSession, 120)
    UIDropDownMenu_SetText(ddSession, BuildSessionFilterLabel(grid.sessionFilter))
    grid.sessionDropDown = ddSession
    ddSession:Hide()
    if Skin and Skin.SkinUIDropDown then
      pcall(function() Skin:SkinUIDropDown(ddSession, 120) end)
    end

    local function SetSession(val)
      if val == nil or val == '' then val = 'ALL' end
      if type(val) ~= 'number' then
        val = tostring(val)
        if val ~= 'ALL' and val ~= 'CURRENT' and val ~= 'PREV' then val = 'ALL' end
      end
      grid.sessionFilter = val
      UIDropDownMenu_SetText(ddSession, BuildSessionFilterLabel(val))
      if UI and UI.RequestRefresh then UI:RequestRefresh('session') end
    end

    UIDropDownMenu_Initialize(ddSession, function(_, level)
      local info = UIDropDownMenu_CreateInfo()
      info.notCheckable = true

      info.text = 'All sessions'
      info.func = function() SetSession('ALL') end
      info.checked = (grid.sessionFilter == 'ALL')
      UIDropDownMenu_AddButton(info, level)

      info.text = 'Current session'
      info.func = function() SetSession('CURRENT') end
      info.checked = (grid.sessionFilter == 'CURRENT')
      UIDropDownMenu_AddButton(info, level)

      local sessions = (RDL.DB and RDL.DB.GetSessions and RDL.DB:GetSessions()) or {}
      if sessions[2] and sessions[2].id ~= nil then
        info.text = 'Previous session'
        info.func = function() SetSession('PREV') end
        info.checked = (grid.sessionFilter == 'PREV')
        UIDropDownMenu_AddButton(info, level)
      end

      local maxOlder = 5
      local added = 0
      for i = 3, #sessions do
        local s = sessions[i]
        local sid = s and (tonumber(s.id) or s.id)
        if sid ~= nil then
          info.text = BuildSessionEntryLabel(s)
          local selectedSid = sid
          info.func = function() SetSession(selectedSid) end
          info.checked = (grid.sessionFilter == selectedSid)
          UIDropDownMenu_AddButton(info, level)
          added = added + 1
          if added >= maxOlder then break end
        end
      end
    end)
  end

  -----------------------------------------------------------------------
  -- Column headers
  -----------------------------------------------------------------------
  grid.headers = {}
  local hx = 6
  local hy = -FILTER_H - 2

  local headerBg = listFrame:CreateTexture(nil, "BACKGROUND")
  headerBg:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 2, hy + 1)
  headerBg:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -2, hy + 1)
  headerBg:SetHeight(HEADER_H + 2)
  if C then
    SetSolid(headerBg, C.titleBg[1], C.titleBg[2], C.titleBg[3], C.titleBg[4])
  else
    SetSolid(headerBg, 0.13, 0.13, 0.15, 1)
  end
  grid.headerBg = headerBg

  for i, c in ipairs(COLS) do
    local w = (grid.colW and grid.colW[c.key]) or c.w
    if i == #COLS then
      local wKind  = (grid.colW and grid.colW.kind)  or COLS[1].w
      local wAddon = (grid.colW and grid.colW.addon) or COLS[2].w
      local wCount = (grid.colW and grid.colW.count) or COLS[3].w
      local wLast  = (grid.colW and grid.colW.last)  or COLS[4].w
      w = (listFrame:GetWidth() - hx - 20) - (wKind + wAddon + wCount + wLast)
      if w < 80 then w = 80 end
    end
    local hb = CreateFrame("Button", nil, listFrame)
    hb:SetSize(w, HEADER_H)
    if hb.SetFrameLevel and listFrame and listFrame.GetFrameLevel then
      hb:SetFrameLevel((listFrame:GetFrameLevel() or 0) + 2)
    end
    hb:SetPoint("TOPLEFT", listFrame, "TOPLEFT", hx, hy)
    hb._key = c.key
    hb._label = c.label
    hb.txt = hb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hb.txt:SetPoint("LEFT", hb, "LEFT", 2, 0)
    hb.txt:SetText(c.label)
    if C then
      hb.txt:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3], C.textBright[4])
    end

    hb:SetScript("OnClick", function(btn)
      local key = btn._key
      if key == "last" then key = "lastSeen" end
      if key == "msg" then key = "message" end
      if grid.sortKey == key then
        grid.sortAsc = not grid.sortAsc
      else
        grid.sortKey = key
        if key == "lastSeen" or key == "count" then grid.sortAsc = false else grid.sortAsc = true end
      end
      if UI and UI.RequestRefresh then UI:RequestRefresh("sort") end
    end)

    -- Resizable columns: grip between header columns
    if c.key ~= "msg" then
      local grip = CreateFrame("Frame", nil, hb)
      grip:SetPoint("TOPRIGHT", hb, "TOPRIGHT", 4, 0)
      grip:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", 4, 0)
      grip:SetWidth(8)
      grip:EnableMouse(true)
      grip._colKey = c.key
      grip._colMin = c.min
      grip._colMax = c.max
      hb._grip = grip

      local function CursorOn()
        if type(SetCursor) == "function" then
          pcall(function() SetCursor("UI_RESIZE_CURSOR") end)
        end
      end
      local function CursorOff()
        if type(ResetCursor) == "function" then
          pcall(function() ResetCursor() end)
        end
      end

      grip:SetScript("OnEnter", CursorOn)
      grip:SetScript("OnLeave", CursorOff)
      grip:SetScript("OnMouseDown", function(_, btn)
        if btn ~= "LeftButton" then return end
        local scale = (listFrame and listFrame.GetEffectiveScale) and listFrame:GetEffectiveScale() or 1
        local cx = (type(GetCursorPosition) == "function") and select(1, GetCursorPosition()) or 0
        cx = cx / (scale or 1)

        grid._resizing = {
          key = grip._colKey,
          min = grip._colMin,
          max = grip._colMax,
          startX = cx,
          startW = (grid.colW and grid.colW[grip._colKey]) or c.w,
          lastApply = 0,
        }

        if not grid._resizeDriver then
          local d = CreateFrame("Frame", nil, UIParent)
          d:SetAllPoints(UIParent)
          d:EnableMouse(true)
          d:SetFrameStrata("TOOLTIP")
          d:Hide()

          d:SetScript("OnMouseUp", function()
            if grid._resizeDriver then grid._resizeDriver:Hide() end
            grid._resizing = nil
            CursorOff()
            local s = RDL.DB and RDL.DB.raw and RDL.DB.raw.settings or nil
            if s then
              s.uiGroupGridCols = s.uiGroupGridCols or {}
              for _, c2 in ipairs(COLS) do
                if c2.key ~= "msg" then
                  s.uiGroupGridCols[c2.key] = grid.colW and grid.colW[c2.key] or c2.w
                end
              end
            end
          end)

          d:SetScript("OnUpdate", function()
            local r = grid._resizing
            if not r then d:Hide() return end
            local now = (type(GetTime) == "function") and GetTime() or 0
            if (now - (r.lastApply or 0)) < 0.02 then return end
            r.lastApply = now

            local sc = (listFrame and listFrame.GetEffectiveScale) and listFrame:GetEffectiveScale() or 1
            local x = (type(GetCursorPosition) == "function") and select(1, GetCursorPosition()) or 0
            x = x / (sc or 1)
            local dw = x - (r.startX or x)
            local nw = (r.startW or 0) + dw
            if r.min and nw < r.min then nw = r.min end
            if r.max and nw > r.max then nw = r.max end
            grid.colW = grid.colW or {}
            grid.colW[r.key] = nw
            if UI and UI.ApplyGroupGridLayout then
              UI:ApplyGroupGridLayout("colresize")
            end
          end)
          grid._resizeDriver = d
        end

        grid._resizeDriver:Show()
      end)
    end

    grid.headers[i] = hb
    hx = hx + w + 4
  end

  -----------------------------------------------------------------------
  -- v3: Row parent + row pool + scroll bar (simple & reliable)
  -----------------------------------------------------------------------
  grid._hy = hy

  -- Row container (clips rows)
  local rowParent = CreateFrame("Frame", nil, listFrame)
  rowParent:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, hy - HEADER_H - 4)
  rowParent:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -22, 6)
  rowParent:SetClipsChildren(true)
  grid.rowParent = rowParent

  -- Scroll bar
  local scrollBar
  local okBar = pcall(function()
    scrollBar = CreateFrame("Slider", "RothDevLibGroupScrollBar", listFrame, "UIPanelScrollBarTemplate")
  end)
  if not okBar or not scrollBar then
    scrollBar = CreateFrame("Slider", "RothDevLibGroupScrollBar", listFrame)
    scrollBar:SetWidth(16)
    local bg = scrollBar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(scrollBar)
    SetSolid(bg, 0.1, 0.1, 0.1, 0.5)
    local thumb = scrollBar:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(16, 24)
    SetSolid(thumb, 0.4, 0.4, 0.4, 0.8)
    scrollBar:SetThumbTexture(thumb)
  end
  scrollBar:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -6, hy - HEADER_H - 4 - 16)
  scrollBar:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -6, 6 + 16)
  scrollBar:SetScript("OnValueChanged", function(_, value)
    grid.scrollOffset = math.floor(value + 0.5)
    if UI._FillVisibleRows then UI:_FillVisibleRows() end
  end)
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetMinMaxValues(0, 0)
  scrollBar:SetValueStep(1)
  scrollBar:SetValue(0)
  scrollBar:SetObeyStepOnDrag(true)
  grid.scrollBar = scrollBar

  -- Mouse wheel on row parent
  rowParent:EnableMouseWheel(true)
  rowParent:SetScript("OnMouseWheel", function(_, delta)
    local cur = grid.scrollOffset or 0
    local newVal = math.max(0, cur - delta * 3)
    grid.scrollOffset = newVal
    scrollBar:SetValue(newVal)
  end)

  -- Also mouse wheel on listFrame itself (headers area)
  listFrame:EnableMouseWheel(true)
  listFrame:SetScript("OnMouseWheel", function(_, delta)
    local cur = grid.scrollOffset or 0
    local newVal = math.max(0, cur - delta * 3)
    grid.scrollOffset = newVal
    scrollBar:SetValue(newVal)
  end)

  -- Create row pool
  grid.rowPool = {}
  for i = 1, MAX_ROW_POOL do
    local row = CreateFrame("Button", nil, rowParent, "BackdropTemplate")
    row:SetHeight(ROW_H)
    self:_InitRow(row, rowParent)
    row:Hide()
    grid.rowPool[i] = row
  end

  -- Auto-resize
  if listFrame.HookScript then
    listFrame:HookScript("OnSizeChanged", function()
      if UI and UI.RequestGroupGridLayout then
        UI:RequestGroupGridLayout("resize")
      end
    end)

    listFrame:HookScript("OnHide", function()
      if grid and grid._resizeDriver then pcall(function() grid._resizeDriver:Hide() end) end
      if grid then grid._resizing = nil end
    end)
  end

  -- First paint
  if self.ApplyGroupGridLayout then
    self:ApplyGroupGridLayout("init")
  else
    self:UpdateGroupGrid()
  end
end

---------------------------------------------------------------------------
-- Build filtered+sorted group list
---------------------------------------------------------------------------
function UI:_BuildFilteredGroups()
  local grid = self.groupGrid
  if not grid or not RDL.DB then return {} end

  local q = Lower(grid.query)
  local wantQuery = (q ~= nil and q ~= "")
  local kindFilter = NormalizeKindFilter(grid.kind)
  local addonFilter = tostring(grid.addon or "ALL")
  local showIgnored = grid.showIgnored and true or false
  local sessionFilter, sessionScoped, sessionId = ResolveSessionContext(RDL.DB, grid.sessionFilter)

  if grid.sessionFilter ~= sessionFilter then
    grid.sessionFilter = sessionFilter
    if grid.sessionDropDown then
      if UI and UI.Menu and UI.Menu.SafeGenerate and grid.sessionDropDown.GenerateMenu then
        pcall(function() UI.Menu:SafeGenerate(grid.sessionDropDown) end)
      elseif type(UIDropDownMenu_SetText) == 'function' then
        UIDropDownMenu_SetText(grid.sessionDropDown, BuildSessionFilterLabel(sessionFilter))
      end
    end
  end

  local out = {}
  local iter, state, var
  if sessionScoped then
    if sessionId ~= nil and RDL.DB.IterSessionGroups then
      iter, state, var = RDL.DB:IterSessionGroups(sessionId)
    else
      iter = function() return nil end
      state, var = nil, nil
    end
  else
    iter, state, var = RDL.DB:IterGroups()
  end

  for sig, g in iter, state, var do
    if g then
      if g.sig == nil or g.sig == "" then g.sig = sig end
      g._sig = sig
      if PassesFilters(sig, g, kindFilter, addonFilter, showIgnored, wantQuery, q) then
        table.insert(out, g)
      end
    end
  end

  -- Sort
  local key = grid.sortKey or "lastSeen"
  local asc = grid.sortAsc and true or false

  local function cmp(a, b)
    if key == "count" or key == "lastSeen" then
      local av = tonumber(a[key]) or 0
      local bv = tonumber(b[key]) or 0
      if av == bv then
        return (tonumber(a.lastSeen) or 0) > (tonumber(b.lastSeen) or 0)
      end
      if asc then return av < bv else return av > bv end
    else
      local av = Lower(a[key])
      local bv = Lower(b[key])
      if av == bv then
        return (tonumber(a.lastSeen) or 0) > (tonumber(b.lastSeen) or 0)
      end
      if asc then return av < bv else return av > bv end
    end
  end

  table.sort(out, cmp)
  return out
end

---------------------------------------------------------------------------
-- Update grid display
---------------------------------------------------------------------------
function UI:UpdateGroupGrid()
  local grid = self.groupGrid
  if not grid then return end

  local ok, err = pcall(function()
    if UI and UI._RebuildAddonDropdown then UI:_RebuildAddonDropdown() end
    local groups = self:_BuildFilteredGroups()
    grid._groups = groups

    local total = #groups

    -- Auto-select first visible group when selection is empty or filtered out
    local selected = UI.selectedSig
    local found = false
    if selected and selected ~= "" then
      for j = 1, total do
        local sg = groups[j]
        local ss = sg and (sg.sig or sg._sig)
        if ss == selected then found = true break end
      end
    end

    if total <= 0 then
      UI.selectedSig = nil
      if UI.UpdateDetailView then
        UI:UpdateDetailView(nil)
      end
    elseif not found then
      local first = groups[1]
      local firstSig = first and (first.sig or first._sig)
      if firstSig and firstSig ~= "" then
        UI.selectedSig = firstSig
        if UI.ShowGroup then UI:ShowGroup(firstSig) end
      end
    end

    -- Sort arrows
    for _, hb in ipairs(grid.headers or {}) do
      local k = hb._key
      if k == "last" then k = "lastSeen" end
      if k == "msg" then k = "message" end
      SetSortArrow(hb, (grid.sortKey == k), grid.sortAsc)
    end

    -- Fill visible rows
    UI:_FillVisibleRows()
  end)

  if ok then
    grid._lastUpdateError = nil
    grid._lastUpdateErrorTs = nil
  else
    grid._lastUpdateError = tostring(err)
    grid._lastUpdateErrorTs = time()
    if RDL and RDL.Log then
      pcall(function() RDL:Log("ERROR", "UI", "UpdateGroupGrid failed", { err = tostring(err) }) end)
    end
  end
end

---------------------------------------------------------------------------
-- Addon dropdown rebuild
---------------------------------------------------------------------------
function UI:_RebuildAddonDropdown()
  local grid = self.groupGrid
  if not grid or not RDL.DB or not RDL.DB.IterGroups then return end

  local showIgnored = grid.showIgnored and true or false
  local _, sessionScoped, sessionId = ResolveSessionContext(RDL.DB, grid.sessionFilter)
  local iter, state, var
  if sessionScoped then
    if sessionId ~= nil and RDL.DB.IterSessionGroups then
      iter, state, var = RDL.DB:IterSessionGroups(sessionId)
    else
      iter = function() return nil end
      state, var = nil, nil
    end
  else
    iter, state, var = RDL.DB:IterGroups()
  end

  local seen = {}
  for sig, g in iter, state, var do
    if g and g.addon and g.addon ~= "" then
      if showIgnored then
        seen[g.addon] = true
      else
        if not (RDL.DB.IsIgnored and RDL.DB:IsIgnored(sig, g.addon, g.message)) then
          seen[g.addon] = true
        end
      end
    end
  end

  local list = { "ALL" }
  local addons = {}
  for a in pairs(seen) do table.insert(addons, a) end
  table.sort(addons, function(a, b) return Lower(a) < Lower(b) end)
  for _, a in ipairs(addons) do table.insert(list, a) end
  grid._addonList = list

  if grid.addon ~= "ALL" and not seen[grid.addon] then
    grid.addon = "ALL"
    if grid.addonDropDown then
      if UI and UI.Menu and UI.Menu.SafeGenerate and grid.addonDropDown.GenerateMenu then
        pcall(function() UI.Menu:SafeGenerate(grid.addonDropDown) end)
      elseif type(UIDropDownMenu_SetText) == 'function' then
        UIDropDownMenu_SetText(grid.addonDropDown, "All addons")
      end
    end
  end
end

---------------------------------------------------------------------------
-- Layout recalculation
---------------------------------------------------------------------------
function UI:RequestGroupGridLayout(reason)
  local grid = self.groupGrid
  if not grid or not grid.listFrame then return end
  if grid._layoutPending then return end
  grid._layoutPending = true

  local function Apply()
    grid._layoutPending = false
    if UI and UI.ApplyGroupGridLayout then
      UI:ApplyGroupGridLayout(reason)
    end
  end

  if C_Timer and C_Timer.After then
    C_Timer.After(0, Apply)
  else
    Apply()
  end
end

function UI:ApplyGroupGridLayout(reason)
  local grid = self.groupGrid
  if not grid or not grid.listFrame then return end

  local listFrame = grid.listFrame
  local w = tonumber(listFrame:GetWidth() or 0) or 0
  local hy = grid._hy or (-FILTER_H - 2)

  -- Header bg
  if grid.headerBg then
    grid.headerBg:ClearAllPoints()
    grid.headerBg:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 2, hy + 1)
    grid.headerBg:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -2, hy + 1)
    grid.headerBg:SetHeight(HEADER_H + 2)
  end

  -- Column widths
  local hx = 6
  local gap = 4
  local usable = math.max(0, w - hx - 30)

  local wKind  = (grid.colW and grid.colW.kind)  or COLS[1].w
  local wAddon = (grid.colW and grid.colW.addon) or COLS[2].w
  local wCount = (grid.colW and grid.colW.count) or COLS[3].w
  local wLast  = (grid.colW and grid.colW.last)  or COLS[4].w

  local fixed = (wKind or 0) + (wAddon or 0) + (wCount or 0) + (wLast or 0)
  fixed = fixed + gap * (#COLS - 1)
  local lastW = usable - fixed
  if lastW < 80 then lastW = 80 end

  grid._colWidths = {
    kind = wKind,
    addon = wAddon,
    count = wCount,
    last = wLast,
    msg = lastW,
  }

  -- Position headers
  if grid.headers and #grid.headers > 0 then
    for i, hb in ipairs(grid.headers) do
      local key = hb and hb._key
      local cw = nil
      if i == #COLS or key == "msg" then
        cw = lastW
      else
        cw = (grid.colW and grid.colW[key]) or (COLS[i].w or 80)
      end
      hb:ClearAllPoints()
      hb:SetSize(cw, HEADER_H)
      hb:SetPoint("TOPLEFT", listFrame, "TOPLEFT", hx, hy)
      hx = hx + cw + gap
    end
  end

  -- Re-anchor row parent + scroll bar
  if grid.rowParent then
    grid.rowParent:ClearAllPoints()
    grid.rowParent:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, hy - HEADER_H - 4)
    grid.rowParent:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -22, 6)
  end

  if grid.scrollBar then
    grid.scrollBar:ClearAllPoints()
    grid.scrollBar:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", -6, hy - HEADER_H - 4 - 16)
    grid.scrollBar:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -6, 6 + 16)
  end

  -- Refill visible rows
  if UI._FillVisibleRows then
    UI:_FillVisibleRows()
  end

  -- Also update grid data
  if UI and UI.UpdateGroupGrid then
    UI:UpdateGroupGrid()
  end
end
