# Интеграция с RothDevLib

RothDevLib — опциональный локальный diagnostics sink. Работоспособность твоего аддона не должна зависеть от его наличия.

```toc
## OptionalDeps: !RothDevLib
```

```lua
local Dev = LibStub and LibStub("RothDevLib-1.0", true)
local dev = Dev and Dev:NewAddon("MyAddon", { maxBreadcrumbs = 80 })
```

Все публичные данные копируются в ограниченный ordinary-value snapshot. Secret/inaccessible values заменяются маркерами; исходные таблицы вызывающего аддона не сохраняются по ссылке.

## Entry points

```lua
frame:SetScript("OnEvent", dev:WrapSafeCtx("OnEvent", OnEvent, function(_, event, ...)
  return { event = event, unit = select(1, ...) }
end))

C_Timer.After(0, dev:WrapSafe("DeferredInit", DeferredInit))
```

Оборачивай границы исполнения: `OnEvent`, hooks, timers, callbacks. Не оборачивай каждый мелкий helper.

## Ошибка уже поймана через xpcall

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

## Контекст и сигналы

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

## Правила

- Не используй `SendChatMessage` как транспорт диагностики.
- Репорть swallowed errors в месте catch.
- Передавай полезный контекст, а не дамп всего состояния.
- Не вызывай protected actions из диагностических callbacks.
- Проверяй интеграцию в combat и с `/reload`.
