-- !RothDevLib/Doctor/Validation.lua
-- Lightweight in-game validation and release gate.
--
-- Goals:
--   * Provide a deterministic PASS/FAIL gate based on observable runtime signals.
--   * Offer safe stress + reload-loop utilities for manual QA.
--   * Keep coupling minimal: Capture optionally notifies Validation on stored entries.
--
-- Notes:
--   * This module is intentionally conservative: it never mutates secure state.
--   * All operations are best-effort and guarded with pcall.

local RDL = _G.RothDevLib
if not RDL then return end

RDL.Validation = RDL.Validation or {}
local V = RDL.Validation

local function Now()
  return (type(time) == "function") and time() or 0
end

local function SafeCall(fn, ...)
  if type(fn) ~= "function" then return false, nil end
  return pcall(fn, ...)
end

local function HasAddonPath(stack)
  if type(stack) ~= "string" then return false end
  return stack:find("Interface/AddOns/" .. tostring(RDL.addonName) .. "/", 1, true) ~= nil
end

local function GetSettings()
  if RDL.DB and RDL.DB.GetSettings then
    local ok, s = pcall(RDL.DB.GetSettings, RDL.DB)
    if ok and type(s) == "table" then return s end
  end
  return nil
end

local function PushPassLog(settings, rec)
  if type(settings) ~= "table" then return end
  settings._validationPassLog = settings._validationPassLog or {}
  local log = settings._validationPassLog
  if type(log) ~= "table" then
    log = {}
    settings._validationPassLog = log
  end

  log[#log + 1] = rec
  local maxN = 20
  while #log > maxN do
    table.remove(log, 1)
  end
end

function V:Init()
  if self._inited then return end
  self._inited = true

  self.startedAt = Now()
  self.taint = {
    blocked = 0,
    forbidden = 0,
    state = 0,
    selfBlocked = 0,
    selfForbidden = 0,
    selfState = 0,
  }
  self.errors = {
    lua = 0,
    warning = 0,
    suppressed = 0,
    alert = 0,
    assert = 0,
  }

  self._stress = { active = false, ticker = nil, remaining = 0 }
end

-- Optional hook called from Capture.StoreEntry() after successful store.
function V:OnEntryStored(entry, status)
  if not entry or type(entry) ~= "table" then return end
  local kind = tostring(entry.kind or "")

  if kind == "LUA_ERROR" then self.errors.lua = (self.errors.lua or 0) + 1 end
  if kind == "LUA_WARNING" then self.errors.warning = (self.errors.warning or 0) + 1 end
  if kind == "SUPPRESSED" then self.errors.suppressed = (self.errors.suppressed or 0) + 1 end
  if kind == "ALERT" then self.errors.alert = (self.errors.alert or 0) + 1 end
  if kind == "ASSERT" then self.errors.assert = (self.errors.assert or 0) + 1 end

  if kind == "TAINT_BLOCKED" then
    self.taint.blocked = (self.taint.blocked or 0) + 1
  elseif kind == "TAINT_FORBIDDEN" then
    self.taint.forbidden = (self.taint.forbidden or 0) + 1
  elseif kind == "TAINT_STATE" then
    self.taint.state = (self.taint.state or 0) + 1
  end

  if kind:match("^TAINT_") then
    local isSelf = false
    if entry.addon == RDL.addonName then
      isSelf = true
    elseif HasAddonPath(entry.stack) then
      isSelf = true
    end

    if isSelf then
      if kind == "TAINT_BLOCKED" then
        self.taint.selfBlocked = (self.taint.selfBlocked or 0) + 1
      elseif kind == "TAINT_FORBIDDEN" then
        self.taint.selfForbidden = (self.taint.selfForbidden or 0) + 1
      elseif kind == "TAINT_STATE" then
        self.taint.selfState = (self.taint.selfState or 0) + 1
      end
    end
  end
end

function V:ResetSessionCounters()
  self.startedAt = Now()
  for k in pairs(self.taint or {}) do self.taint[k] = 0 end
  for k in pairs(self.errors or {}) do self.errors[k] = 0 end
end

-- Stress utilities ---------------------------------------------------------

local function NormalizeStressMode(mode)
  mode = tostring(mode or "occ"):lower()
  if mode == "unique" or mode == "groups" then return "unique" end
  return "occ"
end

local function NormalizeStressKind(kind)
  kind = tostring(kind or "ALERT"):upper()
  local allowed = {
    ALERT = true,
    LUA_ERROR = true,
    LUA_WARNING = true,
    ASSERT = true,
    SUPPRESSED = true,
    TAINT_BLOCKED = true,
  }
  if allowed[kind] then return kind end
  return "ALERT"
end

function V:StopStress()
  if self._stress and self._stress.ticker and type(self._stress.ticker.Cancel) == "function" then
    pcall(function() self._stress.ticker:Cancel() end)
  end
  if self._stress then
    self._stress.active = false
    self._stress.ticker = nil
    self._stress.remaining = 0
  end
end

-- Starts a controlled flood of synthetic entries.
-- mode="occ" keeps the signature constant (increases count); mode="unique" creates many groups.
function V:StartStress(kind, count, mode)
  self:Init()

  kind = NormalizeStressKind(kind)
  mode = NormalizeStressMode(mode)

  count = tonumber(count) or 50
  if count < 1 then count = 1 end
  if count > 400 then count = 400 end

  local cap = RDL.Capture
  if not (cap and cap.BuildEntry and cap.StoreEntry) then
    return false, "Capture not ready"
  end

  if not (type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function") then
    return false, "C_Timer.NewTicker unavailable"
  end

  self:StopStress()
  self._stress.active = true
  self._stress.remaining = count

  local idx = 0
  local baseMsg = "RDL_STRESS " .. kind .. " " .. mode

  local function EmitOne()
    idx = idx + 1
    if idx > count then
      self:StopStress()
      return
    end

    local msg = baseMsg
    if mode == "unique" then
      msg = msg .. " #" .. tostring(idx)
    end

    local stack = debugstack(3, 22, 22)
    local extra = { stress = true, mode = mode, idx = idx, total = count }

    local okB, entry = pcall(cap.BuildEntry, cap, kind, msg, stack, nil, RDL.addonName, "Validation.Stress", extra)
    if okB and entry then
      pcall(cap.StoreEntry, entry)
    end

    if idx >= count then
      self:StopStress()
    end
  end

  -- Small tick to avoid a single-frame hitch.
  self._stress.ticker = C_Timer.NewTicker(0.02, EmitOne)
  return true
end

-- Reload loop --------------------------------------------------------------

-- Persisted loop:
-- settings._reloadLoop = { remaining = N, startedAt = ts, lastAt = ts }
function V:SetReloadLoop(remaining)
  local settings = GetSettings()
  if not settings then return false, "DB not ready" end

  remaining = tonumber(remaining) or 0
  if remaining < 0 then remaining = 0 end
  if remaining > 20 then remaining = 20 end

  if remaining == 0 then
    settings._reloadLoop = nil
    return true
  end

  settings._reloadLoop = settings._reloadLoop or {}
  settings._reloadLoop.remaining = remaining
  settings._reloadLoop.startedAt = settings._reloadLoop.startedAt or Now()
  settings._reloadLoop.lastAt = Now()
  return true
end

function V:GetReloadLoop()
  local settings = GetSettings()
  local rl = settings and settings._reloadLoop or nil
  if type(rl) ~= "table" then return 0 end
  return tonumber(rl.remaining) or 0
end

function V:MaybeContinueReloadLoop()
  local settings = GetSettings()
  if not settings or type(settings._reloadLoop) ~= "table" then return end

  local remaining = tonumber(settings._reloadLoop.remaining) or 0
  if remaining <= 0 then
    settings._reloadLoop = nil
    return
  end

  settings._reloadLoop.remaining = remaining - 1
  settings._reloadLoop.lastAt = Now()

  if type(C_Timer) == "table" and type(C_Timer.After) == "function" and type(ReloadUI) == "function" then
    C_Timer.After(1.25, function()
      pcall(ReloadUI)
    end)
  end
end

-- Gate report --------------------------------------------------------------

local function BoolStr(v) return v and "true" or "false" end

function V:BuildGateReport()
  self:Init()

  local lines = {}
  lines[#lines + 1] = "RothDevLib Release Gate"
  lines[#lines + 1] = ("- version: %s"):format(tostring(RDL.version or "?"))
  lines[#lines + 1] = ("- startedAt: %s"):format(tostring(self.startedAt or "?"))

  local settings = GetSettings() or {}
  local cap = RDL.Capture

  local groups = 0
  if RDL.DB and RDL.DB.IterGroups then
    for _ in RDL.DB:IterGroups() do groups = groups + 1 end
  end

  local owns = cap and cap.ownsHandler == true
  lines[#lines + 1] = ("- ownsHandler: %s"):format(BoolStr(owns))
  lines[#lines + 1] = ("- groups: %d"):format(groups)
  lines[#lines + 1] = ("- perfProfiling: %s"):format(BoolStr(settings.enablePerfProfiling ~= false))
  lines[#lines + 1] = ("- storm: %s"):format(RDL.Storm and ("total=" .. tostring((RDL.Storm:GetStats() or {}).total) .. " throttled=" .. tostring((RDL.Storm:GetStats() or {}).throttled)) or "n/a")

  local uiOk = (RDL.UI and type(RDL.UI.Open) == "function")
  lines[#lines + 1] = ("- uiReady: %s"):format(BoolStr(uiOk))
  if RDL.UI and RDL.UI._lastUIError then
    lines[#lines + 1] = ("- lastUIError: %s"):format(tostring(RDL.UI._lastUIError))
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "Session Counters"
  lines[#lines + 1] = ("- luaErrors: %d"):format(tonumber(self.errors.lua) or 0)
  lines[#lines + 1] = ("- warnings: %d"):format(tonumber(self.errors.warning) or 0)
  lines[#lines + 1] = ("- alerts: %d"):format(tonumber(self.errors.alert) or 0)
  lines[#lines + 1] = ("- asserts: %d"):format(tonumber(self.errors.assert) or 0)
  lines[#lines + 1] = ("- taint blocked/forbidden/state: %d/%d/%d"):format(
    tonumber(self.taint.blocked) or 0,
    tonumber(self.taint.forbidden) or 0,
    tonumber(self.taint.state) or 0
  )
  lines[#lines + 1] = ("- self taint blocked/forbidden/state: %d/%d/%d"):format(
    tonumber(self.taint.selfBlocked) or 0,
    tonumber(self.taint.selfForbidden) or 0,
    tonumber(self.taint.selfState) or 0
  )

  lines[#lines + 1] = ""
  lines[#lines + 1] = "Gate Checks"

  local fails = {}

  if (tonumber(self.taint.selfBlocked) or 0) > 0 or (tonumber(self.taint.selfForbidden) or 0) > 0 then
    fails[#fails + 1] = "Taint: restricted action attributed to !RothDevLib (blocked/forbidden)"
  end

  if RDL.UI and RDL.UI._lastUIError then
    fails[#fails + 1] = "UI: lastUIError is set (check /rdev uicheck and report export)"
  end

  -- Optional: require deterministic list mode if ScrollBox API exists.
  local grid = RDL.UI and RDL.UI.groupGrid
  if grid and type(grid.mode) == "string" then
    if grid.mode ~= "scrollbox" then
      fails[#fails + 1] = "UI: groupGrid not in scrollbox mode"
    end
  end

  local pass = (#fails == 0)
  lines[#lines + 1] = ("- PASS: %s"):format(BoolStr(pass))
  if not pass then
    for _, r in ipairs(fails) do
      lines[#lines + 1] = ("  - FAIL: %s"):format(r)
    end
  end

  return pass, table.concat(lines, "\n")
end

function V:RunGateAndLog()
  local pass, text = self:BuildGateReport()

  local settings = GetSettings()
  if pass and settings then
    PushPassLog(settings, {
      ts = Now(),
      version = tostring(RDL.version or "?"),
      taintSelfBlocked = tonumber(self.taint.selfBlocked) or 0,
      taintSelfForbidden = tonumber(self.taint.selfForbidden) or 0,
      lastUIError = (RDL.UI and RDL.UI._lastUIError) and tostring(RDL.UI._lastUIError) or "",
    })
  end

  return pass, text
end

function V:BuildPassLogText()
  local settings = GetSettings() or {}
  local log = settings._validationPassLog
  if type(log) ~= "table" or #log == 0 then
    return "(no pass log recorded)"
  end

  local lines = {}
  lines[#lines + 1] = "RothDevLib Pass Log (last 20)"
  for i = 1, #log do
    local r = log[i]
    if type(r) == "table" then
      local ts = r.ts and date and date("%Y-%m-%d %H:%M:%S", r.ts) or tostring(r.ts or "?")
      lines[#lines + 1] = string.format(
        "%2d) %s  v=%s  selfTaint=%d/%d  lastUIError=%s",
        i,
        ts,
        tostring(r.version or "?"),
        tonumber(r.taintSelfBlocked) or 0,
        tonumber(r.taintSelfForbidden) or 0,
        tostring(r.lastUIError or "")
      )
    end
  end
  return table.concat(lines, "\n")
end
