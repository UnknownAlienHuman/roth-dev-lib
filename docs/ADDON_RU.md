# !RothDevLib — документация аддона

Актуально для версии: `1.0.0-alpha.19.0`

!RothDevLib — инструмент разработчика для World of Warcraft (Midnight / 12.x), который объединяет в одном месте:
- перехват hard Lua ошибок (через `seterrorhandler()`),
- taints (`ADDON_ACTION_BLOCKED` / `ADDON_ACTION_FORBIDDEN`),
- Lua warnings (`LUA_WARNING`),
- «скрытые» ошибки (которые аддоны поймали через `xpcall`/wrapper и не дали Blizzard показать),
- контекст выполнения (Doctor) и breadcrumbs/metrics,
- экспорт отчётов в структурированном виде (JSON + LLM pack).

Ключевая идея: аддон-автор **не обязан** печатать текст в чат и надеяться, что пользователь его найдёт. Вместо этого автор передаёт диагностические события в !RothDevLib библиотечным API, а пользователь получает единый UI, поиск/фильтры, мониторинг и экспорт.

---

## 1) Установка

1. Скопируй папку `!RothDevLib` в:
   - `_retail_/Interface/AddOns/`
2. Перезапусти игру или `/reload`.
3. (Рекомендуется) отключи другие сборщики, которые пытаются владеть `seterrorhandler()`:
   - `!BugGrabber`, `BugSack` и аналоги.

Пояснение: в WoW глобальный error handler обычно может быть «владелец только один». Если другой аддон «перехватил» handler позже, !RothDevLib будет показывать статус `not-owned`.

---

## 2) Что именно собирается

### Hard Lua errors
- Источник: глобальный `seterrorhandler()`.
- Сохраняется: сообщение, стек, Doctor контекст, breadcrumbs, (опционально) locals.

### Suppressed errors
- Источник: `RDL:SafeCall*` / `RDL:WrapSafe*` и/или явные репорты от других аддонов.
- Это основной режим для ситуаций, когда аддон «обёрнут» в `xpcall` и Blizzard ничего не показывает.

### Taints
- Источник: события `ADDON_ACTION_BLOCKED`/`FORBIDDEN`.
- Группируются и отображаются как отдельные категории.

### Lua warnings
- Источник: `LUA_WARNING`.

### ChatTap (эвристика)
- Если сторонний аддон **пишет стек в чат**, !RothDevLib пытается распарсить последовательность строк и сохранить как SUPPRESSED (source=`chat`).
- Это запасной механизм. Надёжный путь — библиотечная интеграция/явный `ReportError`.

---

## 3) UI: как читать данные

### Основное окно
Открытие:
- `/rdev` (или `/rdev open`)
- кнопка в Addon Compartment
- кнопка/иконка у миникарты

Левая панель — список **групп (категорий)**. Это важно:
- 100 одинаковых ошибок = **1 группа** с `count=100`.
- счётчик на иконке миникарты показывает **количество активных групп**, а не количество occurrences.

Колонки:
- **Kind**: тип (LUA_ERROR / TAINT / WARNING / SUPPRESSED / ALERT / ASSERT)
- **Addon**: вероятный источник
- **Count**: сколько раз повторилось
- **Last**: когда было последнее occurrence
- **Message**: короткий текст

Поиск/фильтры:
- Search (по addon/kind/message/stack top)
- Kind filter
- Addon filter
- Show ignored
- Быстрые переключатели: Only errors / Only taints

Окраска:
- LUA_ERROR — красный
- TAINT — жёлтый
- WARNING — оранжевый
- SUPPRESSED — голубой

### Игнорирование шума
Кнопки:
- **Ignore Sig** — игнорировать конкретную сигнатуру группы
- **Ignore Addon** — игнорировать целый аддон

Игнор влияет на:
- подсчёт активных групп
- цвет/состояние миникарты
- список (если `Show ignored` выключен)

---

## 4) Мониторинг (CPU/Mem + Alerts)

### Что есть
- CPU profiling wrappers (`debugprofilestop()`): EMA/last/max + ALERT при спайках
- Memory delta wrappers (`collectgarbage('count')`): EMA/last/max + ALERT
- Опциональный global memory watcher (выключен по умолчанию)

### Окно мониторинга
Открытие:
- кнопка **Monitor** в основном окне
- `/rdev monitor`

Показывает:
- Top CPU (EMA)
- Top Mem (EMA)
- Recent ALERTs

Важно: мониторинг обновляется тикером **только пока окно открыто**.

---

## 5) Экспорт отчётов

Кнопки в UI:
- **Export All** — весь DB (ограничено лимитами)
- **Export Selected** — выбранная группа
- **GitHub Issue (Selected)** — готовый markdown-шаблон issue по выбранной группе
- **Validation Checklist** — чеклист smoke/taint/perf/release для Iteration 7
- **Export JSON** — JSON schema=1
- **Pack (LLM)** — упакованный JSON под byte-budget

Slash:
- `/rdev export json`
- `/rdev export pack`
- `/rdev export share` — выдаёт `RDL1:` строку (сжатие будет лучше, если установлен LibDeflate; без него отдаётся raw JSON)
- `/rdev export github` — issue-template для выбранной группы

Экспорт специально ограничивает объём:
- `maxGroups` (default 200)
- `maxOccurrencesPerGroup` (default 10)
- урезание stack/locals/breadcrumbs по byte-budget

---

## 6) Команды

Основные:
- `/rdev` — открыть/закрыть
- `/rdev clear` — очистить базу
- `/rdev monitor` — окно мониторинга
- `/rdev report` или `/rdev export` — окно экспорта

Экспорт:
- `/rdev export json | pack | share | github`
- `/rdev export addon <AddonName>`
- `/rdev export kind <LUA_ERROR|SUPPRESSED|LUA_WARNING|TAINT|ALERT|ASSERT>`

Диагностика:
- `/rdev status` — кто владеет error handler
- `/rdev reclaim` — попытаться вернуть handler
- `/rdev storm` — статистика flood protection
- `/rdev diag` — расширенный self-diagnosis
- `/rdev debug` — полный debug report в ExportFrame
- `/rdev validate` — runtime validation checklist (smoke/taint/perf)
- `/rdev release` — alias для `/rdev validate`

Настройки/служебные:
- `/rdev set <key> <value>`
- `/rdev get [key]`
- `/rdev perfreset`
- `/rdev bus`
- `/rdev bus <AddonName>`
- `/rdev uireset` (сброс сохранённой геометрии UI; затем `/reload`)

Миникарта/ChatTap:
- `/rdev icon show|hide|toggle|reset|status`
- `/rdev chat on|off|status`

Тесты:
- `/rdev test suppressed|hard|warning|taint|taintmacro|taintstate|breadcrumb|metric|alert|assert|report|cpu|mem`

---

## 7) Настройки (SavedVariables) — ключевые

`RothDevLibDB.settings`:
- `maxGroups`, `maxOccurrencesPerGroup`
- `lockErrorHandler` (пытаться удержать `seterrorhandler`)
- `hideBlizzardScriptErrors`, `hideTaintPopups`
- `captureChatErrors` (ChatTap)
- `uiRefreshThrottleSec` (важно для storm)
- `captureLocals`, `maxLocalsSize`, `localsProbeMax`
- `enablePerfProfiling`, `cpuSampleRate`, `cpuSpikeMs`, `memSpikeKB`
- `memWatchEnabled`, `memWatchIntervalSec`

---

## 8) Ограничения и ожидания

1) **Нельзя гарантированно поймать ошибку, если аддон:
   - полностью глотает её,
   - не репортит наружу,
   - и не печатает стек в чат.**
   Решение: интеграция через `LibStub("RothDevLib-1.0")` и `dev:Error/dev:Report`.

2) **SendChatMessage** может быть restricted в бою/инстансах.
   !RothDevLib не использует чат как транспорт. Интеграция должна быть через локальные вызовы.

3) Межклиентный транспорт (addon messages) возможен через `C_ChatInfo.SendAddonMessage`, но он троттлится и требует очереди/батчинга. В !RothDevLib это не включено как обязательная часть.

---

## 9) Для авторов аддонов

Смотри `docs/INTEGRATION_RU.md`.

Практически минимальный стандарт:
- wrap все entry points (`OnEvent`, hooks, timers) через `dev:WrapSafeCtx`
- на любых `xpcall` / swallow-path: `dev:Error(...)` или `dev:Report(...)`
- добавляй breadcrumbs/metrics на важных этапах
