-- !RothDevLib/Export/Export.lua
-- Phase 4: JSON export + share string (optional LibDeflate).

local RDL = _G.RothDevLib
local Export = {}
RDL.Export = Export

local function Now() return time() end
local function SafeDate(ts)
  local t = tonumber(ts) or time()
  return date("%Y-%m-%d %H:%M:%S", t)
end

local function TrimStr(s, maxBytes)
  if type(s) ~= "string" then
    if s == nil then return nil end
    s = tostring(s)
  end
  maxBytes = maxBytes or 4096
  if #s <= maxBytes then return s end
  return s:sub(1, maxBytes) .. "\n... (trimmed to " .. tostring(maxBytes) .. " bytes)"
end

local function StackTopLines(stack, maxLines)
  if type(stack) ~= "string" then return nil end
  maxLines = maxLines or 20
  local out = {}
  local n = 0
  for line in stack:gmatch("[^\n]+") do
    n = n + 1
    out[#out + 1] = line
    if n >= maxLines then break end
  end
  return table.concat(out, "\n")
end

local function EscapeFence(s)
  if s == nil then return "" end
  return tostring(s):gsub("```", "``\\`")
end

local function SafeCopyTable(t, depth, maxDepth)
  depth = depth or 0
  maxDepth = maxDepth or 4
  if type(t) ~= "table" then return t end
  if depth >= maxDepth then return "<depth>" end
  local out = {}
  local n = 0
  for k, v in pairs(t) do
    n = n + 1
    if n > 80 then out["__truncated"] = true; break end
    if type(v) == "table" then
      out[tostring(k)] = SafeCopyTable(v, depth + 1, maxDepth)
    else
      out[tostring(k)] = v
    end
  end
  return out
end

local function SerializeBreadcrumbs(bcs, max)
  if type(bcs) ~= "table" then return nil end
  max = max or 12
  local out = {}
  for i = 1, math.min(#bcs, max) do
    local bc = bcs[i]
    if type(bc) == "table" then
      out[#out + 1] = {
        ts = bc.ts,
        cat = bc.cat,
        msg = bc.msg,
        data = bc.data,
      }
    end
  end
  return out
end

local function SerializeGroup(g, opts)
  opts = opts or {}
  local maxStackLines = opts.maxStackLines or 40
  local maxMsgBytes = opts.maxMsgBytes or 2048
  local maxLocalsBytes = opts.maxLocalsBytes or 4096
  local maxBreadcrumbs = opts.maxBreadcrumbs or 12
  local maxOcc = opts.maxOccurrences or 3

  local obj = {
    sig = g.sig,
    kind = g.kind,
    count = g.count,
    firstSeen = g.firstSeen,
    lastSeen = g.lastSeen,
    firstSessionId = g.firstSessionId,
    lastSessionId = g.lastSessionId,
    addon = g.addon,
    func = g.func,
    message = TrimStr(g.message, maxMsgBytes),
    origin = g.origin and {
      addon = g.origin.addon,
      file = g.origin.file,
      line = g.origin.line,
    } or nil,
    stack = StackTopLines(g.stack or "", maxStackLines),
    locals = g.locals and TrimStr(g.locals, maxLocalsBytes) or nil,
  }

  if g.sys then obj.sys = SafeCopyTable(g.sys, 0, 4) end
  if g.ctx then
    obj.ctx = {
      top = g.ctx.top and SafeCopyTable(g.ctx.top, 0, 4) or nil,
      chain = g.ctx.chain and SafeCopyTable(g.ctx.chain, 0, 4) or nil,
      extra = g.ctx.extra and SafeCopyTable(g.ctx.extra, 0, 4) or nil,
    }
  end

  if g.bus then
    obj.bus = {
      breadcrumbs = g.bus.breadcrumbs and SerializeBreadcrumbs(g.bus.breadcrumbs, maxBreadcrumbs) or nil,
      metrics = g.bus.metrics and SafeCopyTable(g.bus.metrics, 0, 4) or nil,
    }
  end

  if opts.includeOccurrences and g.occurrences and type(g.occurrences) == "table" then
    local occ = {}
    for i = 1, math.min(#g.occurrences, maxOcc) do
      local e = g.occurrences[i]
      occ[#occ + 1] = {
        ts = e.ts,
        kind = e.kind,
        addon = e.addon,
        func = e.func,
        message = TrimStr(e.message, 512),
        origin = e.origin and { addon = e.origin.addon, file = e.origin.file, line = e.origin.line } or nil,
        stackTop = StackTopLines(e.stack or "", 6),
        sys = e.sys and SafeCopyTable(e.sys, 0, 3) or nil,
      }
    end
    obj.occurrences = occ
  end

  return obj
end

local function CollectGroups(opts)
  opts = opts or {}
  local onlySig = opts.sig
  local out = {}
  if not (RDL.DB and RDL.DB.IsReady and RDL.DB:IsReady()) then
    return out
  end
  for sig, g in RDL.DB:IterGroups() do
    if not onlySig or sig == onlySig then
      if not (opts.includeIgnored ~= true and g.ignored == true) then
        out[#out + 1] = g
      end
    end
  end
  table.sort(out, function(a, b)
    return (a.lastSeen or 0) > (b.lastSeen or 0)
  end)
  return out
end

local function BuildBaseEnvelope(kind)
  local U = RDL.Util
  local sys = (U and U.SnapshotSys) and U:SnapshotSys() or nil
  return {
    type = "RothDevLibExport",
    schema = 1,
    exportKind = kind or "full",
    generatedAt = Now(),
    env = {
      build = sys and sys.build or nil,
      locale = GetLocale and GetLocale() or nil,
      client = { interface = select(4, GetBuildInfo()) },
      player = sys and sys.player or nil,
      zone = sys and { zone = sys.zone, subzone = sys.subzone } or nil,
    },
    addon = {
      name = "!RothDevLib",
      version = tostring(RDL.version or ""),
    },
    session = RDL.DB and RDL.DB.session or nil,
  }
end

function Export:BuildFullObject(opts)
  opts = opts or {}
  local env = BuildBaseEnvelope(opts.exportKind or "full")
  env.limits = {
    maxGroups = opts.maxGroups,
    maxOccurrences = opts.maxOccurrences,
    maxStackLines = opts.maxStackLines,
    maxLocalsBytes = opts.maxLocalsBytes,
  }

  local groups = CollectGroups({ sig = opts.sig, includeIgnored = opts.includeIgnored })
  local maxGroups = opts.maxGroups or #groups
  local arr = {}
  for i = 1, math.min(#groups, maxGroups) do
    arr[#arr + 1] = SerializeGroup(groups[i], {
      includeOccurrences = opts.includeOccurrences ~= false,
      maxOccurrences = opts.maxOccurrences or 3,
      maxStackLines = opts.maxStackLines or 40,
      maxLocalsBytes = opts.maxLocalsBytes or 4096,
      maxMsgBytes = opts.maxMsgBytes or 2048,
      maxBreadcrumbs = opts.maxBreadcrumbs or 12,
    })
  end
  env.groups = arr
  env.summary = {
    groupCount = #groups,
    activeGroupCount = (RDL.DB and RDL.DB.GetActiveGroupCount) and RDL.DB:GetActiveGroupCount() or nil,
  }

  if opts.includeLog and RDL.Logger and RDL.Logger.GetText then
    env.log = TrimStr(RDL.Logger:GetText() or "", opts.maxLogBytes or 12000)
  end

  return env
end

function Export:BuildGitHubIssueText(sig, opts)
  opts = opts or {}
  if not sig or not RDL.DB or not RDL.DB.IsReady or not RDL.DB:IsReady() then
    return nil, "Select an error group first."
  end

  local g = RDL.DB:GetGroup(sig)
  if not g then
    return nil, "Selected signature not found."
  end

  local buildVersion, buildNumber, buildDate, interfaceVersion = GetBuildInfo()
  local addonName = tostring(g.addon or "<?>")
  local kind = tostring(g.kind or "<?>")
  local oneLineMsg = tostring(g.message or ""):gsub("\r", " "):gsub("\n", " ")
  oneLineMsg = TrimStr(oneLineMsg, 120)
  local issueTitle = string.format("[%s] %s: %s", addonName, kind, oneLineMsg)

  local lines = {}
  lines[#lines + 1] = "## Bug Report (auto-generated by RothDevLib)"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "### Suggested Title"
  lines[#lines + 1] = "`" .. EscapeFence(issueTitle) .. "`"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "### Environment"
  lines[#lines + 1] = "- Addon: `" .. EscapeFence(addonName) .. "`"
  lines[#lines + 1] = "- Kind: `" .. EscapeFence(kind) .. "`"
  lines[#lines + 1] = "- Count: `" .. tostring(g.count or 0) .. "`"
  lines[#lines + 1] = "- Signature: `" .. EscapeFence(tostring(sig)) .. "`"
  lines[#lines + 1] = "- RothDevLib: `" .. EscapeFence(tostring(RDL.version or "")) .. "`"
  lines[#lines + 1] = "- WoW Build: `" .. EscapeFence(tostring(buildVersion or "?")) .. " (" .. EscapeFence(tostring(buildNumber or "?")) .. ")`"
  lines[#lines + 1] = "- Interface: `" .. EscapeFence(tostring(interfaceVersion or "?")) .. "`"
  lines[#lines + 1] = "- Build Date: `" .. EscapeFence(tostring(buildDate or "?")) .. "`"
  lines[#lines + 1] = "- Locale: `" .. EscapeFence(tostring(GetLocale and GetLocale() or "?")) .. "`"
  lines[#lines + 1] = "- Player: `" .. EscapeFence(tostring(UnitName("player") or "?")) .. "-" .. EscapeFence(tostring(GetRealmName and GetRealmName() or "?")) .. "`"
  lines[#lines + 1] = "- Zone: `" .. EscapeFence(tostring(GetRealZoneText and GetRealZoneText() or "?")) .. " / " .. EscapeFence(tostring(GetSubZoneText and GetSubZoneText() or "?")) .. "`"
  lines[#lines + 1] = "- First Seen: `" .. EscapeFence(SafeDate(g.firstSeen)) .. "`"
  lines[#lines + 1] = "- Last Seen: `" .. EscapeFence(SafeDate(g.lastSeen)) .. "`"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "### Error Message"
  lines[#lines + 1] = "```"
  lines[#lines + 1] = EscapeFence(TrimStr(g.message or "", opts.maxMessageBytes or 1200))
  lines[#lines + 1] = "```"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "### Stack Trace"
  lines[#lines + 1] = "```lua"
  lines[#lines + 1] = EscapeFence(StackTopLines(g.stack or "", opts.maxStackLines or 80) or "")
  lines[#lines + 1] = "```"

  if g.locals and g.locals ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "<details><summary>Locals</summary>"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "```"
    lines[#lines + 1] = EscapeFence(TrimStr(g.locals, opts.maxLocalsBytes or 2400))
    lines[#lines + 1] = "```"
    lines[#lines + 1] = "</details>"
  end

  if g.bus and g.bus.breadcrumbs and #g.bus.breadcrumbs > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "<details><summary>Bus Breadcrumbs</summary>"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "```"
    for i = 1, math.min(#g.bus.breadcrumbs, opts.maxBreadcrumbs or 8) do
      local bc = g.bus.breadcrumbs[i]
      local ts = bc.ts and SafeDate(bc.ts) or "<?>"
      lines[#lines + 1] = string.format("%d) %s [%s] %s", i, ts, tostring(bc.cat or "?"), tostring(bc.msg or ""))
      if bc.data and bc.data ~= "" then
        lines[#lines + 1] = "   data: " .. TrimStr(tostring(bc.data), opts.maxBreadcrumbDataBytes or 220)
      end
    end
    lines[#lines + 1] = "```"
    lines[#lines + 1] = "</details>"
  end

  if g.ctx and g.ctx.extra then
    local U = RDL.Util
    lines[#lines + 1] = ""
    lines[#lines + 1] = "<details><summary>Doctor Extra</summary>"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "```"
    lines[#lines + 1] = EscapeFence(TrimStr((U and U:SafeSerializeTable(g.ctx.extra)) or tostring(g.ctx.extra), opts.maxDoctorBytes or 1400))
    lines[#lines + 1] = "```"
    lines[#lines + 1] = "</details>"
  end

  return table.concat(lines, "\n"), issueTitle
end

function Export:ToJSON(obj, opts)
  local J = RDL.JSON
  if not J or not J.Encode then return "{}" end
  opts = opts or {}
  return J:Encode(obj, opts)
end

-- Optional share string: uses LibDeflate if present (do not hard-depend).
function Export:ToShareString(json)
  local prefix = "RDL1:"
  if type(json) ~= "string" then json = tostring(json or "") end
  local LibStub = _G.LibStub
  if type(LibStub) ~= "function" then
    return prefix .. json
  end
  local ok, LibDeflate = pcall(function() return LibStub("LibDeflate") end)
  if not ok or not LibDeflate or type(LibDeflate.CompressDeflate) ~= "function" then
    return prefix .. json
  end

  local compressed = LibDeflate:CompressDeflate(json, { level = 7 })
  if not compressed then
    return prefix .. json
  end
  local encoded = LibDeflate:EncodeForPrint(compressed)
  return prefix .. (encoded or json)
end
