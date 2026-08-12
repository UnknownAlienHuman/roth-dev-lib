# RothDevLib Integration (for other addons)

RothDevLib is a debugging/telemetry sink for World of Warcraft addons. It captures:
- hard Lua errors (global errorhandler),
- taints (ADDON_ACTION_BLOCKED/FORBIDDEN),
- Lua warnings,
- *suppressed* failures (wrappers / xpcall / swallowed errors) via explicit `Report*`,
- correlation context (Doctor) + breadcrumbs/metrics,
- exports (JSON / packed LLM bundle).

> Do not rely on `SendChatMessage` for diagnostics. In combat/instances it may be restricted. Local library calls are fine in combat.

---

## 1) Load order / dependency

Recommended in your `.toc`:

```
## OptionalDeps: !RothDevLib
```

Always acquire the library safely:

```lua
local Dev = LibStub and LibStub("RothDevLib-1.0", true) -- nil if not installed
local dev = Dev and Dev:NewAddon("MyAddon")
```

---

## 2) The most important pattern: WrapSafe surfaces

### Static context
```lua
frame:SetScript("OnEvent", dev:WrapSafe("OnEvent", OnEvent, { frame = "Main" }))
```

### Dynamic context per call (recommended): WrapSafeCtx
```lua
frame:SetScript("OnEvent", dev:WrapSafeCtx("OnEvent", OnEvent, function(self, event, ...)
  return { event = event, unit = select(1, ...) }
end))
```

---

## 3) Doctor context (correlation)

Prefer `SafeCallCtx` over manual Enter/Leave:

```lua
dev:SafeCallCtx("ScanBags", { bag = bagId }, function()
  -- risky work
end)
```

Manual:
```lua
dev:Enter("ScanBags", { bag = bagId })
-- work
dev:Leave()
```

---

## 4) Explicit reporting (when you catch/swallow errors yourself)

```lua
local ok, err = xpcall(fn, function(e)
  return debugstack(2, 40, 40) .. "\n" .. tostring(e)
end)

if (not ok) and dev then
  dev:Error(err, { func = "Init", stack = err, tag = "xpcall" })
end
```

Generic:
```lua
dev:Report("LUA_ERROR", err, { func = "OnEvent", stackLevel = 3 })
```

`opts` highlights:
- `stack` (string) or `stackLevel`
- `locals` (string/table) or let RDL attempt capture
- `event`, `tag`, `data`, `extra`, `code`

---

## 5) Signals

```lua
dev:Breadcrumb("flow", "scan_start", { bag = bagId })
dev:Metric("scan.windows", n, "count")
dev:Alert("SANITY", "Unexpected nil", { key = key })
dev:Assert(type(foo) == "table", "E_FOO", "foo must be table", { foo = foo })
```

---

## 6) Profiling (CPU / Memory delta)

```lua
frame:SetScript("OnEvent", dev:WrapProfiled("OnEvent", OnEvent, { spikeMs = 16 }))
frame:SetScript("OnEvent", dev:WrapMemDelta("OnEvent", OnEvent, { spikeKB = 64 }))
```

---

## 7) Exports

UI buttons:
- Export JSON
- Pack (LLM)

Slash:
- `/rdev export json`
- `/rdev export pack`
- `/rdev export share` (compressed if LibDeflate is installed)

