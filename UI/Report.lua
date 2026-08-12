-- !RothDevLib/UI/Report.lua
-- Report builders (text) used by ExportFrame.
-- Ported from RothDevLib/UI/Report.lua.
-- Enhanced: includes locals field in export.

local RDL = _G.RothDevLib
local UI = RDL.UI

local function SafeDate(ts)
  return date("%Y-%m-%d %H:%M:%S", ts or time())
end

local function IsAddonLoadedSafe(name)
  if C_AddOns and C_AddOns.IsAddOnLoaded then
    local ok, v = pcall(C_AddOns.IsAddOnLoaded, name)
    return ok and v and true or false
  end
  return false
end

local function BuildHeader(title)
  local lines = {}
  table.insert(lines, title or "RothDevLib Export")
  table.insert(lines, ("Time: %s"):format(SafeDate(time())))
  table.insert(lines, ("Build: %s"):format(select(4, GetBuildInfo())))
  table.insert(lines, ("Player: %s-%s"):format(UnitName("player") or "<?>", GetRealmName() or "<?>"))
  table.insert(lines, ("Zone: %s / %s"):format(GetRealZoneText() or "<?>", GetSubZoneText() or "<?>"))
  table.insert(lines, "")
  return lines
end

-- Export hardening (Stage 5): deterministic, bounded exports.
local function TrimBytes(s, maxBytes)
  if s == nil then return "" end
  s = tostring(s)
  maxBytes = tonumber(maxBytes) or 0
  if maxBytes <= 0 or #s <= maxBytes then return s end
  return s:sub(1, maxBytes) .. "…"
end

local function StackTopLines(stack, maxLines, maxLineBytes)
  if stack == nil then return "" end
  stack = tostring(stack):gsub("\r", "")
  maxLines = tonumber(maxLines) or 0
  if maxLines <= 0 then return stack end
  maxLineBytes = tonumber(maxLineBytes) or 320
  local out = {}
  local n = 0
  for ln in stack:gmatch("[^\n]+") do
    n = n + 1
    out[#out + 1] = TrimBytes(ln, maxLineBytes)
    if n >= maxLines then break end
  end
  return table.concat(out, "\n")
end

local function CompactMetrics(metrics, maxEntries, maxValueBytes)
  if type(metrics) ~= "table" then return nil end
  maxEntries = tonumber(maxEntries) or 24
  maxValueBytes = tonumber(maxValueBytes) or 180
  local keys = {}
  for k in pairs(metrics) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  local out = {}
  for i = 1, math.min(#keys, maxEntries) do
    local k = keys[i]
    out[#out + 1] = string.format("  - %s = %s", k, TrimBytes(metrics[k], maxValueBytes))
  end
  return (#out > 0) and out or nil
end

local function BuildLimits(settings, opts)
  settings = settings or {}
  opts = opts or {}
  return {
    maxGroups = tonumber(opts.maxGroups) or tonumber(settings.maxGroups) or 200,
    maxOccurrences = tonumber(opts.maxOccurrences) or tonumber(settings.maxOccurrencesPerGroup) or 10,
    maxStackLines = tonumber(opts.maxStackLines) or 80,
    maxStackLineBytes = tonumber(opts.maxStackLineBytes) or 320,
    maxMsgBytes = tonumber(opts.maxMsgBytes) or 2000,
    maxLocalsBytes = tonumber(opts.maxLocalsBytes) or 4096,
    maxDoctorBytes = tonumber(opts.maxDoctorBytes) or 2400,
    maxSysBytes = tonumber(opts.maxSysBytes) or 1800,
    maxBreadcrumbs = tonumber(opts.maxBreadcrumbs) or 12,
    maxBreadcrumbMsgBytes = tonumber(opts.maxBreadcrumbMsgBytes) or 180,
    maxBreadcrumbDataBytes = tonumber(opts.maxBreadcrumbDataBytes) or 220,
    maxMetricEntries = tonumber(opts.maxMetricEntries) or 24,
    maxMetricValueBytes = tonumber(opts.maxMetricValueBytes) or 180,
    maxLogBytes = tonumber(opts.maxLogBytes) or 16000,
  }
end

local function FormatOneGroup(U, g, includeOccurrences, lim)
  local lines = {}
  lim = lim or {}
  table.insert(lines, ("Signature: %s"):format(g.sig or "<?>"))
  table.insert(lines, ("Kind: %s"):format(g.kind or "<?>"))
  table.insert(lines, ("Count: %d"):format(g.count or 0))
  table.insert(lines, ("Addon: %s"):format(g.addon or "<?>"))
  table.insert(lines, ("Func: %s"):format(g.func or "<?>"))
  local extra = g.ctx and g.ctx.extra
  if extra and (extra.faultAddon or extra.wrapperAddon or extra.handlerAddon) then
    table.insert(lines, ("Attribution: fault=%s wrapper=%s handler=%s"):format(
      tostring(extra.faultAddon or g.addon or "<?>"),
      tostring(extra.wrapperAddon or "-"),
      tostring(extra.handlerAddon or "-")
    ))
  end
  if g.origin and (g.origin.file or g.origin.addon) then
    local o = g.origin
    table.insert(lines, ("Origin: addon=%s file=%s line=%s"):format(tostring(o.addon or "<?>"), tostring(o.file or "<?>"), tostring(o.line or "<?>")))
  end
  table.insert(lines, ("First: %s"):format(SafeDate(g.firstSeen)))
  table.insert(lines, ("Last:  %s"):format(SafeDate(g.lastSeen)))
  table.insert(lines, "")

  table.insert(lines, "Message:")
  table.insert(lines, TrimBytes(g.message or "", lim.maxMsgBytes))
  table.insert(lines, "")

  -- Locals (new in !RothDevLib)
  if g.locals and g.locals ~= "" then
    table.insert(lines, "Locals:")
    table.insert(lines, TrimBytes(g.locals, lim.maxLocalsBytes))
    table.insert(lines, "")
  end

  if g.ctx and g.ctx.top then
    table.insert(lines, "Doctor Top:")
    table.insert(lines, TrimBytes(U and U:SafeSerializeTable(g.ctx.top) or "<ctx>", lim.maxDoctorBytes))
    table.insert(lines, "")
  end
  if g.ctx and g.ctx.chain then
    table.insert(lines, "Doctor Chain:")
    table.insert(lines, TrimBytes(U and U:SafeSerializeTable(g.ctx.chain) or "<chain>", lim.maxDoctorBytes))
    table.insert(lines, "")
  end
  if g.ctx and g.ctx.extra then
    table.insert(lines, "Extra:")
    table.insert(lines, TrimBytes(U and U:SafeSerializeTable(g.ctx.extra) or "<extra>", lim.maxDoctorBytes))
    table.insert(lines, "")
  end
  if g.sys then
    table.insert(lines, "System Snapshot:")
    table.insert(lines, TrimBytes(U and U:SafeSerializeTable(g.sys) or "<sys>", lim.maxSysBytes))
    table.insert(lines, "")
  end

  if g.bus then
    local b = g.bus
    if b.breadcrumbs and #b.breadcrumbs > 0 then
      table.insert(lines, "Breadcrumbs (newest first):")
      for i = 1, math.min(#b.breadcrumbs, lim.maxBreadcrumbs or 12) do
        local bc = b.breadcrumbs[i]
        local ts = bc.ts and SafeDate(bc.ts) or "<?>"
        table.insert(lines, ("  - %s [%s] %s"):format(ts, tostring(bc.cat or "<?>"), TrimBytes(tostring(bc.msg or ""), lim.maxBreadcrumbMsgBytes)))
        if bc.data and bc.data ~= "" then
          table.insert(lines, ("      data=%s"):format(TrimBytes(tostring(bc.data), lim.maxBreadcrumbDataBytes)))
        end
      end
      table.insert(lines, "")
    end
    if b.metrics then
      table.insert(lines, "Metrics:")
      local compact = CompactMetrics(b.metrics, lim.maxMetricEntries, lim.maxMetricValueBytes)
      if compact then
        for _, l in ipairs(compact) do table.insert(lines, l) end
      else
        table.insert(lines, TrimBytes(U and U:SafeSerializeTable(b.metrics) or tostring(b.metrics), lim.maxSysBytes))
      end
      table.insert(lines, "")
    end
  end

  table.insert(lines, "Stack:")
  table.insert(lines, StackTopLines(g.stack or "", lim.maxStackLines, lim.maxStackLineBytes))
  table.insert(lines, "")

  if includeOccurrences and g.occurrences and #g.occurrences > 0 then
    table.insert(lines, "Occurrences (newest first):")
    for i = 1, math.min(#g.occurrences, lim.maxOccurrences or 5) do
      local o = g.occurrences[i]
      table.insert(lines, ("  - %s kind=%s addon=%s func=%s"):format(SafeDate(o.ts), o.kind or "<?>", o.addon or "<?>", o.func or "<?>"))
      table.insert(lines, ("    msg=%s"):format(TrimBytes((tostring(o.message or "")):gsub("\n", " "), lim.maxBreadcrumbMsgBytes)))
      local topLine = tostring(o.stack or ""):match("([^\n]*)") or ""
      if topLine ~= "" then
        table.insert(lines, ("    stack.top=%s"):format(TrimBytes(topLine, lim.maxStackLineBytes)))
      end
      if o.sys then
        table.insert(lines, ("    sys=%s"):format(TrimBytes(U and U:SafeSerializeTable(o.sys) or "<sys>", lim.maxSysBytes)))
      end
    end
    table.insert(lines, "")
  end

  return lines
end

function UI:BuildExportAllText(opts)
  opts = opts or {}
  if not RDL.DB or not RDL.DB:IsReady() then return "" end
  local U = RDL.Util
  local settings = RDL.DB:GetSettings() or {}
  local lim = BuildLimits(settings, opts)

  local groups = {}
  for _, g in RDL.DB:IterGroups() do
    table.insert(groups, g)
  end
  table.sort(groups, function(a, b)
    local at = (a.lastSeen or 0)
    local bt = (b.lastSeen or 0)
    if at == bt then
      return tostring(a.sig or "") < tostring(b.sig or "")
    end
    return at > bt
  end)

  local lines = BuildHeader("RothDevLib Export (All)")
  if RDL.DB.session then
    local s = RDL.DB.session
    table.insert(lines, ("Session: id=%s started=%s"):format(tostring(s.id), SafeDate(s.started)))
    table.insert(lines, ("Counts: errors=%d warnings=%d taints=%d suppressed=%d alerts=%d asserts=%d"):format(s.errors or 0, s.warnings or 0, s.taints or 0, s.suppressed or 0, s.alerts or 0, s.asserts or 0))
    table.insert(lines, "")
  end
  table.insert(lines, ("Groups: %d (max=%d)"):format(#groups, settings.maxGroups or 0))
  table.insert(lines, "")

  local includeOccurrences = opts.includeOccurrences and true or false
  local max = math.min(#groups, lim.maxGroups or #groups)
  for i = 1, max do
    local g = groups[i]
    table.insert(lines, ("===== Group %d/%d ====="):format(i, max))
    local one = FormatOneGroup(U, g, includeOccurrences, lim)
    for _, l in ipairs(one) do table.insert(lines, l) end
  end

  if opts.includeLog and RDL.Logger then
    table.insert(lines, "===== RothDevLib Log =====")
    table.insert(lines, TrimBytes(RDL.Logger:GetText() or "", lim.maxLogBytes))
    table.insert(lines, "")
  end

  return table.concat(lines, "\n")
end

-- Export a specific list of group objects (typically the current UI filtered view).
function UI:BuildExportGroupsText(groups, title, opts)
  opts = opts or {}
  if not RDL.DB or not RDL.DB:IsReady() then return "" end
  groups = groups or {}
  local U = RDL.Util
  local settings = RDL.DB:GetSettings() or {}
  local lim = BuildLimits(settings, opts)

  local lines = BuildHeader(title or "RothDevLib Export (View)")
  table.insert(lines, ("Groups: %d (max=%d)"):format(#groups, settings.maxGroups or 0))
  table.insert(lines, "")

  local includeOccurrences = (opts.includeOccurrences ~= false)
  local includeLog = (opts.includeLog == true)
  local max = math.min(#groups, lim.maxGroups or #groups)

  for i = 1, max do
    local g = groups[i]
    table.insert(lines, ("===== Group %d/%d ====="):format(i, max))
    local one = FormatOneGroup(U, g, includeOccurrences, lim)
    for _, l in ipairs(one) do table.insert(lines, l) end
  end

  if includeLog and RDL.Logger then
    table.insert(lines, "===== RothDevLib Log =====")
    table.insert(lines, TrimBytes(RDL.Logger:GetText() or "", lim.maxLogBytes))
    table.insert(lines, "")
  end

  return table.concat(lines, "\n")
end

function UI:BuildExportSelectedText(sig, opts)
  opts = opts or {}
  if not sig or not RDL.DB or not RDL.DB:IsReady() then return "" end
  local g = RDL.DB:GetGroup(sig)
  if not g then return "" end
  local U = RDL.Util
  local settings = RDL.DB:GetSettings() or {}
  local lim = BuildLimits(settings, opts)

  local lines = BuildHeader("RothDevLib Export (Selected)")
  table.insert(lines, "")
  local one = FormatOneGroup(U, g, opts.includeOccurrences ~= false, lim)
  for _, l in ipairs(one) do table.insert(lines, l) end

  if opts.includeLog and RDL.Logger then
    table.insert(lines, "===== RothDevLib Log =====")
    table.insert(lines, TrimBytes(RDL.Logger:GetText() or "", lim.maxLogBytes))
    table.insert(lines, "")
  end

  return table.concat(lines, "\n")
end

-- Filtered export: by addon, kind, or sig
function UI:BuildFilteredExport(opts)
  opts = opts or {}
  if not RDL.DB or not RDL.DB:IsReady() then return "" end
  local U = RDL.Util
  local settings = RDL.DB:GetSettings() or {}
  local lim = BuildLimits(settings, opts)

  local filterAddon = opts.addon   -- string or nil
  local filterKind  = opts.kind    -- string or nil (LUA_ERROR, SUPPRESSED, etc.)
  local filterSig   = opts.sig     -- string or nil (exact signature)

  local groups = {}
  for _, g in RDL.DB:IterGroups() do
    local ok = true
    if filterAddon and g.addon ~= filterAddon then ok = false end
    if filterKind then
      if filterKind == "TAINT" then
        if not (g.kind == "TAINT_BLOCKED" or g.kind == "TAINT_FORBIDDEN" or g.kind == "TAINT_STATE") then ok = false end
      elseif g.kind ~= filterKind then
        ok = false
      end
    end
    if filterSig   and g.sig   ~= filterSig   then ok = false end
    if ok then table.insert(groups, g) end
  end
  table.sort(groups, function(a, b)
    local at = (a.lastSeen or 0)
    local bt = (b.lastSeen or 0)
    if at == bt then
      return tostring(a.sig or "") < tostring(b.sig or "")
    end
    return at > bt
  end)

  local title = "RothDevLib Export (Filtered)"
  if filterAddon then title = title .. " addon=" .. filterAddon end
  if filterKind  then title = title .. " kind="  .. filterKind end
  if filterSig   then title = title .. " sig="   .. filterSig:sub(1, 40) end

  local lines = BuildHeader(title)
  table.insert(lines, ("Matched groups: %d"):format(#groups))
  table.insert(lines, "")

  local max = math.min(#groups, lim.maxGroups or #groups)
  for i = 1, max do
    local g = groups[i]
    table.insert(lines, ("===== Group %d/%d ====="):format(i, max))
    local one = FormatOneGroup(U, g, true, lim)
    for _, l in ipairs(one) do table.insert(lines, l) end
  end

  return table.concat(lines, "\n")
end

-- Convenience: open ExportFrame with a filter
function UI:OpenFilteredExport(opts)
  if not self.ShowExport or not self.BuildFilteredExport then return end
  local text = self:BuildFilteredExport(opts)
  local title = "RothDevLib Export"
  if opts and opts.addon then title = title .. " - " .. tostring(opts.addon) end
  if opts and opts.kind  then title = title .. " - " .. tostring(opts.kind) end
  self:ShowExport(title, text)
end

-- Convenience: export exactly what the group grid is currently showing (query/kind/addon/ignored).
function UI:OpenGridExport(opts)
  if not self.ShowExport or not self.BuildExportGroupsText then return end
  opts = opts or {}

  local grid = self.groupGrid
  local groups = (grid and grid._groups) or nil
  if not groups then
    -- Fallback: best effort.
    if self.OpenExportAll then return self:OpenExportAll() end
    return
  end

  local title = "RothDevLib Export (Filtered View)"
  if grid then
    if grid.kind and grid.kind ~= "ALL" then title = title .. " kind=" .. tostring(grid.kind) end
    if grid.addon and grid.addon ~= "ALL" then title = title .. " addon=" .. tostring(grid.addon) end
    if grid.query and grid.query ~= "" then
      local q = tostring(grid.query)
      if #q > 40 then q = q:sub(1, 40) .. "..." end
      title = title .. " q=\"" .. q .. "\""
    end
    if grid.showIgnored then title = title .. " +ignored" end
  end

  local text = self:BuildExportGroupsText(groups, title, opts)
  self:ShowExport(title, text)
end

function UI:BuildDebugReportText()
  local lines = BuildHeader("RothDevLib Debug Report")
  local settings = (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or {}
  local cap = RDL.Capture

  table.insert(lines, ("Version: %s"):format(tostring(RDL.version or "?")))
  table.insert(lines, "")

  table.insert(lines, "--- Error Handler ---")
  if cap then
    if cap.SyncOwnership then
      pcall(function() cap:SyncOwnership("debug-report") end)
    end

    table.insert(lines, "ownsHandler: " .. tostring(cap.ownsHandler))
    if cap.ownerInfo then
      local oi = cap.ownerInfo
      table.insert(lines, "state: " .. tostring(oi.state or "?"))
      table.insert(lines, "reason: " .. tostring(oi.reason or "?"))
      table.insert(lines, "mode: " .. tostring(oi.mode or "?"))
      table.insert(lines, "nowHandlerAddon: " .. tostring(oi.nowHandlerAddon or "?"))
      table.insert(lines, "nowHandlerSrc: " .. tostring(oi.nowHandlerSrc or "?"))
      table.insert(lines, "seterrorhandlerSrc: " .. tostring(oi.seterrorhandlerSrc or "?"))
      if oi.addons then
        table.insert(lines, "loaded.BugGrabber: " .. tostring(oi.addons.BugGrabber))
        table.insert(lines, "loaded.BugSack: " .. tostring(oi.addons.BugSack))
        table.insert(lines, "loaded.DebugTools: " .. tostring(oi.addons.DebugTools))
      end
    end

    if cap.ProbeSetErrorHandler then
      local p = nil
      pcall(function() p = cap:ProbeSetErrorHandler() end)
      if p then
        table.insert(lines, "setEH.global_ok: " .. tostring(p.global_ok))
        table.insert(lines, "setEH.global_src: " .. tostring(p.global_src))
        table.insert(lines, "setEH.real_ok: " .. tostring(p.real_ok))
        table.insert(lines, "setEH.real_src: " .. tostring(p.real_src))
        table.insert(lines, "setEH.before_addon: " .. tostring(p.before_addon or "?"))
      end
    end

    if cap._fallback then
      local fb = cap._fallback
      table.insert(lines, "fallback.scriptErrorsHooked: " .. tostring(fb.scriptErrorsHooked))
      table.insert(lines, "fallback.bugGrabberEnabled: " .. tostring(fb.bugGrabberEnabled))
      table.insert(lines, "fallback.chatTapHooked: " .. tostring(fb.chatTapHooked))
    end
  else
    table.insert(lines, "Capture: NOT LOADED")
  end
  table.insert(lines, "")

  table.insert(lines, "--- Session ---")
  if RDL.DB and RDL.DB.session then
    local s = RDL.DB.session
    table.insert(lines, "id: " .. tostring(s.id))
    table.insert(lines, "started: " .. SafeDate(s.started))
    table.insert(lines, "character: " .. tostring(s.character or "?"))
    table.insert(lines, "errors: " .. tostring(s.errors or 0))
    table.insert(lines, "warnings: " .. tostring(s.warnings or 0))
    table.insert(lines, "taints: " .. tostring(s.taints or 0))
    table.insert(lines, "suppressed: " .. tostring(s.suppressed or 0))
    table.insert(lines, "alerts: " .. tostring(s.alerts or 0))
    table.insert(lines, "asserts: " .. tostring(s.asserts or 0))
  else
    table.insert(lines, "session: NOT READY")
  end
  table.insert(lines, "")

  table.insert(lines, "--- Database ---")
  local groupCount = 0
  local byKind = {}
  if RDL.DB and RDL.DB.IterGroups then
    for _, g in RDL.DB:IterGroups() do
      groupCount = groupCount + 1
      local k = tostring((g and g.kind) or "?")
      byKind[k] = (byKind[k] or 0) + 1
    end
  end
  table.insert(lines, "groups: " .. tostring(groupCount) .. "/" .. tostring(settings.maxGroups or "?"))
  local kinds = {}
  for k in pairs(byKind) do kinds[#kinds + 1] = k end
  table.sort(kinds)
  for _, k in ipairs(kinds) do
    table.insert(lines, "  " .. k .. ": " .. tostring(byKind[k]))
  end
  local sessions = (RDL.DB and RDL.DB.GetSessions and RDL.DB:GetSessions()) or {}
  table.insert(lines, "sessions: " .. tostring(#sessions))
  table.insert(lines, "")

  table.insert(lines, "--- Storm ---")
  if RDL.Storm and RDL.Storm.GetStats then
    local st = RDL.Storm:GetStats()
    table.insert(lines, "total: " .. tostring(st.total))
    table.insert(lines, "throttled: " .. tostring(st.throttled))
  else
    table.insert(lines, "Storm: NOT LOADED")
  end
  table.insert(lines, "")

  table.insert(lines, "--- Bus ---")
  if RDL.Bus and RDL.Bus.GetAllAddonNames then
    local names = RDL.Bus:GetAllAddonNames()
    if #names == 0 then
      table.insert(lines, "(no registered addons)")
    else
      for _, name in ipairs(names) do
        local st = RDL.Bus.GetAddonStats and RDL.Bus:GetAddonStats(name) or nil
        table.insert(lines, ("  %s: %s/%s"):format(
          tostring(name),
          tostring(st and st.size or 0),
          tostring(st and st.max or 0)
        ))
      end
    end
  else
    table.insert(lines, "Bus: NOT LOADED")
  end
  table.insert(lines, "")

  table.insert(lines, "--- Perf ---")
  table.insert(lines, "enablePerfProfiling: " .. tostring(settings.enablePerfProfiling))
  table.insert(lines, "cpuSampleRate: " .. tostring(settings.cpuSampleRate))
  table.insert(lines, "cpuSpikeMs: " .. tostring(settings.cpuSpikeMs))
  table.insert(lines, "memSpikeKB: " .. tostring(settings.memSpikeKB))
  table.insert(lines, "memWatchEnabled: " .. tostring(settings.memWatchEnabled))
  if RDL.CPU and RDL.CPU.GetStats then
    local n = 0
    for _ in pairs(RDL.CPU:GetStats() or {}) do n = n + 1 end
    table.insert(lines, "cpuStatsKeys: " .. tostring(n))
  end
  if RDL.Mem and RDL.Mem.GetStats then
    local n = 0
    for _ in pairs(RDL.Mem:GetStats() or {}) do n = n + 1 end
    table.insert(lines, "memStatsKeys: " .. tostring(n))
  end
  table.insert(lines, "")

  table.insert(lines, "--- UI ---")
  table.insert(lines, "uiLoaded: " .. tostring(UI and type(UI.Toggle) == "function"))
  table.insert(lines, "uiLiveDisabled: " .. tostring(UI and UI._liveDisabled))
  if UI and UI._lastUIError then
    table.insert(lines, "uiLastError: " .. tostring(UI._lastUIError))
  end
  table.insert(lines, "minimapHidden: " .. tostring(settings.minimap and settings.minimap.hide))
  table.insert(lines, "")

  local evErrs = RDL._eventRegErrors or {}
  if #evErrs > 0 then
    table.insert(lines, "--- Event Registration Errors ---")
    local startAt = math.max(1, #evErrs - 4)
    for i = startAt, #evErrs do
      local e = evErrs[i]
      table.insert(lines, ("  %s -> %s"):format(tostring(e and e.event or "?"), tostring(e and e.err or "?")))
    end
    table.insert(lines, "")
  end

  table.insert(lines, "--- Related Addons ---")
  local candidates = { "!BugGrabber", "BugSack", "!Swatter", "TekErr", "ErrorMonster" }
  for _, name in ipairs(candidates) do
    local loaded = false
    if C_AddOns and C_AddOns.IsAddOnLoaded then
      local ok, v = pcall(C_AddOns.IsAddOnLoaded, name)
      loaded = ok and v and true or false
    elseif IsAddOnLoaded then
      local ok, v = pcall(IsAddOnLoaded, name)
      loaded = ok and v and true or false
    end

    if loaded then
      local ver = nil
      if C_AddOns and C_AddOns.GetAddOnMetadata then
        local ok, v = pcall(C_AddOns.GetAddOnMetadata, name, "Version")
        if ok then ver = v end
      end
      table.insert(lines, ("  %s: LOADED%s"):format(name, ver and (" v" .. tostring(ver)) or ""))
    else
      table.insert(lines, ("  %s: not loaded"):format(name))
    end
  end

  return table.concat(lines, "\n")
end

function UI:OpenDebugReport()
  if not self.ShowExport or not self.BuildDebugReportText then return end
  local text = self:BuildDebugReportText()
  self:ShowExport("RothDevLib Debug Report", text)
end

function UI:OpenExportAll()
  if not self.ShowExport or not self.BuildExportAllText then return end
  local text = self:BuildExportAllText({ includeLog = true })
  self:ShowExport("RothDevLib Export All", text)
end

function UI:OpenExportSelected()
  if not self.ShowExport or not self.BuildExportSelectedText then return end
  if not self.selectedSig then
    self:ShowExport("RothDevLib Export Selection", "No group selected.")
    return
  end
  local text = self:BuildExportSelectedText(self.selectedSig, { includeOccurrences = true, includeLog = false })
  self:ShowExport("RothDevLib Export Selection", text)
end

function UI:OpenExportGitHub(sig)
  if not self.ShowExport or not (RDL.Export and RDL.Export.BuildGitHubIssueText) then return end
  local targetSig = sig or self.selectedSig
  local text, suggestedTitle = RDL.Export:BuildGitHubIssueText(targetSig)
  if not text then
    self:ShowExport("GitHub Issue Template", suggestedTitle or "Select an error group first.")
    return
  end
  local title = "GitHub Issue Template"
  if suggestedTitle and suggestedTitle ~= "" then
    title = title .. " - " .. tostring(suggestedTitle)
  end
  self:ShowExport(title, text)
end

function UI:BuildValidationChecklistText()
  local lines = BuildHeader("RothDevLib Validation Checklist (Iteration 7)")
  local settings = (RDL.DB and RDL.DB.GetSettings and RDL.DB:GetSettings()) or {}
  local cap = RDL.Capture

  local groupCount = 0
  if RDL.DB and RDL.DB.IterGroups then
    for _ in RDL.DB:IterGroups() do
      groupCount = groupCount + 1
    end
  end

  local st = (RDL.Storm and RDL.Storm.GetStats) and RDL.Storm:GetStats() or nil
  local stormTotal = st and st.total or 0
  local stormThrottled = st and st.throttled or 0

  table.insert(lines, "Status Snapshot")
  table.insert(lines, ("- Version: %s"):format(tostring(RDL.version or "?")))
  table.insert(lines, ("- Groups: %d"):format(groupCount))
  table.insert(lines, ("- UI throttle sec: %s"):format(tostring(settings.uiRefreshThrottleSec)))
  table.insert(lines, ("- Perf profiling: %s"):format(tostring(settings.enablePerfProfiling)))
  table.insert(lines, ("- Storm total/throttled: %s/%s"):format(tostring(stormTotal), tostring(stormThrottled)))
  table.insert(lines, ("- Capture owner state: %s"):format(tostring(cap and cap.ownerInfo and cap.ownerInfo.state or "?")))
  table.insert(lines, ("- !BugGrabber loaded: %s"):format(tostring(IsAddonLoadedSafe("!BugGrabber"))))
  table.insert(lines, ("- BugSack loaded: %s"):format(tostring(IsAddonLoadedSafe("BugSack"))))
  table.insert(lines, "")

  table.insert(lines, "Test Matrix")
  table.insert(lines, "Automated Helpers")
  table.insert(lines, "- /rdev gate  (PASS/FAIL release gate + saves pass log entry on PASS)")
  table.insert(lines, "- /rdev passlog  (shows last 20 PASS runs)")
  table.insert(lines, "- /rdev stress [KIND] <N> [occ|unique]  | /rdev stress stop")
  table.insert(lines, "- /rdev reloadloop <N> | status | stop  (persisted reload loop; max 20)")
  table.insert(lines, "")
  table.insert(lines, "- [ ] A) RDL-only baseline")
  table.insert(lines, "  1) Enable: !RothDevLib only; disable !BugGrabber/BugSack/DebugTools.")
  table.insert(lines, "  2) /reload -> /rdev clear -> /rdev status (expect ownsHandler=true).")
  table.insert(lines, "  3) Run: /rdev test hard, /rdev test warning, /rdev test suppressed.")
  table.insert(lines, "  4) Verify: no duplicate groups for warning/suppressed dedup path.")
  table.insert(lines, "- [ ] B) Chain-mode (!BugGrabber + BugSack)")
  table.insert(lines, "  1) Enable !BugGrabber + BugSack with !RothDevLib.")
  table.insert(lines, "  2) /reload -> /rdev status -> /rdev diag.")
  table.insert(lines, "  3) Run same tests; verify state is blocked/replaced but captures still flow via fallback/report paths.")
  table.insert(lines, "  4) Open /rdev debug and confirm related addon detection is correct.")
  table.insert(lines, "- [ ] C) Combat scenario")
  table.insert(lines, "  1) Enter combat and run safe tests: /rdev test alert, /rdev test assert.")
  table.insert(lines, "  2) Trigger real gameplay events (target swap/casts).")
  table.insert(lines, "  3) Verify no protected action popups caused by RDL UI actions.")
  table.insert(lines, "- [ ] D) Stress flood")
  table.insert(lines, "  1) Fire: /rdev test report, /rdev test breadcrumb, /rdev test metric in loops/manual spam.")
  table.insert(lines, "  2) Verify /rdev storm shows throttled>0 and UI remains responsive.")
  table.insert(lines, "")

  table.insert(lines, "Taint / Restricted Checks")
  table.insert(lines, "- [ ] /etrace mark START_RDL_TAINT")
  table.insert(lines, "- [ ] reproduce scenario")
  table.insert(lines, "- [ ] /etrace mark END_RDL_TAINT")
  table.insert(lines, "- [ ] /framestack on target UI element before any hook assumptions")
  table.insert(lines, "- [ ] /console taintLog 1 (if available) -> reproduce -> /console taintLog 0")
  table.insert(lines, "- [ ] Confirm: no protected mutation from RDL (post-only hooks, no SetAttribute on secure templates)")
  table.insert(lines, "")

  table.insert(lines, "Performance Gate")
  table.insert(lines, "- [ ] Monitor open/close loop x20 (button or /rdev monitor), no errors and no UI freeze.")
  table.insert(lines, "- [ ] Verify uiRefreshThrottleSec works (no excessive redraw storm under spam).")
  table.insert(lines, "- [ ] /rdev perfreset then collect 2-3 min samples; inspect Top CPU/Top Mem stability.")
  table.insert(lines, "")

  table.insert(lines, "Export / UX Gate")
  table.insert(lines, "- [ ] Export dropdown: All, Selected, GitHub, JSON, Pack all open without errors.")
  table.insert(lines, "- [ ] /rdev export github works for selected group and shows template.")
  table.insert(lines, "- [ ] /rdev export share creates copyable string.")
  table.insert(lines, "- [ ] Frame state persistence verified for Main/Monitor/Export after hide/show and /reload.")
  table.insert(lines, "")

  table.insert(lines, "Release Checklist (alpha.19.x)")
  table.insert(lines, "- [ ] Version bumped in Core and TOC.")
  table.insert(lines, "- [ ] docs/ADDON_RU.md updated (commands + export + validation flow).")
  table.insert(lines, "- [ ] docs/INTEGRATION_RU.md updated (new export/release notes).")
  table.insert(lines, "- [ ] todo.md updated with pass log + exact file references.")
  table.insert(lines, "- [ ] Final smoke summary attached to release note.")

  return table.concat(lines, "\n")
end

function UI:OpenValidationChecklist()
  if not self.ShowExport or not self.BuildValidationChecklistText then return end
  local text = self:BuildValidationChecklistText()
  self:ShowExport("RothDevLib Validation Checklist", text)
end

-- Phase 4: JSON export + LLM packing
function UI:OpenExportJSON()
  if not self.ShowExport or not (RDL.Export and RDL.Export.BuildFullObject and RDL.Export.ToJSON) then return end

  local sig = self.selectedSig
  local obj
  if sig and RDL.DB and RDL.DB.GetGroup and RDL.DB:GetGroup(sig) then
    obj = RDL.Export:BuildFullObject({ sig = sig, includeOccurrences = true, includeLog = true })
    local json = RDL.Export:ToJSON(obj, { pretty = true, maxDepth = 6, maxTableEntries = 300, maxArrayLen = 400 })
    self:ShowExport("RothDevLib JSON (Selected)", json)
    return
  end

  obj = RDL.Export:BuildFullObject({ includeOccurrences = true, includeLog = true })
  local json = RDL.Export:ToJSON(obj, { pretty = true, maxDepth = 6, maxTableEntries = 300, maxArrayLen = 500 })
  self:ShowExport("RothDevLib JSON (All)", json)
end

function UI:OpenExportPacked()
  if not self.ShowExport or not (RDL.Export and RDL.Export.Packer and RDL.Export.Packer.BuildPackedJSON) then return end
  local json = RDL.Export.Packer:BuildPackedJSON({ maxBytes = 32000 })
  local share = (RDL.Export and RDL.Export.ToShareString) and RDL.Export:ToShareString(json) or nil
  local out = "-- Packed JSON (copy this) --\n" .. (json or "")
  if share and share ~= "" then
    out = out .. "\n\n-- Share String (optional; smaller if LibDeflate present) --\n" .. share
  end
  self:ShowExport("RothDevLib Pack (LLM)", out)
end
