-- !RothDevLib/UI/Table.lua
-- Lightweight ScrollBox-based table helper for Monitor and other read-only lists.
-- Design goals:
--   * Minimal allocations during refresh.
--   * Deterministic layout (no multiline EditBox).
--   * Optional per-row "bar" visualization.
--
-- Public API:
--   UI.Table:Create(panel, opts) -> tableView
--     opts.columns = { { key, title, w, justify, valueFn, sortFn } ... }
--     opts.rowTemplate (default RothDevLibMonitorRowTemplate)
--     opts.rowH (default 18)
--     opts.rowGap (default 1)
--     opts.enableBar (bool) + opts.barValueFn(rowData) + opts.barAlpha
--     opts.onRowClick(rowData)
--
-- tableView:SetData(array)
-- tableView:SetSort(key[, desc])

local RDL = _G.RothDevLib
if not RDL then return end

RDL.UI = RDL.UI or {}
local UI = RDL.UI

local Skin = UI.Skin

local Table = {}
UI.Table = Table

local function SafeCall(fn, ...)
  local ok, err = pcall(fn, ...)
  return ok, err
end

local function Clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function ScrollBoxAvailable()
  return type(CreateScrollBoxListLinearView) == "function"
    and type(CreateDataProvider) == "function"
    and type(ScrollUtil) == "table"
    and type(ScrollUtil.InitScrollBoxListWithScrollBar) == "function"
end

local function SetSortArrow(btn, active, desc)
  if not btn then return end
  if not btn._arrow then
    local t = btn:CreateTexture(nil, "OVERLAY")
    t:SetSize(12, 12)
    t:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
    t:SetTexture("Interface\\Buttons\\UI-SortArrow")
    btn._arrow = t
  end
  if not active then
    btn._arrow:Hide()
    return
  end
  btn._arrow:Show()
  -- UI-SortArrow points up by default; rotate for asc/desc.
  if btn._arrow.SetRotation then
    btn._arrow:SetRotation(desc and 0 or math.pi)
  end
end

local function MakeHeaderButton(parent, text, w, justify)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(18)
  if b.SetWidth then b:SetWidth(w) end

  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetAllPoints(b)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetText(text or "")
  b.text = fs

  return b
end

local function MakeStatusBar(parent)
  local sb = CreateFrame("StatusBar", nil, parent)
  sb:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
  sb:SetMinMaxValues(0, 1)
  sb:SetValue(0)
  sb:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) - 1)
  if sb.SetAlpha then sb:SetAlpha(0.22) end
  return sb
end

local function BuildRow(tv, row)
  if row._rdlBuilt then return end
  row._rdlBuilt = true

  local C = Skin and Skin.C

  -- zebra bg
  local bg = row:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(row)
  if bg.SetColorTexture then
    if C and C.rowAlt then
      bg:SetColorTexture(C.rowAlt[1], C.rowAlt[2], C.rowAlt[3], C.rowAlt[4])
    else
      bg:SetColorTexture(0.12, 0.12, 0.14, 0.35)
    end
  end
  row._bg = bg

  -- selection highlight
  local sel = row:CreateTexture(nil, "ARTWORK")
  sel:SetAllPoints(row)
  if sel.SetColorTexture then
    if C and C.sel then
      sel:SetColorTexture(C.sel[1], C.sel[2], C.sel[3], C.sel[4])
    else
      sel:SetColorTexture(0.25, 0.35, 0.55, 0.35)
    end
  end
  sel:Hide()
  row._sel = sel

  -- Optional bar fill (behind text)
  if tv.enableBar then
    local bar = MakeStatusBar(row)
    bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    -- width is set per-row update (value-based)
    bar:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    if tv.barAlpha and bar.SetAlpha then
      bar:SetAlpha(tv.barAlpha)
    end
    row._bar = bar
  end

  row._cells = row._cells or {}
  for i, col in ipairs(tv.columns) do
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH(col.justify or "LEFT")
    fs:SetJustifyV("MIDDLE")
    if C and C.text then
      fs:SetTextColor(C.text[1], C.text[2], C.text[3], C.text[4])
    end
    row._cells[i] = fs
  end

  row:SetScript("OnMouseDown", function() end)
  row:SetScript("OnEnter", function(r)
    if r._sel then r._sel:Show() end
  end)
  row:SetScript("OnLeave", function(r)
    if r._sel and (not r._selected) then r._sel:Hide() end
  end)
  row:SetScript("OnClick", function(r)
    if tv and tv.onRowClick and r._data then
      SafeCall(tv.onRowClick, r._data)
    end
  end)
end

local function LayoutRow(tv, row)
  local x = (tv.padL or 6)
  for i, col in ipairs(tv.columns) do
    local fs = row._cells[i]
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", row, "LEFT", x, 0)
    fs:SetPoint("RIGHT", row, "LEFT", x + (col.w or 80), 0)
    x = x + (col.w or 80) + (tv.colGap or 6)
  end
end

local function UpdateRow(tv, row, elementData)
  BuildRow(tv, row)
  LayoutRow(tv, row)

  local d = elementData
  row._data = d

  -- zebra: show every other
  if row._bg then
    local idx = tonumber(d and d._idx) or 0
    row._bg:SetShown((idx % 2) == 0)
  end

  -- bar
  if tv.enableBar and row._bar and tv.barValueFn then
    local v = tonumber(tv.barValueFn(d)) or 0
    local mx = tv._barMax or 1
    if mx <= 0 then mx = 1 end
    row._bar:SetMinMaxValues(0, mx)
    row._bar:SetValue(v)
  end

  for i, col in ipairs(tv.columns) do
    local fs = row._cells[i]
    local v = nil
    if col.valueFn then
      v = col.valueFn(d)
    else
      v = d and d[col.key]
    end
    if v == nil then v = "" end
    fs:SetText(tostring(v))
  end
end

function Table:Create(panel, opts)
  opts = opts or {}
  if not panel then return nil end

  local tv = {}
  tv.panel = panel
  tv.columns = opts.columns or {}
  tv.enableBar = opts.enableBar and true or false
  tv.barValueFn = opts.barValueFn
  tv.barAlpha = opts.barAlpha
  tv.onRowClick = opts.onRowClick
  tv.onSortChanged = opts.onSortChanged
  tv.rowTemplate = opts.rowTemplate or "RothDevLibMonitorRowTemplate"
  tv.rowH = tonumber(opts.rowH) or 18
  tv.rowGap = tonumber(opts.rowGap) or 1
  tv.colGap = tonumber(opts.colGap) or 6
  tv.padL = tonumber(opts.padL) or 6
  tv.sortKey = opts.sortKey
  tv.sortDesc = (opts.sortDesc ~= false) and true or false

  -- Header row
  local header = CreateFrame("Frame", nil, panel)
  header:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -24)
  header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -28, -24)
  header:SetHeight(18)
  tv.header = header

  tv.headerBtns = {}
  local hx = 0
  for i, col in ipairs(tv.columns) do
    local hb = MakeHeaderButton(header, col.title or col.key, col.w or 80, col.justify)
    hb:SetPoint("LEFT", header, "LEFT", hx, 0)
    hb:SetWidth(col.w or 80)
    hb:SetScript("OnClick", function()
      if not col.key then return end
      if tv.sortKey == col.key then
        tv.sortDesc = not tv.sortDesc
      else
        tv.sortKey = col.key
        tv.sortDesc = true
      end
      if tv.onSortChanged then SafeCall(tv.onSortChanged, tv.sortKey, tv.sortDesc) end
      tv:Resort()
    end)
    tv.headerBtns[i] = hb
    hx = hx + (col.w or 80) + tv.colGap
  end

  if ScrollBoxAvailable() then
    tv.mode = "scrollbox"

    local okSB, list = SafeCall(CreateFrame, "Frame", nil, panel, "WowScrollBoxList")
    if okSB and list then
      tv.scrollContainer = list

      -- Resolve actual ScrollBox (template differs by build).
      local sb = list
      if not (sb and sb.SetDataProvider and sb.SetView) then
        sb = list.ScrollBox or list.scrollBox or list.Scrollbox or list.scrollbox or sb
      end
      tv.scrollBox = sb

      -- Resolve/create ScrollBar. Prefer template-provided.
      local bar = list.ScrollBar or list.scrollBar or list.Scrollbar or list.scrollbar
      if not bar then
        local okBar, created = SafeCall(CreateFrame, "Slider", nil, panel, "MinimalScrollBarTemplate")
        if okBar and created then
          bar = created
        else
          bar = CreateFrame("Slider", nil, panel, "UIPanelScrollBarTemplate")
        end
        tv._externalScrollBar = true
      end
      tv.scrollBar = bar

      -- Anchor container below header and reserve right padding for scrollbar.
      list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
      list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -22, 6)

      -- If real ScrollBox is a child, fill container and reserve room for internal scrollbar.
      if sb and sb ~= list and sb.SetPoint then
        SafeCall(sb.ClearAllPoints, sb)
        SafeCall(sb.SetPoint, sb, "TOPLEFT", list, "TOPLEFT", 0, 0)
        local rightPad = 0
        if bar and bar.GetParent and bar:GetParent() == list then
          rightPad = 18
        end
        SafeCall(sb.SetPoint, sb, "BOTTOMRIGHT", list, "BOTTOMRIGHT", -rightPad, 0)
      end

      -- Anchor scrollbar to panel (even if template-provided).
      if bar and bar.SetPoint then
        SafeCall(bar.ClearAllPoints, bar)
        SafeCall(bar.SetPoint, bar, "TOPRIGHT", panel, "TOPRIGHT", -6, -44)
        SafeCall(bar.SetPoint, bar, "BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 6)
        if bar.SetWidth then SafeCall(bar.SetWidth, bar, 16) end
      end

      local view = CreateScrollBoxListLinearView()
      if view.SetElementExtent then view:SetElementExtent(tv.rowH + tv.rowGap) end
      if view.SetPadding then view:SetPadding(2, 2, 2, 2, 0) end

      if view.SetElementInitializer then
        view:SetElementInitializer(tv.rowTemplate, function(row, elementData)
          UpdateRow(tv, row, elementData)
        end)
      end

      tv.view = view
      tv.dp = CreateDataProvider()
      SafeCall(ScrollUtil.InitScrollBoxListWithScrollBar, tv.scrollBox, tv.scrollBar, view)

      function tv:FullUpdate()
        if self.scrollBox and self.scrollBox.FullUpdate then
          SafeCall(self.scrollBox.FullUpdate, self.scrollBox)
        elseif self.scrollBox and self.scrollBox.Update then
          SafeCall(self.scrollBox.Update, self.scrollBox)
        end
      end

      function tv:Resort()
        if self._data then
          self:SetData(self._data)
        end
      end

      function tv:SetSort(key, desc)
        self.sortKey = key
        if desc ~= nil then self.sortDesc = desc and true or false end
        if self.onSortChanged then SafeCall(self.onSortChanged, self.sortKey, self.sortDesc) end
        self:Resort()
      end

      function tv:SetData(arr)
        arr = arr or {}
        self._data = arr

        -- compute bar max
        if self.enableBar and self.barValueFn then
          local mx = 0
          for i = 1, #arr do
            local v = tonumber(self.barValueFn(arr[i])) or 0
            if v > mx then mx = v end
          end
          self._barMax = (mx > 0) and mx or 1
        end

        -- sort
        local sk = self.sortKey
        if sk then
          local desc = self.sortDesc
          table.sort(arr, function(a, b)
            local av = a and (a[sk] ~= nil and a[sk] or (a._sort and a._sort[sk]))
            local bv = b and (b[sk] ~= nil and b[sk] or (b._sort and b._sort[sk]))
            if type(av) == "number" and type(bv) == "number" then
              if av == bv then
                return tostring(a and a._tiebreak or a.key or "") < tostring(b and b._tiebreak or b.key or "")
              end
              if desc then
                return av > bv
              else
                return av < bv
              end
            end
            av = tostring(av or "")
            bv = tostring(bv or "")
            if av == bv then
              return tostring(a and a._tiebreak or a.key or "") < tostring(b and b._tiebreak or b.key or "")
            end
            if desc then
              return av > bv
            else
              return av < bv
            end
          end)
        end

        -- header arrows
        for i, col in ipairs(self.columns) do
          SetSortArrow(self.headerBtns[i], (col.key == self.sortKey), self.sortDesc)
        end

        -- DataProvider rebuild
        local dp = self.dp
        if dp.Flush then dp:Flush()
        elseif dp.RemoveAllData then dp:RemoveAllData() end

        for i = 1, #arr do
          local d = arr[i]
          if type(d) == "table" then
            d._idx = i
          end
          dp:Insert(d)
        end

        if self.scrollBox and self.scrollBox.SetDataProvider then
          SafeCall(self.scrollBox.SetDataProvider, self.scrollBox, dp)
        end

        self:FullUpdate()
      end

      return tv
    end
  end

  tv.mode = "unsupported"
  local msg = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  msg:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -46)
  msg:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
  msg:SetJustifyH("LEFT")
  msg:SetText("RothDevLib: ScrollBox UI API not available on this client build.\nUpdate your game client (12.x+) or disable Monitor tables.")
  tv.unsupportedMsg = msg

  function tv:SetData() end
  function tv:SetSort() end

  return tv
end

