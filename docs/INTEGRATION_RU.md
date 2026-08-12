# Интеграция с !RothDevLib (для других аддонов)

Актуально для версии: `1.0.0-alpha.19.0`

Цель: дать вашему аддону **единый канал** для диагностик:
- hard Lua errors (через global errorhandler),
- taints (ADDON_ACTION_BLOCKED/FORBIDDEN),
- Lua warnings,
- ошибки/сбои, которые вы **поймали и “проглотили”** (`xpcall`, wrapper'ы) — через явный `Report*`,
- контекст “что происходило” (Doctor) + breadcrumbs/metrics,
- экспорт (JSON / LLM pack) для багрепортов.

> Критично: не строить диагностику на `SendChatMessage`. В бою/инстансах отправка в чат часто restricted. Вызовы библиотеки **внутри одного клиента** ограничений боя не имеют.

---

## 1) Подключение зависимости

### Вариант A — OptionalDeps (рекомендуется)
В `.toc` вашего аддона:

```
## OptionalDeps: !RothDevLib
```

Это гарантирует корректный порядок загрузки, если пользователь установил !RothDevLib.

### Вариант B — без зависимости (мягкая интеграция)
Если !RothDevLib не установлен — ваш аддон должен работать без него.
Для этого всегда используйте `LibStub("RothDevLib-1.0", true)` (второй аргумент `true` = “не ошибка, а nil”).

---

## 2) Quickstart: 5 строк

```lua
local Dev = LibStub and LibStub("RothDevLib-1.0", true)
local dev = Dev and Dev:NewAddon("MyAddon")

if dev then
  dev:Breadcrumb("event", "PLAYER_LOGIN")
end
```

---

## 3) Самый важный паттерн: WrapSafe для поверхностей (events/hooks/timers)

### Статический контекст
```lua
local Dev = LibStub("RothDevLib-1.0", true)
local dev = Dev and Dev:NewAddon("MyAddon")

local function OnEvent(self, event, ...)
  -- risky logic
end

if dev then
  frame:SetScript("OnEvent", dev:WrapSafe("OnEvent", OnEvent, { frame = "Main" }))
else
  frame:SetScript("OnEvent", OnEvent)
end
```

### Динамический контекст на каждый вызов (рекомендуется)
Используйте `WrapSafeCtx` — он безопасен (ошибки становятся SUPPRESSED) и добавляет Doctor-контекст *на каждый вызов*.

```lua
if dev then
  frame:SetScript("OnEvent", dev:WrapSafeCtx("OnEvent", OnEvent, function(self, event, ...)
    return { event = event, unit = select(1, ...) }
  end))
end
```

---

## 4) Doctor: корреляция “что выполнялось” на момент сбоя

Если вы делаете сложные пайплайны, используйте `Enter/Leave` или `SafeCallCtx`:

### SafeCallCtx (лучше ручного Enter/Leave)
```lua
dev:SafeCallCtx("ScanBags", { bag = bagId }, function()
  -- risky work
end)
```

### Ручной Enter/Leave (только если вы гарантируете балансировку)
```lua
dev:Enter("ScanBags", { bag = bagId })
-- risky work
dev:Leave()
```

---

## 5) Явная отправка ошибок (когда вы сами ловите/прячете)

Если ваш аддон использует `xpcall`/обёртки и **Blizzard не показывает** ошибку — отправляйте её в !RothDevLib явно.

### Коротко: dev:Error / dev:Warning / dev:Taint / dev:Suppressed
```lua
local ok, err = xpcall(fn, function(e)
  return debugstack(2, 40, 40) .. "\n" .. tostring(e)
end)

if (not ok) and dev then
  dev:Error(err, { func = "Init", stack = err, tag = "xpcall" })
end
```

### Универсально: dev:Report(kind, message, opts)
- `kind`: `LUA_ERROR`, `LUA_WARNING`, `TAINT_BLOCKED`, `TAINT_FORBIDDEN`, `SUPPRESSED`, `ALERT`, `ASSERT`…

`opts` (наиболее полезное):
- `stack` (строка) или `stackLevel` (если стек пусть снимет RDL),
- `locals` (если есть) — иначе RDL попробует снять сам,
- `func`, `event`, `tag`, `data`, `extra`, `code`.

---

## 6) Breadcrumbs / Metrics / Alerts / Assert

### Breadcrumbs (высокочастотные маркеры)
```lua
dev:Breadcrumb("flow", "step:scan_start", { bag = bagId })
```

### Metrics (числа)
```lua
dev:Metric("scan.windows", n, "count")
```

### Alert (логическая проблема без крэша)
```lua
dev:Alert("SANITY", "Unexpected nil in cache", { key = key })
```

### Assert (инварианты)
```lua
dev:Assert(type(foo) == "table", "E_FOO", "foo must be table", { foo = foo })
```

---

## 7) Профилирование (CPU / Memory delta)
Цель: ловить спайки и видеть метрики в RDL.

```lua
frame:SetScript("OnEvent", dev:WrapProfiled("OnEvent", OnEvent, { spikeMs = 16 }))
frame:SetScript("OnEvent", dev:WrapMemDelta("OnEvent", OnEvent, { spikeKB = 64 }))
```

---

## 8) Экспорт для багрепортов
В UI !RothDevLib:
- **GitHub Issue (Selected)** (рекомендуемый формат для issue tracker)
- **Export JSON**
- **Pack (LLM)**

Slash:
- `/rdev export github` (для выбранной группы)
- `/rdev export json`
- `/rdev export pack`
- `/rdev export share` (если установлен LibDeflate — будет компактнее)

Для validation/release прогона:
- `/rdev validate` (чеклист smoke/taint/perf/release в ExportFrame)
- `/rdev release` (alias)

---

## 9) Ограничения “в бою” и обмен сообщениями
- Внутриклиентная интеграция (вызов `dev:*`) **работает в бою**.
- `SendChatMessage` может быть restricted (особенно в бою/инстансах) — не используйте его как транспорт диагностик.
- Если вам нужен обмен *между игроками*, используйте `C_ChatInfo.SendAddonMessage` (CHAT_MSG_ADDON), но там есть троттлинг и нужна очередь/батчинг.

---

## 10) Мини-список API (то, что обычно нужно)

Создание клиента:
- `Dev:NewAddon(addonName)`
- `Dev:Embed(targetTable, addonName)`

Контекст/корреляция:
- `dev:Enter(funcName, ctx)` / `dev:Leave()`
- `dev:SafeCall(funcName, fn, ...)`
- `dev:SafeCallCtx(funcName, ctx, fn, ...)`
- `dev:WrapSafe(funcName, fn, staticCtx)`
- `dev:WrapSafeCtx(funcName, fn, ctxFn)`

Явные репорты:
- `dev:Error(message, opts)` / `dev:Warning(...)` / `dev:Taint(...)` / `dev:Suppressed(...)`
- `dev:Report(kind, message, opts)`

Сигналы:
- `dev:Breadcrumb(category, message, data)`
- `dev:Metric(name, value, unit, opts)`
- `dev:Alert(code, message, data[, level])`
- `dev:Assert(condition, code, message, data)`

Perf:
- `dev:Profile(funcName, fn, opts, ...)`
- `dev:MemDelta(funcName, fn, opts, ...)`
- wrappers: `dev:WrapProfiled`, `dev:WrapMemDelta`
