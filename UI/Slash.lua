-- !RothDevLib/UI/Slash.lua
-- Slash commands.
-- Ported from RothDevLib/UI/Slash.lua.
-- Enhanced: added /rdev storm, /rdev status, /rdev reclaim.

local RDL = _G.RothDevLib
RDL.UI = RDL.UI or {}
local UI = RDL.UI

SLASH_ROTHDEVLIB1 = "/rdev"
SlashCmdList["ROTHDEVLIB"] = function(msg)
  local rawMsg = (msg or ""):match("^%s*(.-)%s*$")
  msg = rawMsg:lower()

  -- ChatTap helpers
  local chatCmd, chatArg = msg:match("^(chat)%s*(.*)$")
  if chatCmd == "chat" then
    local settings = RDL.DB and RDL.DB:GetSettings()
    if settings then
      local a = (chatArg or "")
      if a == "" or a == "status" then
        -- no-op
      elseif a == "on" or a == "enable" then
        settings.captureChatErrors = true
      elseif a == "off" or a == "disable" then
        settings.captureChatErrors = false
      end
      print("|cffffff00RothDevLib|r chat tap: " .. tostring(settings.captureChatErrors and "on" or "off"))
    end
    return
  end

  -- Icon helpers (minimap)
  local iconCmd, iconArg = msg:match("^(icon)%s*(.*)$")
  if iconCmd == "icon" then
    local settings = RDL.DB and RDL.DB:GetSettings()
    if settings then
      settings.minimap = settings.minimap or { hide = false, minimapPos = settings.minimapAngle or 225 }
      local a = (iconArg or "")
      if a == "" or a == "toggle" then
        settings.minimap.hide = not settings.minimap.hide
      elseif a == "show" then
        settings.minimap.hide = false
      elseif a == "hide" then
        settings.minimap.hide = true
      elseif a == "reset" then
        settings.minimap.hide = false
        settings.minimap.minimapPos = 225
        settings.minimapForceShowOnNextLogin = false
      elseif a == "status" then
        -- no state changes
      end

      settings.minimapHide = settings.minimap.hide
      settings.minimapAngle = settings.minimap.minimapPos
      if UI and UI.SetMinimapButtonShown then
        UI:SetMinimapButtonShown(not settings.minimap.hide)
      end
      print("|cffffff00RothDevLib|r icon: " .. (settings.minimap.hide and "hidden" or "shown") .. " pos=" .. tostring(settings.minimap.minimapPos or "<?>"))
    end
    return
  end

  local setKey, setVal = rawMsg:match("^[Ss][Ee][Tt]%s+(%S+)%s+(.+)$")
  if setKey and setVal then
    local settings = RDL.DB and RDL.DB:GetSettings()
    if not settings then
      print("|cffff3333RothDevLib|r DB not ready.")
      return
    end

    local allowed = {
      cpuSpikeMs = "number",
      memSpikeKB = "number",
      cpuSampleRate = "number",
      cpuAlertMinIntervalMs = "number",
      memAlertMinIntervalMs = "number",
      memWatchSpikeKB = "number",
      memWatchIntervalSec = "number",
      memWatchEnabled = "bool",
      enablePerfProfiling = "bool",
      uiUseScrollBoxList = "bool",
      uiUseButtonFrameShell = "bool",
      maxBreadcrumbsPerAddon = "number",
      breadcrumbsPerError = "number",
      monitorTopN = "number",
      monitorRefreshSec = "number",
      stormBurstLimit = "number",
      stormPerSecondLimit = "number",
    }

    local keyType = allowed[setKey]
    if not keyType then
      local keys = {}
      for k in pairs(allowed) do keys[#keys + 1] = k end
      table.sort(keys)
      print("|cffff3333RothDevLib|r Unknown setting: " .. tostring(setKey))
      print("  Allowed: " .. table.concat(keys, ", "))
      return
    end

    local parsed = nil
    if keyType == "number" then
      parsed = tonumber(setVal)
      if parsed == nil then
        print("|cffff3333RothDevLib|r Expected number for " .. tostring(setKey))
        return
      end
    else
      local low = tostring(setVal):lower()
      if low == "true" or low == "1" or low == "on" then
        parsed = true
      elseif low == "false" or low == "0" or low == "off" then
        parsed = false
      else
        print("|cffff3333RothDevLib|r Expected true/false for " .. tostring(setKey))
        return
      end
    end

    local old = settings[setKey]
    settings[setKey] = parsed
    print("|cffffff00RothDevLib|r set " .. tostring(setKey) .. " = " .. tostring(parsed) .. " (was " .. tostring(old) .. ")")
    if UI and UI.Refresh then pcall(function() UI:Refresh() end) end
    if UI and UI.RefreshMonitor then pcall(function() UI:RefreshMonitor() end) end
    return
  end

  local getKey = nil
  if rawMsg:match("^[Gg][Ee][Tt]$") then
    getKey = ""
  else
    getKey = rawMsg:match("^[Gg][Ee][Tt]%s+(.+)$")
  end
  if getKey ~= nil then
    local settings = RDL.DB and RDL.DB:GetSettings()
    if not settings then
      print("|cffff3333RothDevLib|r DB not ready.")
      return
    end

    getKey = tostring(getKey or ""):match("^%s*(.-)%s*$")
    if getKey ~= "" then
      print("|cffffff00RothDevLib|r " .. tostring(getKey) .. " = " .. tostring(settings[getKey]))
      return
    end

    local keys = {}
    for k, v in pairs(settings) do
      if type(v) == "number" or type(v) == "boolean" then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys)
    print("|cffffff00RothDevLib|r settings:")
    for _, k in ipairs(keys) do
      print("  " .. tostring(k) .. " = " .. tostring(settings[k]))
    end
    return
  end

  if msg == "" or msg == "open" or msg == "ui" then
    if UI and UI.Init and not UI.frame then pcall(function() UI:Init() end) end
    if UI and UI.Toggle then UI:Toggle() end
    return
  end

  if msg == "monitor" then
    if UI and UI.ToggleMonitor then UI:ToggleMonitor() end
    return
  end

  if msg == "uireset" or msg == "layoutreset" then
    local settings = RDL.DB and RDL.DB:GetSettings()
    if not settings then
      print("|cffff3333RothDevLib|r DB not ready.")
      return
    end
    settings.uiFrames = {}
    settings.uiPanes = {}
    print("|cffffff00RothDevLib|r UI layout state reset. Use /reload to apply defaults.")
    return
  end

  local testCmd, testArg = msg:match("^(test)%s*(.*)$")
  if testCmd == "test" then
    local kind = tostring(testArg or "")
    if kind == "" then kind = "hard" end
    if RDL.Capture and RDL.Capture.RunTest then
      pcall(function() RDL.Capture:RunTest(kind) end)
      print("|cffffff00RothDevLib|r test fired: " .. tostring(kind) .. " (see UI/log)")
    else
      print("|cffff3333RothDevLib|r Capture:RunTest unavailable")
    end
    return
  end
  if msg == "clear" then
    if RDL.DB then RDL.DB:Clear() end
    if UI and UI.Refresh then UI:Refresh() end
    print("|cffff3333RothDevLib|r cleared.")
    return
  end
  if msg == "report" or msg == "export" then
    if UI and UI.OpenExportAll then UI:OpenExportAll() end
    return
  end

  -- Phase 4 exports
  local exMode = msg:match("^export%s+(json|pack|share|github)%s*.*$")
  if exMode == "json" then
    if UI and UI.OpenExportJSON then UI:OpenExportJSON() end
    return
  end
  if exMode == "pack" then
    if UI and UI.OpenExportPacked then UI:OpenExportPacked() end
    return
  end
  if exMode == "share" then
    if UI and UI.ShowExport and RDL.Export and RDL.Export.Packer and RDL.Export.Packer.BuildPackedJSON then
      local json = RDL.Export.Packer:BuildPackedJSON({ maxBytes = 32000 })
      local share = (RDL.Export and RDL.Export.ToShareString) and RDL.Export:ToShareString(json) or json
      UI:ShowExport("RothDevLib Share String", share)
    end
    return
  end
  if exMode == "github" then
    if UI and UI.OpenExportGitHub then
      UI:OpenExportGitHub(UI.selectedSig)
    elseif UI and UI.ShowExport then
      UI:ShowExport("GitHub Issue Template", "Export module is not ready.")
    end
    return
  end

  -- Filtered export (uses rawMsg to preserve case for addon names)
  local exFilter, exKey = msg:match("^export%s+(addon)%s+(.+)$")
  if not exFilter then
    exFilter, exKey = msg:match("^export%s+(kind)%s+(.+)$")
  end
  if exFilter and exKey then
    if UI and UI.OpenFilteredExport then
      local opts = {}
      if exFilter == "addon" then
        -- Get original-case addon name from rawMsg
        local rawKey = rawMsg:match("^[Ee][Xx][Pp][Oo][Rr][Tt]%s+[Aa][Dd][Dd][Oo][Nn]%s+(.+)$")
        opts.addon = rawKey or exKey
      end
      if exFilter == "kind" then opts.kind = exKey:upper() end
      UI:OpenFilteredExport(opts)
    end
    return
  end

  if msg == "reclaim" then
    if RDL.Capture and RDL.Capture.TryReclaimHandler then
      local ok = RDL.Capture:TryReclaimHandler("slash")
      if UI and UI.UpdateTitle then pcall(function() UI:UpdateTitle() end) end
      print("|cffffff00RothDevLib|r reclaim: " .. (ok and "ok" or "failed"))
    end
    return
  end

  if msg == "debug" or msg == "debugreport" then
    if UI and UI.Init and not UI.frame then
      pcall(function() UI:Init() end)
    end
    if UI and UI.OpenDebugReport then
      UI:OpenDebugReport()
    else
      print("|cffff3333RothDevLib|r Debug report UI not available. Use /rdev diag.")
    end
    return
  end

  if msg == "validate" or msg == "release" then
    if UI and UI.Init and not UI.frame then
      pcall(function() UI:Init() end)
    end
    if UI and UI.OpenValidationChecklist then
      UI:OpenValidationChecklist()
    elseif UI and UI.ShowExport then
      UI:ShowExport("RothDevLib Validation Checklist", "Validation report UI is not available.")
    else
      print("|cffff3333RothDevLib|r Validation report UI not available.")
    end
    return
  end

  local gateCmd, gateArg = msg:match("^(gate)%s*(.*)$")
  if gateCmd == "gate" then
    if RDL.Validation and RDL.Validation.RunGateAndLog then
      local pass, text = RDL.Validation:RunGateAndLog()
      local title = pass and "RothDevLib Release Gate (PASS)" or "RothDevLib Release Gate (FAIL)"
      if UI and UI.ShowExport then
        UI:ShowExport(title, text)
      else
        print("|cffffff00RothDevLib|r " .. title)
        print(text)
      end
    else
      print("|cffff3333RothDevLib|r Validation module not available.")
    end
    return
  end

  if msg == "passlog" or msg == "gatelog" then
    if RDL.Validation and RDL.Validation.BuildPassLogText then
      local text = RDL.Validation:BuildPassLogText()
      if UI and UI.ShowExport then
        UI:ShowExport("RothDevLib Pass Log", text)
      else
        print("|cffffff00RothDevLib|r pass log:")
        print(text)
      end
    else
      print("|cffff3333RothDevLib|r Validation module not available.")
    end
    return
  end

  local stressCmd, stressArg = msg:match("^(stress)%s*(.*)$")
  if stressCmd == "stress" then
    if not (RDL.Validation and RDL.Validation.StartStress) then
      print("|cffff3333RothDevLib|r Validation module not available.")
      return
    end

    local a = tostring(stressArg or "")
    if a == "" then
      local ok, err = RDL.Validation:StartStress("ALERT", 120, "occ")
      print("|cffffff00RothDevLib|r stress: " .. (ok and "started" or ("failed: " .. tostring(err))))
      return
    end
    if a == "stop" or a == "off" then
      pcall(function() RDL.Validation:StopStress() end)
      print("|cffffff00RothDevLib|r stress: stopped")
      return
    end

    -- Supported:
    --   /rdev stress <count>
    --   /rdev stress unique <count>
    --   /rdev stress <KIND> <count> [unique|occ]
    local w1, w2, w3 = a:match("^(%S+)%s*(%S*)%s*(%S*)$")
    local mode = "occ"
    local kind = "ALERT"
    local count = 120

    if w1 and w1:match("^%d+") then
      count = tonumber(w1) or count
    elseif w1 and (w1 == "unique" or w1 == "occ" or w1 == "groups") then
      mode = (w1 == "unique" or w1 == "groups") and "unique" or "occ"
      count = tonumber(w2) or count
    elseif w1 then
      kind = w1:upper()
      if w2 == "unique" or w2 == "occ" or w2 == "groups" then
        mode = (w2 == "unique" or w2 == "groups") and "unique" or "occ"
        count = tonumber(w3) or count
      else
        count = tonumber(w2) or count
        mode = (w3 == "unique" or w3 == "groups") and "unique" or "occ"
      end
    end

    local ok, err = RDL.Validation:StartStress(kind, count, mode)
    print("|cffffff00RothDevLib|r stress: " .. (ok and ("started kind=" .. tostring(kind) .. " count=" .. tostring(count) .. " mode=" .. tostring(mode)) or ("failed: " .. tostring(err))))
    return
  end

  local rlArg = rawMsg:match("^[Rr][Ee][Ll][Oo][Aa][Dd][Ll][Oo][Oo][Pp]%s*(.*)$")
  if rlArg ~= nil then
    if not (RDL.Validation and RDL.Validation.SetReloadLoop) then
      print("|cffff3333RothDevLib|r Validation module not available.")
      return
    end
    local arg = tostring(rlArg or ""):match("^%s*(.-)%s*$")
    if arg == "" or arg == "status" then
      local n = RDL.Validation:GetReloadLoop()
      print("|cffffff00RothDevLib|r reloadloop remaining=" .. tostring(n))
      return
    end
    if arg == "stop" or arg == "off" or arg == "0" then
      local ok, err = RDL.Validation:SetReloadLoop(0)
      print("|cffffff00RothDevLib|r reloadloop: " .. (ok and "stopped" or ("failed: " .. tostring(err))))
      return
    end
    local n = tonumber(arg)
    if not n then
      print("|cffff3333RothDevLib|r reloadloop usage: /rdev reloadloop <1..20> | status | stop")
      return
    end
    local ok, err = RDL.Validation:SetReloadLoop(n)
    if not ok then
      print("|cffff3333RothDevLib|r reloadloop failed: " .. tostring(err))
      return
    end
    print("|cffffff00RothDevLib|r reloadloop armed: remaining=" .. tostring(RDL.Validation:GetReloadLoop()) .. " (will reload in 1.25s)")
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" and type(ReloadUI) == "function" then
      C_Timer.After(1.25, function() pcall(ReloadUI) end)
    end
    return
  end

  if msg == "perfclear" or msg == "perfreset" then
    if RDL.CPU and RDL.CPU.ResetStats then
      pcall(function() RDL.CPU:ResetStats() end)
    end
    if RDL.Mem and RDL.Mem.ResetStats then
      pcall(function() RDL.Mem:ResetStats() end)
    end
    print("|cffffff00RothDevLib|r profiling stats cleared.")
    if UI and UI.RefreshMonitor then pcall(function() UI:RefreshMonitor() end) end
    return
  end

  if msg == "status" then
    local cap = RDL.Capture
    print("|cffffff00RothDevLib|r status:")
    print("  version=" .. tostring(RDL.version))

    if cap and cap.SyncOwnership then
      pcall(function() cap:SyncOwnership("status") end)
    end

    if cap and cap.ownerInfo then
      local oi = cap.ownerInfo
      print("  handler=" .. tostring(cap.ownsHandler and "owned" or "not-owned") .. " reason=" .. tostring(oi.reason or "<?>"))
      print("  nowHandlerAddon=" .. tostring(oi.nowHandlerAddon or "<?>"))
      print("  nowHandlerSrc=" .. tostring(oi.nowHandlerSrc or "<?>"))
      print("  seterrorhandlerSrc=" .. tostring(oi.seterrorhandlerSrc or "<?>"))
      if oi.addons then
        print("  addons: BugGrabber=" .. tostring(oi.addons.BugGrabber) .. " BugSack=" .. tostring(oi.addons.BugSack) .. " DebugTools=" .. tostring(oi.addons.DebugTools))
      end
    else
      print("  handler=<?> (Capture not initialized)")
    end

    if RDL.Storm then
      local stats = RDL.Storm:GetStats()
      print("  storm: total=" .. tostring(stats.total) .. " throttled=" .. tostring(stats.throttled))
    end
    return
  end


  if msg == "storm" then
    if not RDL.Storm then
      print("|cffffff00RothDevLib|r Storm module not loaded.")
      return
    end
    local stats = RDL.Storm:GetStats()
    print("|cffffff00RothDevLib|r Storm stats:")
    print("  total=" .. tostring(stats.total))
    print("  throttled=" .. tostring(stats.throttled))
    if stats.buckets then
      for kind, b in pairs(stats.buckets) do
        print("  " .. tostring(kind) .. ": tokens=" .. string.format("%.1f", b.tokens or 0))
      end
    end
    return
  end

  local busArg = nil
  if rawMsg:match("^[Bb][Uu][Ss]$") then
    busArg = ""
  else
    busArg = rawMsg:match("^[Bb][Uu][Ss]%s+(.+)$")
  end
  if busArg ~= nil then
    if not RDL.Bus then
      print("|cffffff00RothDevLib|r Bus module not loaded.")
      return
    end

    local addonName = tostring(busArg or ""):match("^%s*(.-)%s*$")
    if addonName == "" then
      local names = (RDL.Bus.GetAllAddonNames and RDL.Bus:GetAllAddonNames()) or {}
      print("|cffffff00RothDevLib|r Bus registered addons:")
      if #names == 0 then
        print("  (none)")
      else
        for _, name in ipairs(names) do
          local st = RDL.Bus.GetAddonStats and RDL.Bus:GetAddonStats(name) or nil
          local size = st and st.size or 0
          local max = st and st.max or 0
          print(("  %s: %d/%d breadcrumbs"):format(name, size, max))
        end
      end
      return
    end

    local crumbs = RDL.Bus.GetBreadcrumbSnapshot and RDL.Bus:GetBreadcrumbSnapshot(addonName, 20) or nil
    if not crumbs or #crumbs == 0 then
      print("|cffffff00RothDevLib|r no breadcrumbs for: " .. tostring(addonName))
      return
    end

    print("|cffffff00RothDevLib|r Bus [" .. tostring(addonName) .. "] last " .. tostring(#crumbs) .. ":")
    for i, c in ipairs(crumbs) do
      local ts = "?"
      if c and type(c.ts) == "number" and type(date) == "function" then
        ts = date("%H:%M:%S", c.ts)
      elseif c and c.ts ~= nil then
        ts = tostring(c.ts)
      end
      local line = ("  %d) [%s] [%s] %s"):format(i, ts, tostring(c and c.cat or "?"), tostring(c and c.msg or ""))
      if c and c.data and c.data ~= "" then
        local d = tostring(c.data)
        if #d > 80 then d = d:sub(1, 80) .. "..." end
        line = line .. " | " .. d
      end
      print(line)
    end
    return
  end

  if msg == "diag" then
    local s = (RDL.DB and RDL.DB:GetSettings()) or {}
    local evErrs = (RDL._eventRegErrors and #RDL._eventRegErrors) or 0
    local cap = RDL.Capture

    print("|cffffff00RothDevLib|r diag:")
    print("  version=" .. tostring(RDL.version))

    if cap and cap.SyncOwnership then
      pcall(function() cap:SyncOwnership("diag") end)
    end

    print("  handler=" .. tostring(cap and cap.ownsHandler and "owned" or "not-owned"))

    if cap and cap.ownerInfo then
      local oi = cap.ownerInfo
      print("  reason=" .. tostring(oi.reason or "<?>"))
      print("  nowHandlerAddon=" .. tostring(oi.nowHandlerAddon or "<?>"))
      print("  nowHandlerSrc=" .. tostring(oi.nowHandlerSrc or "<?>"))
      print("  seterrorhandlerSrc=" .. tostring(oi.seterrorhandlerSrc or "<?>"))

      if cap.ProbeSetErrorHandler then
        local p = nil
        pcall(function() p = cap:ProbeSetErrorHandler() end)
        if p then
          print("  setEH.global ok=" .. tostring(p.global_ok) .. " src=" .. tostring(p.global_src))
          print("  setEH.real   ok=" .. tostring(p.real_ok) .. " src=" .. tostring(p.real_src))
          print("  handler.before addon=" .. tostring(p.before_addon or "<?>") .. " src=" .. tostring(p.before_src or "<?>"))
        end
      end

      if oi.addons then
        print("  loaded: BugGrabber=" .. tostring(oi.addons.BugGrabber) .. " BugSack=" .. tostring(oi.addons.BugSack) .. " DebugTools=" .. tostring(oi.addons.DebugTools))
      end

      local fb = cap._fallback
      if fb then
        print("  fallback: scriptErrorsHooked=" .. tostring(fb.scriptErrorsHooked) .. " bugGrabberEnabled=" .. tostring(fb.bugGrabberEnabled))
      end
    end

    print("  uiLoaded=" .. tostring(RDL.UI and type(RDL.UI.Toggle) == "function"))
    print("  uiLiveDisabled=" .. tostring(RDL.UI and RDL.UI._liveDisabled))
    if RDL.UI and RDL.UI._lastUIError then
      print("  uiLastError=" .. tostring(RDL.UI._lastUIError))
    end

    print("  minimapHidden=" .. tostring(s.minimap and s.minimap.hide))
    print("  eventRegErrors=" .. tostring(evErrs))

    local groupCount = 0
    if RDL.DB and RDL.DB.IterGroups then
      for _ in RDL.DB:IterGroups() do groupCount = groupCount + 1 end
    end
    print("  groups=" .. tostring(groupCount))

    if evErrs > 0 then
      local last = RDL._eventRegErrors[evErrs]
      print("  lastEventRegError=" .. tostring(last.event) .. " " .. tostring(last.err))
    end

    return
  end

  if msg == "uicheck" then
    local ui = RDL.UI
    local grid = ui and ui.groupGrid or nil

    local function WH(f)
      if not f or not f.GetWidth then return "<?>" end
      return string.format("%dx%d", math.floor((f:GetWidth() or 0) + 0.5), math.floor((f:GetHeight() or 0) + 0.5))
    end

    local dbGroups = 0
    if RDL.DB and RDL.DB.IterGroups then
      for _ in RDL.DB:IterGroups() do dbGroups = dbGroups + 1 end
    end

    print("|cffffff00RothDevLib|r uicheck:")
    print("  uiFrame=" .. tostring(ui and ui.frame and ui.frame:IsShown() and "shown" or "hidden") .. " size=" .. WH(ui and ui.frame))
    print("  contentErrors=" .. WH(ui and ui._contentErrors) .. " listFrame=" .. WH(ui and ui.listFrame) .. " detailFrame=" .. WH(ui and ui.detailFrame))
    print("  db.groups=" .. tostring(dbGroups))

    if grid then
      print("  grid.mode=" .. tostring(grid.mode))
      local shown = 0
      if grid.mode == "scrollbox" and grid.scrollBox and grid.scrollBox.ForEachFrame then
        pcall(function()
          grid.scrollBox:ForEachFrame(function(_, r)
            if r and r.IsShown and r:IsShown() then shown = shown + 1 end
          end)
        end)
      end
      print("  grid.rowsShown=" .. tostring(shown))
      print("  grid.filtered=" .. tostring(type(grid._groups) == "table" and #grid._groups or 0) .. " sortKey=" .. tostring(grid.sortKey) .. " asc=" .. tostring(grid.sortAsc))
      print("  grid.filters: kind=" .. tostring(grid.kind) .. " addon=" .. tostring(grid.addon) .. " ignored=" .. tostring(grid.showIgnored) .. " queryLen=" .. tostring(grid.query and #grid.query or 0))
print("  selectedSig=" .. tostring(ui and ui.selectedSig))
if ui and ui.selectedSig and type(grid._groups) == "table" then
  local present = false
  for _, g in ipairs(grid._groups) do
    local sig = g and (g.sig or g._sig)
    if sig == ui.selectedSig then present = true break end
  end
  local first = grid._groups[1] and (grid._groups[1].sig or grid._groups[1]._sig)
  print("  selectedInFiltered=" .. tostring(present) .. " firstSig=" .. tostring(first))
end
      print("  grid.scrollBox=" .. WH(grid.scrollBox) .. " scrollBar=" .. WH(grid.scrollBar))
      local hasDP = (grid.scrollBox and grid.scrollBox.SetDataProvider) and true or false
      local hasView = (grid.scrollBox and grid.scrollBox.SetView) and true or false
      print("  grid.scrollContainer=" .. WH(grid.scrollContainer) .. " sb.hasDP=" .. tostring(hasDP) .. " sb.hasView=" .. tostring(hasView))
      if grid._lastUpdateError then
        print("  grid.lastError=" .. tostring(grid._lastUpdateError))
      end
    else
      print("  grid=<nil>")
    end

    if ui and ui.Refresh then
      pcall(function() ui:Refresh() end)
    end
    return
  end


  if msg == "log" then
    if UI and UI.OpenLog then UI:OpenLog() end
    return
  end

  if msg == "minimap" then
    local settings = RDL.DB and RDL.DB:GetSettings()
    if settings then
      settings.minimap = settings.minimap or { hide = false, minimapPos = settings.minimapAngle or 225 }
      settings.minimap.hide = not settings.minimap.hide
      settings.minimapHide = settings.minimap.hide
      if UI and UI.SetMinimapButtonShown then
        UI:SetMinimapButtonShown(not settings.minimap.hide)
      end
      print("|cffffff00RothDevLib|r minimap button: " .. (settings.minimap.hide and "hidden" or "shown"))
    end
    return
  end

  local test = msg:match("^test%s+(%S+)$")
  if test and RDL.Capture then
    RDL.Capture:RunTest(test)
    print("|cffffff00RothDevLib|r test fired: " .. test)
    return
  end

  print("|cffffff00RothDevLib|r commands:")
  print("  /rdev open")
  print("  /rdev clear")
  print("  /rdev report | export")
  print("  /rdev export json")
  print("  /rdev export pack")
  print("  /rdev export share")
  print("  /rdev export github")
  print("  /rdev export addon <AddonName>")
  print("  /rdev export kind <LUA_ERROR|SUPPRESSED|LUA_WARNING|TAINT|ALERT|ASSERT>")
  print("  /rdev diag")
  print("  /rdev uicheck")
  print("  /rdev status")
  print("  /rdev debug")
  print("  /rdev validate")
  print("  /rdev release")
  print("  /rdev set <key> <value>")
  print("  /rdev get [key]")
  print("  /rdev perfreset")
  print("  /rdev bus")
  print("  /rdev bus <AddonName>")
  print("  /rdev storm")
  print("  /rdev log")
  print("  /rdev monitor")
  print("  /rdev reclaim")
  print("  /rdev minimap")
  print("  /rdev uireset")
  print("  /rdev icon show|hide|toggle|reset|status")
  print("  /rdev chat on|off|status")
  print("  /rdev test suppressed|hard|warning|taint|taintmacro|taintstate|breadcrumb|metric|alert|assert|report|cpu|mem")
end
