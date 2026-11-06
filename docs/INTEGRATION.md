# RothDevLib integration

Use RothDevLib as an optional local diagnostics sink. Do not use chat transport for errors.

```toc
## OptionalDeps: !RothDevLib
```

```lua
local Dev = LibStub and LibStub("RothDevLib-1.0", true)
local dev = Dev and Dev:NewAddon("MyAddon", { maxBreadcrumbs = 80 })
```

Every public diagnostic input is copied into a bounded ordinary-value snapshot. Secret/inaccessible values become markers, so callers may pass event payloads without persisting foreign table references.

## Safe entry points

```lua
frame:SetScript("OnEvent", dev:WrapSafeCtx("OnEvent", OnEvent, function(_, event, ...)
  return { event = event, unit = select(1, ...) }
end))

C_Timer.After(0, dev:WrapSafe("DeferredInit", DeferredInit))
```

For code that already catches an error:

```lua
local ok, err = xpcall(RiskyWork, function(value)
  return debugstack(2, 40, 40) .. "\n" .. tostring(value)
end)

if not ok and dev then
  dev:Error(err, {
    func = "RiskyWork",
    stack = err,
    tag = "xpcall",
    data = { phase = "startup" },
  })
end
```

## Context and signals

```lua
dev:SafeCallCtx("ScanBags", { bag = bagID }, ScanBags)
dev:Breadcrumb("flow", "scan_start", { bag = bagID })
dev:Metric("scan.windows", count, "count", { minInterval = 0.5 })
dev:Alert("SANITY", "Unexpected nil", { key = key })
dev:Assert(type(value) == "table", "E_VALUE", "value must be a table", { value = value })
```

## Profiling

```lua
frame:SetScript("OnEvent", dev:WrapProfiled("OnEvent", OnEvent, { spikeMs = 16 }))
local wrapped = dev:WrapMemDelta("Rebuild", Rebuild, { spikeKB = 64 })
```

## Rules

- Treat RothDevLib as optional; normal addon behavior must not depend on it.
- Wrap entry points, not every helper.
- Report swallowed failures at the catch site.
- Keep context semantically useful; payloads are bounded but garbage is still garbage.
- Never call protected actions from diagnostic callbacks.
