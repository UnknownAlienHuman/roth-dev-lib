-- !RothDevLib/Export/Packer.lua
-- Phase 6: LLM-oriented compact packing with predictable byte-budget degradation.

local RDL = _G.RothDevLib
local Export = RDL.Export
if not Export then return end

local Packer = {}
Export.Packer = Packer

local function KindWeight(kind)
  if kind == "LUA_ERROR" then return 100 end
  if kind == "TAINT_FORBIDDEN" then return 85 end
  if kind == "TAINT_STATE" then return 80 end
  if kind == "TAINT_BLOCKED" then return 75 end
  if kind == "ALERT" then return 60 end
  if kind == "ASSERT" then return 55 end
  if kind == "LUA_WARNING" then return 40 end
  if kind == "SUPPRESSED" then return 30 end
  return 10
end

local function ScoreGroup(g)
  local w = KindWeight(g and g.kind)
  local c = tonumber(g and g.count) or 1
  local rec = tonumber(g and g.lastSeen) or 0
  return rec * 0.001 + w + math.log(c + 1) * 3
end

local function Trim(s, n)
  if type(s) ~= "string" then
    if s == nil then return nil end
    s = tostring(s)
  end
  if #s <= n then return s end
  return s:sub(1, n) .. "…"
end

local function SafeSerialize(v)
  local U = RDL.Util
  if type(v) == "table" and U and U.SafeSerializeTable then
    return U:SafeSerializeTable(v)
  end
  return tostring(v)
end

local function CompactStack(stack, maxLines)
  if type(stack) ~= "string" then return nil end
  stack = stack:gsub("\r", ""):gsub("\n+$", "")
  local lines = {}
  local n = 0
  for ln in stack:gmatch("[^\n]+") do
    n = n + 1
    lines[#lines + 1] = ln
    if n >= maxLines then break end
  end
  return table.concat(lines, "\n")
end

local function CompactMetrics(metrics, maxEntries, maxValueBytes)
  if type(metrics) ~= "table" then return nil end
  local keys = {}
  for k in pairs(metrics) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)

  local out = {}
  for i = 1, math.min(#keys, maxEntries) do
    local k = keys[i]
    local v = metrics[k]
    out[#out + 1] = {
      k = k,
      v = Trim(SafeSerialize(v), maxValueBytes),
    }
  end
  if #out == 0 then return nil end
  return out
end

local function CompactDoctor(ctx, maxBytes)
  if type(ctx) ~= "table" then return nil end
  local d = {}
  if ctx.top then d.top = Trim(SafeSerialize(ctx.top), maxBytes) end
  if ctx.chain then d.chain = Trim(SafeSerialize(ctx.chain), maxBytes) end
  if ctx.extra then d.extra = Trim(SafeSerialize(ctx.extra), maxBytes) end
  if not d.top and not d.chain and not d.extra then
    return nil
  end
  return d
end

local function CollectGroupsAll(includeIgnored)
  local arr = {}
  if not (RDL.DB and RDL.DB.IsReady and RDL.DB:IsReady()) then return arr end
  for sig, g in RDL.DB:IterGroups() do
    local ignored = (RDL.DB.IsIgnored and RDL.DB:IsIgnored(sig, g and g.addon, g and g.message)) or false
    if includeIgnored or not ignored then
      arr[#arr + 1] = g
    end
  end
  table.sort(arr, function(a, b)
    local as = ScoreGroup(a)
    local bs = ScoreGroup(b)
    if as == bs then
      return tostring(a and a.sig or "") < tostring(b and b.sig or "")
    end
    return as > bs
  end)
  return arr
end

local function BuildAddonStats(groups)
  local out = {}
  for _, g in ipairs(groups) do
    local a = g.addon or "<?>"
    out[a] = out[a] or { total = 0, byKind = {} }
    out[a].total = (out[a].total or 0) + (g.count or 1)
    local k = g.kind or "<?>"
    out[a].byKind[k] = (out[a].byKind[k] or 0) + (g.count or 1)
  end
  return out
end

local function FlattenRecentEntries(maxEntries, maxMsgBytes)
  maxEntries = maxEntries or 24
  local entries = {}
  if not (RDL.DB and RDL.DB.IsReady and RDL.DB:IsReady()) then return entries end

  for _, g in RDL.DB:IterGroups() do
    if g.occurrences and type(g.occurrences) == "table" then
      for i = 1, math.min(#g.occurrences, 4) do
        local e = g.occurrences[i]
        entries[#entries + 1] = e
      end
    end
  end

  table.sort(entries, function(a, b)
    local at = tonumber(a and a.ts) or 0
    local bt = tonumber(b and b.ts) or 0
    if at ~= bt then
      return at > bt
    end
    local ak = tostring(a and a.kind or "")
    local bk = tostring(b and b.kind or "")
    if ak ~= bk then
      return ak < bk
    end
    local aa = tostring(a and a.addon or "")
    local ba = tostring(b and b.addon or "")
    if aa ~= ba then
      return aa < ba
    end
    local as = tostring(a and a.sig or "")
    local bs = tostring(b and b.sig or "")
    if as ~= bs then
      return as < bs
    end
    return tostring(a and a.message or "") < tostring(b and b.message or "")
  end)

  local out = {}
  local seen = {}
  for i = 1, math.min(#entries, maxEntries * 2) do
    local e = entries[i]
    local key = tostring(e.kind) .. "|" .. tostring(e.addon) .. "|" .. tostring(e.sig or "") .. "|" .. tostring(e.ts)
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = {
        ts = e.ts,
        kind = e.kind,
        addon = e.addon,
        func = e.func,
        sig = e.sig,
        msg = Trim(e.message, maxMsgBytes),
        origin = e.origin and { addon = e.origin.addon, file = e.origin.file, line = e.origin.line } or nil,
        stackTop = (type(e.stack) == "string") and (e.stack:match("([^\n]*)") or "") or nil,
      }
      if #out >= maxEntries then break end
    end
  end
  return out
end

local function BuildPolicyDoc()
  return {
    order = {
      "maxStackLines",
      "maxLocalsBytes",
      "maxMsgBytes",
      "maxDoctorBytes",
      "maxBreadcrumbs",
      "maxBreadcrumbMsgBytes",
      "maxMetricEntries",
      "maxMetricValueBytes",
      "timelineMax",
      "maxOccurrences",
      "maxGroups",
      "includeLog",
    },
    note = "Degradation is deterministic: one parameter shrinks at a time in fixed order.",
  }
end

local function TryPackWithLimits(lim, meta)
  local base = Export:BuildFullObject({
    exportKind = "packed",
    maxGroups = 0,
    includeOccurrences = false,
    includeLog = lim.includeLog,
    maxLogBytes = lim.maxLogBytes,
  })

  local groups = CollectGroupsAll(false)
  local chosen = {}
  for i = 1, math.min(#groups, lim.maxGroups) do
    chosen[#chosen + 1] = groups[i]
  end

  local serial = {}
  for i = 1, #chosen do
    local g = chosen[i]
    local o = {
      sig = g.sig,
      kind = g.kind,
      count = g.count,
      lastSeen = g.lastSeen,
      addon = g.addon,
      func = g.func,
      message = Trim(g.message, lim.maxMsgBytes),
      origin = g.origin and { addon = g.origin.addon, file = g.origin.file, line = g.origin.line } or nil,
      stack = CompactStack(g.stack, lim.maxStackLines),
      locals = g.locals and Trim(g.locals, lim.maxLocalsBytes) or nil,
      doctor = CompactDoctor(g.ctx, lim.maxDoctorBytes),
    }

    if g.bus and g.bus.breadcrumbs then
      local bcs = {}
      for j = 1, math.min(#g.bus.breadcrumbs, lim.maxBreadcrumbs) do
        local bc = g.bus.breadcrumbs[j]
        bcs[#bcs + 1] = {
          t = bc.ts,
          c = Trim(bc.cat, 24),
          m = Trim(bc.msg, lim.maxBreadcrumbMsgBytes),
          d = Trim(bc.data, lim.maxBreadcrumbMsgBytes),
        }
      end
      if #bcs > 0 then
        o.breadcrumbs = bcs
      end
    end
    if g.bus and g.bus.metrics then
      o.metrics = CompactMetrics(g.bus.metrics, lim.maxMetricEntries, lim.maxMetricValueBytes)
    end

    if g.occurrences and #g.occurrences > 0 then
      local occ = {}
      for j = 1, math.min(#g.occurrences, lim.maxOccurrences) do
        local e = g.occurrences[j]
        occ[#occ + 1] = {
          ts = e.ts,
          kind = e.kind,
          func = e.func,
          msg = Trim(e.message, lim.maxMsgBytes),
          stackTop = (type(e.stack) == "string") and (e.stack:match("([^\n]*)") or "") or nil,
        }
      end
      o.occ = occ
    end

    serial[#serial + 1] = o
  end

  base.groups = serial
  base.addonStats = BuildAddonStats(chosen)
  base.timeline = FlattenRecentEntries(lim.timelineMax, lim.timelineMsgBytes)
  base.packing = {
    limits = {
      maxGroups = lim.maxGroups,
      maxOccurrences = lim.maxOccurrences,
      maxStackLines = lim.maxStackLines,
      maxLocalsBytes = lim.maxLocalsBytes,
      maxMsgBytes = lim.maxMsgBytes,
      maxDoctorBytes = lim.maxDoctorBytes,
      maxBreadcrumbs = lim.maxBreadcrumbs,
      maxBreadcrumbMsgBytes = lim.maxBreadcrumbMsgBytes,
      maxMetricEntries = lim.maxMetricEntries,
      maxMetricValueBytes = lim.maxMetricValueBytes,
      timelineMax = lim.timelineMax,
      timelineMsgBytes = lim.timelineMsgBytes,
      includeLog = lim.includeLog and true or false,
      maxLogBytes = lim.maxLogBytes,
    },
    byteBudget = {
      target = meta and meta.maxBytes or nil,
      attempt = meta and meta.attempt or nil,
      degradationCount = meta and meta.degradation and #meta.degradation or 0,
    },
    byteBudgetPolicy = BuildPolicyDoc(),
    degradation = meta and meta.degradation or {},
    limitations = {
      "Packed export is size-constrained: fields are truncated by deterministic policy.",
      "WoW sandbox: no external file attachments, local copy-only share model.",
    },
  }

  local json = Export:ToJSON(base, { pretty = true, maxDepth = 6, maxTableEntries = 250, maxArrayLen = 400 })
  return json
end

local function ApplyNextDegradation(lim)
  local function shrinkMul(key, minValue, mul)
    local old = tonumber(lim[key]) or 0
    if old <= minValue then return nil end
    local newV = math.max(minValue, math.floor(old * mul))
    if newV == old and old > minValue then
      newV = old - 1
    end
    if newV == old then return nil end
    lim[key] = newV
    return key, old, newV
  end

  local function shrinkStep(key, minValue, step)
    local old = tonumber(lim[key]) or 0
    if old <= minValue then return nil end
    local newV = old - step
    if newV < minValue then newV = minValue end
    if newV == old then return nil end
    lim[key] = newV
    return key, old, newV
  end

  return shrinkMul("maxStackLines", 8, 0.75)
      or shrinkMul("maxLocalsBytes", 480, 0.75)
      or shrinkMul("maxMsgBytes", 360, 0.80)
      or shrinkMul("maxDoctorBytes", 320, 0.75)
      or shrinkStep("maxBreadcrumbs", 3, 1)
      or shrinkMul("maxBreadcrumbMsgBytes", 80, 0.80)
      or shrinkStep("maxMetricEntries", 3, 1)
      or shrinkMul("maxMetricValueBytes", 64, 0.80)
      or shrinkStep("timelineMax", 8, 4)
      or shrinkStep("maxOccurrences", 1, 1)
      or shrinkStep("maxGroups", 3, 1)
      or (lim.includeLog and (function()
            lim.includeLog = false
            lim.maxLogBytes = 0
            return "includeLog", true, false
          end)() or nil)
end

function Packer:BuildPackedJSON(opts)
  opts = opts or {}
  local maxBytes = tonumber(opts.maxBytes) or 32000
  if maxBytes < 4096 then maxBytes = 4096 end

  local lim = {
    maxGroups = tonumber(opts.maxGroups) or 8,
    maxOccurrences = tonumber(opts.maxOccurrences) or 2,
    maxStackLines = tonumber(opts.maxStackLines) or 18,
    maxBreadcrumbs = tonumber(opts.maxBreadcrumbs) or 8,
    maxBreadcrumbMsgBytes = tonumber(opts.maxBreadcrumbMsgBytes) or 180,
    maxMetricEntries = tonumber(opts.maxMetricEntries) or 8,
    maxMetricValueBytes = tonumber(opts.maxMetricValueBytes) or 140,
    maxMsgBytes = tonumber(opts.maxMsgBytes) or 1200,
    maxLocalsBytes = tonumber(opts.maxLocalsBytes) or 1600,
    maxDoctorBytes = tonumber(opts.maxDoctorBytes) or 640,
    includeLog = opts.includeLog == true,
    maxLogBytes = tonumber(opts.maxLogBytes) or 4000,
    timelineMax = tonumber(opts.timelineMax) or 24,
    timelineMsgBytes = tonumber(opts.timelineMsgBytes) or 200,
  }

  local attempts = 0
  local degradation = {}
  local json = "{}"

  repeat
    attempts = attempts + 1
    json = TryPackWithLimits(lim, {
      maxBytes = maxBytes,
      attempt = attempts,
      degradation = degradation,
    })

    if #json <= maxBytes then
      return json
    end

    local key, from, to = ApplyNextDegradation(lim)
    if not key then
      return json
    end

    degradation[#degradation + 1] = {
      step = key,
      from = from,
      to = to,
      bytesBefore = #json,
      attempt = attempts,
    }
  until attempts >= 16

  return json
end
