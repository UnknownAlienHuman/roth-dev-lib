-- !RothDevLib/UI/Monitor.lua
-- Monitoring dashboard: live CPU/Mem profiling stats + recent ALERT groups.
-- v2 rewrite:
--   * Panels extracted into _BuildMonitorPanels() for embedding in MainFrame
--   * BuildMonitorContent(parent) — public API for MainFrame Monitor tab
--   * Standalone window still works via /rdev monitor
--   * Dark theme via Skin helpers
--   * Both embedded + standalone share RefreshMonitor()

local RDL = _G.RothDevLib
if not RDL then return end

RDL.UI = RDL.UI or {}
local UI = RDL.UI

local Skin = UI.Skin
local Menu = UI.Menu
local Table = UI.Table

UI._monitor = UI._monitor or { isOpen = false, ticker = nil }

---------------------------------------------------------------------------
-- Helpers (unchanged from v1)
---------------------------------------------------------------------------
local function SafeSort(t)
  table.sort(t, function(a, b)
    local as = tonumber(a and a.score) or 0
    local bs = tonumber(b and b.score) or 0
    if as == bs then
      return tostring(a and a.key or "") < tostring(b and b.key or "")
    end
    return as > bs
  end)
end

local function Clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function FormatStatLine(kind, key, s)
  local ema = tonumber(s and s.ema) or 0
  local last = tonumber(s and s.last) or 0
  local mx = tonumber(s and s.max) or 0
  local n = tonumber(s and s.n) or 0
  if kind == "CPU" then
    return string.format("%7.2f ema  %7.2f last  %7.2f max  n=%d  %s", ema, last, mx, n, key)
  end
  return string.format("%7.1f emaKB %7.1f lastKB %7.1f maxKB n=%d  %s", ema, last, mx, n, key)
end

local function CollectTopStats(stats, topN, minN)
  local out = {}
  if type(stats) ~= "table" then return out end
  local filter = UI._monitor.filterText and UI._monitor.filterText:lower() or nil
  for key, s in pairs(stats) do
    if not filter or key:lower():find(filter, 1, true) then
      local n = tonumber(s and s.n) or 0
      if n >= (minN or 1) then
        local score = tonumber(s and s.ema) or 0
        out[#out + 1] = { key = key, s = s, score = score }
      end
    end
  end
  SafeSort(out)
  if topN and #out > topN then
    for i = #out, topN + 1, -1 do out[i] = nil end
  end
  return out
end

local function CollectRecentAlerts(limit)
  local out = {}
  if not (RDL.DB and RDL.DB.IterGroups) then return out end
  local filter = UI._monitor.filterText and UI._monitor.filterText:lower() or nil
  for sig, g in RDL.DB:IterGroups() do
    if g and g.kind == "ALERT" and not (RDL.DB.IsIgnored and RDL.DB:IsIgnored(sig, g.addon, g.message)) then
      local searchable = (sig or "") .. (g.addon or "") .. (g.code or "") .. (g.message or "")
      if not filter or searchable:lower():find(filter, 1, true) then
        out[#out + 1] = {
          sig = sig, addon = g.addon, code = g.code,
          msg = g.message, ts = g.lastTs or g.firstTs or 0,
          count = g.count or 0,
        }
      end
    end
  end
  table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
  limit = tonumber(limit) or 12
  if #out > limit then
    for i = #out, limit + 1, -1 do out[i] = nil end
  end
  return out
end

local function CollectBusLines(limit)
  limit = tonumber(limit) or 60
  if limit < 5 then limit = 5 end
  local lines = {}
  if not (RDL.Bus and RDL.Bus.GetAllAddonNames and RDL.Bus.GetBreadcrumbSnapshot) then
    lines[1] = "(bus module unavailable)"
    return lines
  end

  local names = {}
  local selectedAddon = UI._monitor.busAddonFilter
  if selectedAddon and selectedAddon ~= "" then
    names[1] = selectedAddon
  else
    names = RDL.Bus:GetAllAddonNames() or {}
  end
  table.sort(names, function(a, b) return tostring(a) < tostring(b) end)

  local filter = UI._monitor.filterText and UI._monitor.filterText:lower() or nil
  local perAddon = 8

  for _, addonName in ipairs(names) do
    local crumbs = RDL.Bus:GetBreadcrumbSnapshot(addonName, perAddon) or nil
    if crumbs and #crumbs > 0 then
      local emittedHeader = false
      for _, c in ipairs(crumbs) do
        local ts = c.ts and date("%H:%M:%S", c.ts) or "--:--:--"
        local cat = tostring(c.cat or "?")
        local msg = tostring(c.msg or "")
        local data = tostring(c.data or "")
        local hay = (addonName .. " " .. cat .. " " .. msg .. " " .. data):lower()
        if (not filter) or hay:find(filter, 1, true) then
          if not emittedHeader then
            lines[#lines + 1] = ("[%s]"):format(tostring(addonName))
            emittedHeader = true
          end
          local line = ("  %s [%s] %s"):format(ts, cat, msg)
          if data ~= "" then
            if #data > 120 then data = data:sub(1, 120) .. "..." end
            line = line .. " | " .. data
          end
          lines[#lines + 1] = line
          if #lines >= limit then return lines end
        end
      end
    end
  end

  if #lines == 0 then lines[1] = "(no breadcrumbs)" end
  return lines
end

-- Structured Bus rows for ScrollBox tables.
local function CollectBusRows(limit)
  limit = tonumber(limit) or 80
  if limit < 5 then limit = 5 end
  local rows = {}
  if not (RDL.Bus and RDL.Bus.GetAllAddonNames and RDL.Bus.GetBreadcrumbSnapshot) then
    rows[1] = { ts = 0, addon = "?", cat = "?", msg = "(bus module unavailable)", data = "" }
    return rows
  end

  local names = {}
  local selectedAddon = UI._monitor.busAddonFilter
  if selectedAddon and selectedAddon ~= "" then
    names[1] = selectedAddon
  else
    names = RDL.Bus:GetAllAddonNames() or {}
  end
  table.sort(names, function(a, b) return tostring(a) < tostring(b) end)

  local filter = UI._monitor.filterText and UI._monitor.filterText:lower() or nil
  local perAddon = 10

  for _, addonName in ipairs(names) do
    local crumbs = RDL.Bus:GetBreadcrumbSnapshot(addonName, perAddon) or nil
    if crumbs and #crumbs > 0 then
      for _, c in ipairs(crumbs) do
        local ts = tonumber(c.ts) or 0
        local cat = tostring(c.cat or "?")
        local msg = tostring(c.msg or "")
        local data = tostring(c.data or "")
        local hay = (addonName .. " " .. cat .. " " .. msg .. " " .. data):lower()
        if (not filter) or hay:find(filter, 1, true) then
          if #data > 220 then data = data:sub(1, 220) .. "..." end
          rows[#rows + 1] = {
            ts = ts,
            time = (ts > 0 and date("%H:%M:%S", ts)) or "--:--:--",
            addon = tostring(addonName),
            cat = cat,
            msg = (#msg > 180) and (msg:sub(1, 180) .. "...") or msg,
            data = data,
          }
          if #rows >= limit then return rows end
        end
      end
    end
  end

  if #rows == 0 then
    rows[1] = { ts = 0, addon = "", cat = "", msg = "(no breadcrumbs)", data = "" }
  end
  return rows
end

---------------------------------------------------------------------------
-- _BuildMonitorPanels(parent, stateKey)
-- Creates CPU/Mem/Alerts/Bus panels inside parent.
-- Returns a refs table stored as an "instance".
---------------------------------------------------------------------------
function UI:_BuildMonitorPanels(parent, stateKey)
  if not parent then return nil end

  local C = Skin and Skin.C
  local inst = {}

  -- Summary line
  local summary = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  summary:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -6)
  summary:SetJustifyH("LEFT")
  summary:SetText("")
  if C then summary:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3]) end
  inst.summary = summary

  -- Search box (filter for all panels)
  local search
  if Skin and Skin.SearchBox then
    search = Skin:SearchBox(parent, 160, 18)
  else
    search = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    search:SetSize(160, 18)
    search:SetAutoFocus(false)
    search:SetFontObject(ChatFontSmall)
    search:SetTextInsets(4, 4, 0, 0)
    search:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
  end
  search:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -4)
  search._onChanged = nil
  search:SetScript("OnTextChanged", function(box)
    UI._monitor.filterText = box:GetText() or ""
    if box._placeholder then box._placeholder:SetShown((box:GetText() or "") == "") end
    if box._clearBtn then box._clearBtn:SetShown((box:GetText() or "") ~= "") end
    UI:RefreshMonitor()
  end)
  search:SetScript("OnEscapePressed", function(box) box:SetText(""); box:ClearFocus() end)
  inst.searchBox = search

  -- Pane state
  local paneState = (Skin and Skin.GetPaneState and Skin:GetPaneState(stateKey or "monitorShell")) or {}
  local splitRatio = Clamp(tonumber(paneState.splitRatio) or 0.50, 0.24, 0.76)
  local busAddonFilter = paneState.busAddonFilter
  if type(busAddonFilter) ~= "string" or busAddonFilter == "" then
    busAddonFilter = nil
  end
  UI._monitor.busAddonFilter = busAddonFilter

  -- Persisted sort state (per shell/embed).
  UI._monitor.cpuSortKey = paneState.cpuSortKey or UI._monitor.cpuSortKey or "ema"
  UI._monitor.cpuSortDesc = (paneState.cpuSortDesc ~= false)
  UI._monitor.memSortKey = paneState.memSortKey or UI._monitor.memSortKey or "ema"
  UI._monitor.memSortDesc = (paneState.memSortDesc ~= false)
  UI._monitor.alertSortKey = paneState.alertSortKey or UI._monitor.alertSortKey or "ts"
  UI._monitor.alertSortDesc = (paneState.alertSortDesc ~= false)
  UI._monitor.busSortKey = paneState.busSortKey or UI._monitor.busSortKey or "ts"
  UI._monitor.busSortDesc = (paneState.busSortDesc ~= false)

  local splitterW = 5
  local summaryH = 26
  local alertsHeight = 100
  local busHeight = 100
  local bottomGap = 4

  ---------------------------------------------------------------------------
  -- CPU (left) + Mem (right) panels with vertical splitter
  ---------------------------------------------------------------------------
  local function MakePanel(labelText)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    if Skin and Skin.DarkInset then
      Skin:DarkInset(panel)
    elseif Skin and Skin.ApplyInset then
      Skin:ApplyInset(panel)
    end

    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -6)
    label:SetText(labelText)
    if C then label:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3]) end

    return panel
  end

  local function MakeTextBody(panel)
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, -24)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 6)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    if C then edit:SetTextColor(C.text[1], C.text[2], C.text[3]) end
    local function UpdateWidth()
      local w = (panel.GetWidth and panel:GetWidth() or 400) - 52
      if w < 200 then w = 200 end
      edit:SetWidth(w)
    end
    UpdateWidth()
    if panel.HookScript then panel:HookScript("OnSizeChanged", UpdateWidth) end
    edit:SetText("")
    edit:SetScript("OnEscapePressed", function() edit:ClearFocus() end)
    scroll:SetScrollChild(edit)
    return edit
  end

  local function FmtNum(v, decimals)
    v = tonumber(v) or 0
    if decimals == 1 then
      return string.format("%.1f", v)
    end
    return string.format("%.2f", v)
  end

  local function MakeStatTable(panel, kind)
    if not (Table and Table.Create) then return nil end
    local isCPU = (kind == "cpu")
    local decimals = isCPU and 2 or 1
    local cols = {
      { key = "key",  title = "Key",  w = 260, justify = "LEFT", valueFn = function(d) return d.key end },
      { key = "ema",  title = isCPU and "EMA ms" or "EMA KB", w = 70, justify = "RIGHT", valueFn = function(d) return FmtNum(d.ema, decimals) end },
      { key = "last", title = isCPU and "Last" or "Last",   w = 62, justify = "RIGHT", valueFn = function(d) return FmtNum(d.last, decimals) end },
      { key = "max",  title = "Max",  w = 62, justify = "RIGHT", valueFn = function(d) return FmtNum(d.max, decimals) end },
      { key = "n",    title = "N",    w = 46, justify = "RIGHT", valueFn = function(d) return tostring(tonumber(d.n) or 0) end },
    }

    local sortKey = isCPU and (UI._monitor.cpuSortKey or "ema") or (UI._monitor.memSortKey or "ema")
    local sortDesc = isCPU and (UI._monitor.cpuSortDesc ~= false) or (UI._monitor.memSortDesc ~= false)

    local tv = Table:Create(panel, {
      columns = cols,
      rowTemplate = "RothDevLibMonitorRowTemplate",
      rowH = 18,
      rowGap = 1,
      enableBar = true,
      barAlpha = 0.18,
      barValueFn = function(d) return tonumber(d and d.ema) or 0 end,
      sortKey = sortKey,
      sortDesc = sortDesc,
      onSortChanged = function(k, desc)
        if isCPU then
          UI._monitor.cpuSortKey, UI._monitor.cpuSortDesc = k, desc
        else
          UI._monitor.memSortKey, UI._monitor.memSortDesc = k, desc
        end
        -- Save via closure when available.
        if inst and inst._saveState then pcall(inst._saveState) end
      end,
    })
    return tv
  end

  local leftPanel = MakePanel("Top CPU")
  local rightPanel = MakePanel("Top Mem")

  inst.cpuTable = MakeStatTable(leftPanel, "cpu")
  inst.memTable = MakeStatTable(rightPanel, "mem")
  if not inst.cpuTable then inst.cpuEdit = MakeTextBody(leftPanel) end
  if not inst.memTable then inst.memEdit = MakeTextBody(rightPanel) end

  -- Splitter
  local vSplit = CreateFrame("Button", nil, parent)
  vSplit:SetWidth(splitterW)
  vSplit:EnableMouse(true)
  local splitTex = vSplit:CreateTexture(nil, "BACKGROUND")
  splitTex:SetAllPoints(vSplit)
  if C then
    if splitTex.SetColorTexture then
      splitTex:SetColorTexture(C.splitter[1], C.splitter[2], C.splitter[3], C.splitter[4])
    end
  else
    if splitTex.SetColorTexture then splitTex:SetColorTexture(0.3, 0.3, 0.35, 0.6) end
  end

  local contentBottom = busHeight + bottomGap + alertsHeight + bottomGap

  local function SaveState()
    if Skin and Skin.SavePaneState then
      Skin:SavePaneState(stateKey or "monitorShell", {
        splitRatio = splitRatio,
        busAddonFilter = UI._monitor.busAddonFilter or "",
        cpuSortKey = UI._monitor.cpuSortKey,
        cpuSortDesc = UI._monitor.cpuSortDesc,
        memSortKey = UI._monitor.memSortKey,
        memSortDesc = UI._monitor.memSortDesc,
        alertSortKey = UI._monitor.alertSortKey,
        alertSortDesc = UI._monitor.alertSortDesc,
        busSortKey = UI._monitor.busSortKey,
        busSortDesc = UI._monitor.busSortDesc,
      })
    end
  end

  inst._saveState = SaveState

  local function ComputeSplitBounds(pw)
    local usable = pw - (8 + 8 + splitterW + 8)
    if usable < 1 then usable = 1 end
    local minPane = 180
    local minL = minPane
    local maxL = usable - minPane
    if maxL < minL then maxL = minL end
    return usable, minL, maxL
  end

  local function ApplySplit(save)
    local pw = tonumber(parent:GetWidth() or 800) or 800
    local usable, minL, maxL = ComputeSplitBounds(pw)
    local leftW = Clamp(math.floor(usable * splitRatio + 0.5), minL, maxL)
    splitRatio = Clamp(leftW / math.max(usable, 1), 0.24, 0.76)

    leftPanel:ClearAllPoints()
    rightPanel:ClearAllPoints()
    vSplit:ClearAllPoints()

    leftPanel:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -(summaryH))
    leftPanel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 4, contentBottom)
    leftPanel:SetWidth(leftW)

    vSplit:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 4, 0)
    vSplit:SetPoint("BOTTOMLEFT", leftPanel, "BOTTOMRIGHT", 4, 0)

    rightPanel:SetPoint("TOPLEFT", vSplit, "TOPRIGHT", 4, 0)
    rightPanel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, contentBottom)

    if save then SaveState() end
  end

  local splitDragging = false
  local function StopDrag(save)
    if not splitDragging then return end
    splitDragging = false
    vSplit:SetScript("OnUpdate", nil)
    if save then SaveState() end
  end

  local function UpdateSplitCursor()
    local scale = (parent.GetEffectiveScale and parent:GetEffectiveScale()) or 1
    if scale <= 0 then scale = 1 end
    local cx = GetCursorPosition()
    local leftEdge = parent:GetLeft()
    if not cx or not leftEdge then return end
    local pw = tonumber(parent:GetWidth() or 800) or 800
    local usable, minL, maxL = ComputeSplitBounds(pw)
    local target = (cx / scale) - leftEdge - 4 - 4 - (splitterW * 0.5)
    target = Clamp(target, minL, maxL)
    splitRatio = Clamp(target / math.max(usable, 1), 0.24, 0.76)
    ApplySplit(false)
  end

  vSplit:SetScript("OnMouseDown", function(_, btn)
    if btn ~= "LeftButton" then return end
    splitDragging = true
    vSplit:SetScript("OnUpdate", UpdateSplitCursor)
  end)
  vSplit:SetScript("OnMouseUp", function() StopDrag(true) end)
  vSplit:SetScript("OnHide", function() StopDrag(true) end)

  ---------------------------------------------------------------------------
  -- Alerts panel (bottom)
  ---------------------------------------------------------------------------
  local alertsPanel = MakePanel("Recent ALERTs")
  alertsPanel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 4, busHeight + bottomGap)
  alertsPanel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, busHeight + bottomGap)
  alertsPanel:SetHeight(alertsHeight)
  if Table and Table.Create then
    local cols = {
      { key = "ts",    title = "Time",  w = 58, justify = "LEFT",  valueFn = function(d) return d.time end },
      { key = "addon", title = "Addon", w = 120, justify = "LEFT", valueFn = function(d) return d.addon end },
      { key = "code",  title = "Code",  w = 92, justify = "LEFT",  valueFn = function(d) return d.code end },
      { key = "count", title = "N",     w = 36, justify = "RIGHT", valueFn = function(d) return tostring(d.count or 0) end },
      { key = "msg",   title = "Message", w = 420, justify = "LEFT", valueFn = function(d) return d.msg end },
    }
    inst.alertTable = Table:Create(alertsPanel, {
      columns = cols,
      rowTemplate = "RothDevLibMonitorRowTemplate",
      rowH = 18,
      rowGap = 1,
      sortKey = UI._monitor.alertSortKey or "ts",
      sortDesc = (UI._monitor.alertSortDesc ~= false),
      onRowClick = function(d)
        if d and d.sig and UI and UI.OpenToSig then
          pcall(function() UI:OpenToSig(d.sig) end)
        end
      end,
      onSortChanged = function(k, desc)
        UI._monitor.alertSortKey, UI._monitor.alertSortDesc = k, desc
        if inst and inst._saveState then pcall(inst._saveState) end
      end,
    })
  end
  if not inst.alertTable then
    inst.alertsEdit = MakeTextBody(alertsPanel)
  end

  ---------------------------------------------------------------------------
  -- Bus inspector panel (very bottom)
  ---------------------------------------------------------------------------
  local busPanel = MakePanel("Bus Inspector")
  busPanel:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 4, 2)
  busPanel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, 2)
  busPanel:SetHeight(busHeight)
  if Table and Table.Create then
    local cols = {
      { key = "ts",    title = "Time",  w = 58, justify = "LEFT", valueFn = function(d) return d.time or "--:--:--" end },
      { key = "addon", title = "Addon", w = 120, justify = "LEFT", valueFn = function(d) return d.addon or "" end },
      { key = "cat",   title = "Cat",   w = 72, justify = "LEFT", valueFn = function(d) return d.cat or "" end },
      { key = "msg",   title = "Message", w = 360, justify = "LEFT", valueFn = function(d) return d.msg or "" end },
      { key = "data",  title = "Data",  w = 220, justify = "LEFT", valueFn = function(d) return d.data or "" end },
    }
    inst.busTable = Table:Create(busPanel, {
      columns = cols,
      rowTemplate = "RothDevLibMonitorRowTemplate",
      rowH = 18,
      rowGap = 1,
      sortKey = UI._monitor.busSortKey or "ts",
      sortDesc = (UI._monitor.busSortDesc ~= false),
      onSortChanged = function(k, desc)
        UI._monitor.busSortKey, UI._monitor.busSortDesc = k, desc
        if inst and inst._saveState then pcall(inst._saveState) end
      end,
    })
  end
  if not inst.busTable then
    inst.busEdit = MakeTextBody(busPanel)
  end

  -- Bus addon dropdown (WowStyle dropdown preferred; fallback to UIDropDownMenu).
  local busDD
  local useNew = (Menu and Menu.SupportsWowStyleDropdown and pcall(function() return Menu:SupportsWowStyleDropdown() end))
  if useNew and Menu and Menu.SupportsWowStyleDropdown and Menu:SupportsWowStyleDropdown() then
    busDD = Menu:CreateFilterDropdown(busPanel, nil, 170, "(all addons)", "WowStyle1FilterDropdownTemplate")
    if busDD then
      busDD:SetPoint("TOPLEFT", busPanel, "TOPLEFT", 92, -2)
    end
  else
    busDD = CreateFrame("Frame", nil, busPanel, "UIDropDownMenuTemplate")
    busDD:SetPoint("TOPLEFT", busPanel, "TOPLEFT", 90, 4)
    UIDropDownMenu_SetWidth(busDD, 160)
    UIDropDownMenu_SetText(busDD, UI._monitor.busAddonFilter or "(all)")
  end

  local function SetBusAddonFilter(name)
    if name == nil or name == "" or name == "ALL" then
      UI._monitor.busAddonFilter = nil
      if busDD and busDD.GenerateMenu and Menu and Menu.SafeGenerate then
        pcall(function() Menu:SafeGenerate(busDD) end)
      elseif type(UIDropDownMenu_SetText) == "function" then
        UIDropDownMenu_SetText(busDD, "(all)")
      end
    else
      UI._monitor.busAddonFilter = tostring(name)
      if busDD and busDD.GenerateMenu and Menu and Menu.SafeGenerate then
        pcall(function() Menu:SafeGenerate(busDD) end)
      elseif type(UIDropDownMenu_SetText) == "function" then
        UIDropDownMenu_SetText(busDD, tostring(name))
      end
    end
    SaveState()
    UI:RefreshMonitor()
  end

  local function RebuildBusDD()
    local addonNames = (RDL.Bus and RDL.Bus.GetAllAddonNames and RDL.Bus:GetAllAddonNames()) or {}
    table.sort(addonNames, function(a, b) return tostring(a) < tostring(b) end)

    if busDD and busDD.SetupMenu then
      busDD._addonNames = addonNames

      local function IsSelected(val)
        return tostring(UI._monitor.busAddonFilter or "ALL") == tostring(val or "ALL")
      end

      local function Generator(owner, rootDescription)
        rootDescription:CreateTitle("Bus Addon")
        rootDescription:CreateRadio("(all addons)", IsSelected, SetBusAddonFilter, "ALL")

        local list = busDD._addonNames or {}
        local maxFlat = 40
        if #list <= maxFlat then
          for _, a in ipairs(list) do
            rootDescription:CreateRadio(tostring(a), IsSelected, SetBusAddonFilter, tostring(a))
          end
          return
        end

        local buckets = {}
        for _, a in ipairs(list) do
          local first = a:sub(1, 1):upper()
          if first:match("%a") == nil then first = "#" end
          buckets[first] = buckets[first] or {}
          buckets[first][#buckets[first] + 1] = a
        end
        local keys = {}
        for k in pairs(buckets) do keys[#keys + 1] = k end
        table.sort(keys)

        for _, letter in ipairs(keys) do
          local sub = rootDescription:CreateButton(letter)
          local arr = buckets[letter]
          table.sort(arr, function(a, b) return tostring(a) < tostring(b) end)
          for _, a in ipairs(arr) do
            sub:CreateRadio(tostring(a), IsSelected, SetBusAddonFilter, tostring(a))
          end
        end
      end

      if not busDD._rdlMenuGenerator then
        busDD._rdlMenuGenerator = Generator
        busDD:SetupMenu(Generator)
      end
      if Menu and Menu.SafeGenerate then pcall(function() Menu:SafeGenerate(busDD) end) end

    else
      UIDropDownMenu_Initialize(busDD, function(_, level)
        local info = UIDropDownMenu_CreateInfo()
        info.notCheckable = true
        info.text = "(all addons)"
        info.func = function() SetBusAddonFilter(nil) end
        info.checked = (not UI._monitor.busAddonFilter)
        UIDropDownMenu_AddButton(info, level)
        for _, name in ipairs(addonNames) do
          info.text = tostring(name)
          local sel = tostring(name)
          info.func = function() SetBusAddonFilter(sel) end
          info.checked = (UI._monitor.busAddonFilter == sel)
          UIDropDownMenu_AddButton(info, level)
        end
      end)
      UIDropDownMenu_SetText(busDD, UI._monitor.busAddonFilter or "(all)")
    end
  end
  inst.RebuildBusDD = RebuildBusDD
  RebuildBusDD()

  ---------------------------------------------------------------------------
  -- Resize hook
  ---------------------------------------------------------------------------
  if parent.HookScript then
    parent:HookScript("OnSizeChanged", function()
      ApplySplit(false)
    end)
  end
  ApplySplit(false)

  inst.stateKey = stateKey
  inst.parent = parent
  return inst
end

---------------------------------------------------------------------------
-- BuildMonitorContent(parent) — Public API for MainFrame embed
---------------------------------------------------------------------------
function UI:BuildMonitorContent(parent)
  if not parent then return end
  if self._monitor.embedded then return end -- already built

  local inst = self:_BuildMonitorPanels(parent, "monitorEmbed")
  self._monitor.embedded = inst
end

---------------------------------------------------------------------------
-- InitMonitorFrame — Standalone window (backward compat)
---------------------------------------------------------------------------
function UI:InitMonitorFrame()
  if self._monitor and self._monitor.frame then return end

  local C = Skin and Skin.C

  local f = CreateFrame("Frame", "RothDevLibMonitorFrame", UIParent, "BackdropTemplate")
  self._monitor.frame = f

  if Skin and Skin.DarkFrame then
    Skin:DarkFrame(f, "dialog")
  end
  if Skin and Skin.RestoreFrameState then
    Skin:RestoreFrameState("monitor", f, 980, 560)
  else
    f:SetSize(980, 560)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  if Skin and Skin.AttachFrameStateHandlers then
    Skin:AttachFrameStateHandlers("monitor", f)
  end
  if Skin and Skin.CreateResizeGrip then
    Skin:CreateResizeGrip(f, 820, 520)
  end
  f:Hide()

  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() f:StartMoving() end)
  f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  -- Title bar
  local titleBar = CreateFrame("Frame", nil, f)
  titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  titleBar:SetHeight(28)

  local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
  titleBg:SetAllPoints(titleBar)
  if C then
    if titleBg.SetColorTexture then
      titleBg:SetColorTexture(C.titleBg[1], C.titleBg[2], C.titleBg[3], C.titleBg[4])
    end
  else
    if titleBg.SetColorTexture then titleBg:SetColorTexture(0.13, 0.13, 0.15, 1) end
  end

  local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
  titleText:SetText("RothDevLib - Monitor")
  if C then titleText:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3]) end

  -- Close button
  local closeBtn
  if Skin and Skin.StyledButton then
    closeBtn = Skin:StyledButton(titleBar, "X", 22, 20)
  else
    closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(22, 20)
    closeBtn:SetNormalFontObject(GameFontNormal)
    closeBtn:SetText("X")
  end
  closeBtn:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", -4, -3)
  closeBtn:SetScript("OnClick", function() UI:ToggleMonitor(false) end)

  -- Content area (below title bar)
  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -2)
  content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

  -- Build panels into content area
  local inst = self:_BuildMonitorPanels(content, "monitorShell")
  self._monitor.standalone = inst

  if f.HookScript then
    f:HookScript("OnHide", function()
      if Skin and Skin.SaveFrameState then
        Skin:SaveFrameState("monitor", f)
      end
    end)
  end
end

---------------------------------------------------------------------------
-- BuildMonitorText — shared data builder
---------------------------------------------------------------------------
function UI:_BuildMonitorSnapshot()
  local settings = (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or {}
  local topN = tonumber(settings.monitorTopN) or 20
  local minN = tonumber(settings.monitorMinSamples) or 1

  local cpuStats = (RDL.CPU and RDL.CPU.GetStats) and RDL.CPU:GetStats() or nil
  local memStats = (RDL.Mem and RDL.Mem.GetStats) and RDL.Mem:GetStats() or nil

  local cpuTop = CollectTopStats(cpuStats, topN, minN)
  local memTop = CollectTopStats(memStats, topN, minN)

  local cpuRows = {}
  for i, it in ipairs(cpuTop) do
    local s = it.s or {}
    cpuRows[#cpuRows + 1] = {
      _idx = i,
      key = it.key,
      ema = tonumber(s.ema) or 0,
      last = tonumber(s.last) or 0,
      max = tonumber(s.max) or 0,
      n = tonumber(s.n) or 0,
      _tiebreak = it.key,
    }
  end
  if #cpuRows == 0 then cpuRows[1] = { _idx = 1, key = "(no samples yet)", ema = 0, last = 0, max = 0, n = 0 } end

  local memRows = {}
  for i, it in ipairs(memTop) do
    local s = it.s or {}
    memRows[#memRows + 1] = {
      _idx = i,
      key = it.key,
      ema = tonumber(s.ema) or 0,
      last = tonumber(s.last) or 0,
      max = tonumber(s.max) or 0,
      n = tonumber(s.n) or 0,
      _tiebreak = it.key,
    }
  end
  if #memRows == 0 then memRows[1] = { _idx = 1, key = "(no samples yet)", ema = 0, last = 0, max = 0, n = 0 } end

  local alerts = CollectRecentAlerts(12)
  local alertRows = {}
  for i, a in ipairs(alerts) do
    local ts = tonumber(a.ts) or 0
    local t = (ts > 0) and date("%H:%M:%S", ts) or "--:--:--"
    local msg = tostring(a.msg or ""):gsub("\n", " ")
    if #msg > 200 then msg = msg:sub(1, 200) .. "..." end
    alertRows[#alertRows + 1] = {
      _idx = i,
      ts = ts,
      time = t,
      addon = tostring(a.addon or "?"),
      code = tostring(a.code or "ALERT"),
      count = tonumber(a.count) or 0,
      msg = msg,
      sig = a.sig,
      _tiebreak = tostring(a.sig or i),
    }
  end
  if #alertRows == 0 then alertRows[1] = { _idx = 1, ts = 0, time = "--:--:--", addon = "", code = "", count = 0, msg = "(no alerts)" } end

  local busRows = CollectBusRows(120)
  for i, r in ipairs(busRows) do
    if type(r) == "table" then r._idx = r._idx or i end
  end

  local activeGroups = (RDL.DB and RDL.DB.GetActiveGroupCount) and RDL.DB:GetActiveGroupCount() or 0
  local unread = 0
  if UI and UI.GetUnreadCount then
    local okU, n = pcall(function() return UI:GetUnreadCount() end)
    if okU then unread = tonumber(n) or 0 end
  end
  local sampleRate = tonumber(settings.cpuSampleRate) or 1
  local perfOn = (settings.enablePerfProfiling ~= false) and "on" or "off"
  local busScope = (UI._monitor and UI._monitor.busAddonFilter) and tostring(UI._monitor.busAddonFilter) or "all"
  local sum = string.format(
    "groups=%d  unread=%d  perf=%s  cpuRate=%.2f  memWatch=%s  bus=%s",
    activeGroups, unread, perfOn, sampleRate,
    tostring(settings.memWatchEnabled == true), busScope
  )

  -- Also build legacy text blocks (Export/compat).
  local cpuLines = {}
  for i, it in ipairs(cpuTop) do
    cpuLines[#cpuLines + 1] = string.format("%2d) %s", i, FormatStatLine("CPU", it.key, it.s))
  end
  if #cpuLines == 0 then cpuLines[1] = "(no samples yet)" end

  local memLines = {}
  for i, it in ipairs(memTop) do
    memLines[#memLines + 1] = string.format("%2d) %s", i, FormatStatLine("MEM", it.key, it.s))
  end
  if #memLines == 0 then memLines[1] = "(no samples yet)" end

  local alertLines = {}
  for _, a in ipairs(alerts) do
    local ts = tonumber(a.ts) or 0
    local t = (ts > 0) and date("%H:%M:%S", ts) or "--:--:--"
    local addon = tostring(a.addon or "?")
    local code = tostring(a.code or "ALERT")
    local msg = tostring(a.msg or ""):gsub("\n", " ")
    if #msg > 120 then msg = msg:sub(1, 120) .. "..." end
    alertLines[#alertLines + 1] = string.format("[%s] %s %s x%d - %s", t, addon, code, tonumber(a.count) or 0, msg)
  end
  if #alertLines == 0 then alertLines[1] = "(no alerts)" end

  local busLines = CollectBusLines(64)
  if #busLines == 0 then busLines[1] = "(no breadcrumbs)" end

  return {
    sum = sum,
    cpuRows = cpuRows,
    memRows = memRows,
    alertRows = alertRows,
    busRows = busRows,
    cpuText = table.concat(cpuLines, "\n"),
    memText = table.concat(memLines, "\n"),
    alertsText = table.concat(alertLines, "\n"),
    busText = table.concat(busLines, "\n"),
  }
end

function UI:BuildMonitorText()
  local snap = self:_BuildMonitorSnapshot()
  return snap.sum, snap.cpuText, snap.memText, snap.alertsText, snap.busText
end

function UI:BuildMonitorData()
  local snap = self:_BuildMonitorSnapshot()
  return snap.sum, snap.cpuRows, snap.memRows, snap.alertRows, snap.busRows
end

---------------------------------------------------------------------------
-- RefreshMonitor — updates all visible instances
---------------------------------------------------------------------------
local function RefreshInstance(inst, sum, cpuText, memText, alertsText, busText, cpuRows, memRows, alertRows, busRows)
  if not inst then return end
  if inst.parent and inst.parent.IsShown and not inst.parent:IsShown() then return end
  if inst.RebuildBusDD then inst.RebuildBusDD() end
  if inst.summary then inst.summary:SetText(sum or "") end
  if inst.cpuTable and inst.cpuTable.SetData then inst.cpuTable:SetData(cpuRows or {})
  elseif inst.cpuEdit then inst.cpuEdit:SetText(cpuText or "") end

  if inst.memTable and inst.memTable.SetData then inst.memTable:SetData(memRows or {})
  elseif inst.memEdit then inst.memEdit:SetText(memText or "") end

  if inst.alertTable and inst.alertTable.SetData then inst.alertTable:SetData(alertRows or {})
  elseif inst.alertsEdit then inst.alertsEdit:SetText(alertsText or "") end

  if inst.busTable and inst.busTable.SetData then inst.busTable:SetData(busRows or {})
  elseif inst.busEdit then inst.busEdit:SetText(busText or "") end
end

function UI:RefreshMonitor()
  local mon = self._monitor
  if not mon then return end

  -- Check if anything is visible
  local standaloneVisible = mon.frame and mon.frame.IsShown and mon.frame:IsShown()
  local embeddedVisible = mon.embedded and mon.embedded.parent
    and mon.embedded.parent.IsShown and mon.embedded.parent:IsShown()

  if not standaloneVisible and not embeddedVisible then return end

  local sum, cpuRows, memRows, alertRows, busRows = self:BuildMonitorData()
  local _, cpuText, memText, alertsText, busText = self:BuildMonitorText()
  if standaloneVisible then
    RefreshInstance(mon.standalone, sum, cpuText, memText, alertsText, busText, cpuRows, memRows, alertRows, busRows)
  end
  if embeddedVisible then
    RefreshInstance(mon.embedded, sum, cpuText, memText, alertsText, busText, cpuRows, memRows, alertRows, busRows)
  end
end

---------------------------------------------------------------------------
-- ToggleMonitor — standalone window toggle
---------------------------------------------------------------------------
function UI:ToggleMonitor(force)
  if not (self._monitor and self._monitor.frame) then
    pcall(function() self:InitMonitorFrame() end)
  end
  if not (self._monitor and self._monitor.frame) then return end

  local f = self._monitor.frame
  local wantShow = force
  if wantShow == nil then
    wantShow = not f:IsShown()
  end

  if wantShow then
    f:Show()
    self._monitor.isOpen = true
    self:RefreshMonitor()

    local settings = (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or {}
    local sec = tonumber(settings.monitorRefreshSec) or 1.0
    if sec < 0.2 then sec = 0.2 end

    if type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
      if self._monitor.ticker and type(self._monitor.ticker.Cancel) == "function" then
        pcall(function() self._monitor.ticker:Cancel() end)
      end
      self._monitor.ticker = C_Timer.NewTicker(sec, function()
        pcall(function() UI:RefreshMonitor() end)
      end)
    end
  else
    f:Hide()
    self._monitor.isOpen = false
    if self._monitor.ticker and type(self._monitor.ticker.Cancel) == "function" then
      pcall(function() self._monitor.ticker:Cancel() end)
    end
    self._monitor.ticker = nil
  end
end

---------------------------------------------------------------------------
-- StartEmbeddedTicker / StopEmbeddedTicker — for MainFrame Monitor tab
---------------------------------------------------------------------------
function UI:StartMonitorEmbedTicker()
  if self._monitor._embedTicker then return end

  local settings = (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or {}
  local sec = tonumber(settings.monitorRefreshSec) or 1.0
  if sec < 0.2 then sec = 0.2 end

  if type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
    self._monitor._embedTicker = C_Timer.NewTicker(sec, function()
      pcall(function() UI:RefreshMonitor() end)
    end)
  end
end

function UI:StopMonitorEmbedTicker()
  if self._monitor._embedTicker and type(self._monitor._embedTicker.Cancel) == "function" then
    pcall(function() self._monitor._embedTicker:Cancel() end)
  end
  self._monitor._embedTicker = nil
end
