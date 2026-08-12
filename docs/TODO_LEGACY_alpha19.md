# !RothDevLib — Детальный TODO (с кодом и конкретикой)

> Generated: 2026-02-20 | v1.0.0-alpha.18.0
> Каждый пункт содержит: **что именно** сделать, **где** в коде, **пример** кода.

---

## AUDIT SNAPSHOT (2026-02-20)

### Что проверено по факту в коде (подтверждено, pass-2)
- `UI/GroupGrid.lua:413`: фильтрация по сессиям в `_BuildFilteredGroups()` отсутствует (`IterGroups()` без `sessionFilter`).
- `Capture/ErrorHandler.lua:991` и `Capture/ErrorHandler.lua:1065`: watchdog `_ownerTicker` создаётся в `EarlyInit()` и повторно в `Init()`.
- `Capture/ErrorHandler.lua:1005` и `Capture/ErrorHandler.lua:1079`: `Suppress:SuppressAll` вызывается дважды (в `EarlyInit()` и `Init()`).
- `Capture/ErrorHandler.lua:414`: `ProbeSetErrorHandler()` есть, но не встроен в ранний ownership-gate.
- `Integration/Bus.lua`: публичные helper-методы (`GetAllAddonNames`, `GetAddonStats`) отсутствуют.
- `Perf/CPU.lua` и `Perf/Mem.lua`: `ResetStats()` отсутствует.
- `UI/Monitor.lua`: нет live Bus Inspector-панели.
- `UI/ExportFrame.lua`: нет отдельного `OnHide`-persist (сейчас только `OnDragStop/OnSizeChanged` через `Skin:AttachFrameStateHandlers`).
- `UI/Report.lua`, `Export/Export.lua`, `UI/Slash.lua`: нет `OpenDebugReport` / `BuildGitHubIssueText` / `export github`.

### Уже реализовано (подтверждено, не дублировать)
- `Core/DB.lua:548`: есть `IterSessionGroups(sessionId)` и `sessionIndex` инфраструктура.
- `Capture/ErrorHandler.lua:560`: есть delta-sync из `ScriptErrorsFrame.errorData`.
- `Capture/Suppress.lua:45`: `LUA_WARNING` unregister реализован в `SuppressDefaultLuaWarning()`.
- `UI/Report.lua:275`: есть экспорт current filtered view через `OpenGridExport()`.
- `Export/Packer.lua:205`: есть адаптивный packer с progressive shrink.
- `Export/Packer.lua:155`: в packed JSON уже есть bus-контекст (`breadcrumbs` + `metrics`) — нужен не “добавить”, а “уплотнить и лимитировать”.
- `UI/Monitor.lua:39` и `UI/Monitor.lua:228`: базовые quick-filter + `monitorTopN` уже есть (без Bus Inspector и без отдельной оптимизации jitter).
- `UI/DetailView.lua:107`: в detail уже есть `Copy Sig` и `Copy Stack` (кнопок `Copy Msg/Locals/All` пока нет).
- `Export/Export.lua`: добавлен structured issue export `BuildGitHubIssueText(sig, opts)` c environment/error/stack/details блоками.
- `UI/Slash.lua` и `UI/MainFrame.lua`: добавлен экспорт `github` (`/rdev export github` + dropdown `GitHub Issue (Selected)`).
- `Export/Packer.lua`: Phase 6 packer rewrite с явной `byteBudgetPolicy`, deterministic degradation и лимитами на breadcrumbs/metrics/timeline.

### Повторная сверка с референсами (pass-2)
- `_Reference/DevForge`: подтверждены паттерны shell-layout (`activity rail`, `sidebar`, `splitter`, `bottom panel`) и resize-state persistence.
- `_Reference/APIInterface`: подтверждены современные паттерны поиска/фильтров (`SearchBoxTemplate`, dropdown callbacks, resize callbacks).
- `_Reference/OneWoW_Utility_DevTool`: брать точечно UX-идеи инспекторов; не переносить ownership/error-handler паттерн “как есть” (`seterrorhandler` заменяется грубо).

### Проверка API/паттернов (wow-api + Blizzard source)
- `seterrorhandler`, `geterrorhandler`, `C_Timer.After`, `C_Timer.NewTicker` подтверждены через wow-api.
- `EventRegistry:RegisterFrameEventAndCallback` подтверждён через wow-api.
- `AddLuaErrorHandler` в wow-api не найден; подтверждён в исходниках:
  `C:\Tools\WoW_Dev_Tools\wow-ui-source/Blizzard_UI_12.0.1.65867/Blizzard_ScriptErrors/Blizzard_ScriptErrors.lua:44`.
- `ChatFrameUtil.AddMessageEventFilter` в wow-api не найден как публичный API; подтверждён в исходниках:
  `C:\Tools\WoW_Dev_Tools\wow-ui-source/Blizzard_UI_12.0.1.65867/Blizzard_ChatFrameBase/ChatFrameFilters.lua:195`.
- `ScriptErrorsFrameMixin:DisplayMessageInternal` подтверждён в исходниках:
  `C:\Tools\WoW_Dev_Tools\wow-ui-source/Blizzard_UI_12.0.1.65867/Blizzard_ScriptErrorsFrame/Blizzard_ScriptErrorsFrame.lua:89`.

### Вывод по масштабу
Объём большой. Реализуем итерациями: сначала стабильность capture-пайплайна, затем UI-архитектура, затем UX/экспорт/диагностика.

## CONTEXT RESUME SNAPSHOT (2026-02-20, post-pass-14)

### Уже закрыто к этому моменту
- Iteration 1: code-пункты и smoke matrix template закрыты (runtime smoke execution остаётся ручным шагом).
- Iteration 2: закрыта полностью (session-aware grid + export parity).
- Iteration 3: закрыта полностью (activity rail + collapsible sidebar + split panes + optional diagnostics panel + tab badges).
- Iteration 4: закрыта полностью (Copy actions, Occur navigation, Monitor Bus Inspector, detail quick actions).
- Iteration 5: закрыта полностью (`/rdev set|get|perfreset|bus|debug`, Bus helpers, perf resetters, debug report).
- Iteration 6: закрыта полностью (`BuildGitHubIssueText`, `/rdev export github`, deterministic packer degradation/budget policy, Export/Monitor `OnHide` persist).

### Что осталось после pass-14
- Iteration 7 runtime checks: taint/combat/perf smoke execution в клиенте + финальный релизный smoke-summary.

### Критично помнить (для следующего шага)
- Pane state keys уже используются и должны сохраняться совместимыми:
  - `mainShell` (в `UI/MainFrame.lua`)
  - `monitorShell` (в `UI/Monitor.lua`)
- Для splitter drag используется паттерн `GetCursorPosition()` + `Frame:GetEffectiveScale()`.
- Без in-game smoke пока: проверки в pass-14 выполнены статически (чтение кода/`rg`), runtime в клиенте не запускался.

---

## MASTER ROADMAP V2 (по заходам)

### ИТЕРАЦИЯ 1 — Stabilize Capture Core (критический путь)
**Цель:** убрать дубли/гонки в ownership и сделать предсказуемый fallback.

- [x] Удалить дубли `_ownerTicker` и `Suppress:SuppressAll` из `Capture:Init()`; оставить единичный запуск в `EarlyInit()`.
- [x] Встроить `ProbeSetErrorHandler()` в `EarlyInit()` до сохранения `_real_seterrorhandler`.
- [x] Если `global_ok == false`, переходить сразу в fallback-сценарий без ложной попытки ownership.
- [x] Явно отметить состояния ownership (`owned/blocked/replaced/not-owned`) в одном месте.
- [x] Добавить smoke-набор для RDL-only и chain-mode (с BugGrabber), включая проверку dedup.

**DoD:**
- Нет двойного watchdog.
- Нет двойного suppress-вызова.
- `/rdev status` и `/rdev diag` показывают корректную ownership-семантику.

### ИТЕРАЦИЯ 2 — Data/Filtering (Session-aware)
**Цель:** parity с BugSack по сессионному анализу и clean filtering API.

- [x] Добавить `sessionFilter` в `UI/GroupGrid.lua` (`ALL/CURRENT/PREV/sessionId`).
- [x] Переключить `_BuildFilteredGroups()` на `IterSessionGroups(sessionId)` при выбранной сессии.
- [x] Добавить session dropdown в grid-toolbar.
- [x] Вынести фильтрацию в helper (без дублирования условий в двух итераторах).
- [x] Экспорт текущего view должен учитывать session filter.

**DoD:**
- Список групп реально меняется при выборе Current/Prev session.
- Экспорт “current view” повторяет состояние фильтров 1:1.

### ИТЕРАЦИЯ 3 — UI Shell Modernization (DevForge/APIInterface направления)
**Цель:** современный, удобный и расширяемый интерфейс без таинт-рисков.

- [x] Ввести layout-каркас: `activity rail` + `collapsible sidebar` + `resizable split main/detail`.
- [x] Добавить splitter (drag-resize) для list/detail.
- [x] Добавить splitter (drag-resize) для monitor subpanes.
- [x] Добавить optional bottom diagnostics panel со splitter.
- [x] Централизовать в `UI/Skin.lua` semantic colors (`surface`, `surfaceAlt`, `accent`, `danger`, `warning`, `ok`).
- [x] Централизовать в `UI/Skin.lua` единые размеры/spacing/hover states.
- [x] Добавить persistence для размеров/состояний pane (не только координаты окон).
- [x] Обновить tab-UX: активные/неактивные состояния + бейджи по категориям.

**DoD:**
- UI одинаково читаем на 1080p и 1440p.
- Перезапуск сохраняет геометрию/панели.
- Без protected-операций, только безопасные UI-хуки.

### ИТЕРАЦИЯ 4 — Detail/Monitor UX
**Цель:** ускорить triage ошибки до 10-20 секунд.

- [x] DetailView: `Copy Msg`, `Copy Locals`, `Copy All`.
- [x] Occur tab: `prev/next` навигация по одному occurrence + индекс `N/M`.
- [x] Monitor: добавить Bus Inspector (live breadcrumbs + фильтр по addon).
- [x] Monitor: довести фильтрацию/top N до стабильного режима без рывков (базовый filter + `monitorTopN` уже есть).
- [x] Добавить кнопки quick actions: open sig / ignore sig / ignore addon из detail.

**DoD:**
- Пользователь копирует полный bug-report одним кликом.
- Breadcrumb-контекст доступен без экспорта.

### ИТЕРАЦИЯ 5 — Settings + Slash + Diagnostics
**Цель:** управляемость без ручного редактирования SavedVariables.

- [x] `/rdev set <key> <value>` и `/rdev get [key]` (whitelist only).
- [x] `/rdev perfreset` (`CPU:ResetStats`, `Mem:ResetStats`).
- [x] `/rdev bus` и `/rdev bus <AddonName>`.
- [x] `UI:OpenDebugReport()` + `/rdev debug`.
- [x] Добавить `Bus:GetAllAddonNames()` и `Bus:GetAddonStats()`.

**DoD:**
- Все ключевые thresholds меняются в рантайме командами.
- Debug report создаётся в ExportFrame без чат-спама.

### ИТЕРАЦИЯ 6 — Export/Share Pipeline
**Цель:** улучшить качество данных для GitHub/Discord/LLM.

- [x] `BuildGitHubIssueText(sig)` (structured template).
- [x] `export github` (для выбранной группы).
- [x] Уплотнить уже существующий bus-context в packed JSON (лимиты для `metrics`/`breadcrumbs`, предсказуемая деградация по размеру).
- [x] Гарантировать persist Export/Monitor frame state (`OnHide` + existing handlers).
- [x] Уточнить byte-budget policy и деградацию packer-лимитов.

**DoD:**
- Из UI за 1-2 клика формируется готовый issue текст.
- pack не теряет критичный контекст при урезании.

### ИТЕРАЦИЯ 7 — Validation + Release Gate
**Цель:** зафиксировать стабильный релиз-кандидат.

- [x] Подготовить матрицу тестов (checklist template): RDL-only / RDL+BugGrabber / combat / stress flood.
- [ ] Выполнить матрицу тестов in-game и зафиксировать итоговый smoke summary.
- [x] На каждый API/hook-commit: `lookup_api` + source-proof в `C:\Tools\WoW_Dev_Tools\wow-ui-source` с фиксацией `path:line`.
- [ ] Проверка таинта: `/etrace`, restricted scenarios, no protected mutation.
- [ ] Проверка производительности: UI-refresh throttle, monitor open/close loops.
- [x] Обновить docs (`ADDON_RU.md`, `INTEGRATION_RU.md`) под новые команды/UX.
- [x] Подготовить release checklist и версию `alpha.19.x`.

**DoD:**
- Нет блокирующих регрессий по capture.
- UI и экспорт проверены по smoke-набору.

---

## UI Direction (из референсов, что берём)

### Из `_Reference/DevForge` (берём)
- Activity rail с бейджами активных проблем.
- Collapsible sidebar + split panes с drag-resize.
- Единая тема/палитра + reusable widgets (search/dropdown/split).
- Bottom diagnostics panel (output/errors/events) как опциональный режим.

### Из `_Reference/APIInterface` (берём)
- Использование современных Blizzard-шаблонов поиска/фильтра (`SearchBoxTemplate`, dropdown callbacks).
- История навигации и явные “scope search” UX-паттерны.
- ScrollBox-подход для больших списков (где это оправдано).

### Из `_Reference/OneWoW_Utility_DevTool` (берём осторожно)
- Полезно: быстрые инспекторы, copy UX, селекторы событий.
- Не переносим как есть: монолитный UI-файл и грубый `seterrorhandler` ownership без тонкой диагностики.

---

## История изменений / результатов

- 2026-02-20 (Codex): аудит кода `!RothDevLib` + сверка с `_Info`, `C:\Tools\WoW_Dev_Tools\wow-ui-source`, референсами `DevForge/OneWoW/APIInterface`; добавлен master roadmap v2 с итерациями и DoD; подтверждены критические точки (дубли watchdog/suppress, отсутствие session-filter UI, отсутствие Bus/DebugReport команд); тесты в игре не запускались (только статический аудит и source-proof).
- 2026-02-20 (Codex, pass-2): повторный аудит после всех изменений с фокусом на блок “уже реализовано”; подтверждены реализованные части (`IterSessionGroups`, `ScriptErrorsFrame delta-sync`, `OpenGridExport`, adaptive packer, базовый bus-context в packer), скорректированы roadmap-пункты (bus-context: не “добавить”, а “уплотнить”; Monitor filter/topN: частично готово), критические незакрытые пункты без изменений (дубли в `ErrorHandler`, session-filter UI, bus/perf/debug команды).
- 2026-02-20 (Codex, pass-3, Iteration 1): `Capture/ErrorHandler.lua` — удалены дубли watchdog/suppress из `Capture:Init()` (оставлен единичный запуск в `EarlyInit()`), встроен ранний `ProbeSetErrorHandler()` gate до сохранения `_real_seterrorhandler`, добавлен немедленный fallback-path при `global_ok == false`, синхронизация ownership переведена на единые состояния (`owned/blocked/replaced/not-owned`) через `_SetOwnershipState`; локальная проверка через `rg`: watchdog/suppress-блок найден только в `EarlyInit()`; in-game smoke не запускался в этой сессии.
- 2026-02-20 (Codex, pass-4, Iteration 2): `UI/GroupGrid.lua` — добавлен `sessionFilter` state + dropdown `All/Current/Previous/#id`, `_BuildFilteredGroups()` переключён на `IterSessionGroups(sessionId)` при scoped-фильтре, фильтрация вынесена в `PassesFilters()`, `_RebuildAddonDropdown()` теперь тоже учитывает текущую session-область; проверка связки экспорта: `UI/Report.lua:275` использует `grid._groups`, поэтому экспорт повторяет текущий session-filter view; in-game smoke не запускался в этой сессии.
- 2026-02-20 (Codex, pass-5, Iteration 5 partial): добавлены runtime-команды `/rdev set|get`, `/rdev perfreset`, `/rdev bus [AddonName]` в `UI/Slash.lua`; реализованы `Bus:GetAllAddonNames()` и `Bus:GetAddonStats()` в `Integration/Bus.lua`; добавлены `CPU:ResetStats()` и `Mem:ResetStats()` в `Perf/CPU.lua` и `Perf/Mem.lua`; локальная статическая проверка (`rg`) подтверждает наличие новых entry points и команд; in-game smoke не запускался в этой сессии.
- 2026-02-20 (Codex, pass-6, Iteration 5 complete): в `UI/Report.lua` добавлены `UI:BuildDebugReportText()` и `UI:OpenDebugReport()` (комплексный экспорт диагностики в ExportFrame), в `UI/Slash.lua` добавлена команда `/rdev debug|debugreport`; проверка: `!RothDevLib.toc` уже содержит `UI\\Report.lua`, отдельные toc-правки не потребовались; in-game smoke не запускался в этой сессии.
- 2026-02-20 (Codex, pass-7, Iteration 3 partial): `UI/Skin.lua` — добавлены semantic theme tokens (`surface/surfaceAlt/accent/danger/warning/ok`) и spacing scale, `ApplyWindow/ApplyInset` переведены на theme-цвета, добавлено persist-хранилище pane-state (`uiPanes`) через `GetPaneState/SavePaneState`; `UI/MainFrame.lua` — внедрены collapsible sidebar + drag splitter list/detail с persist (`mainShell`); `UI/Monitor.lua` — внедрён drag splitter для CPU/Mem subpanes с persist (`monitorShell`); проверка API: `GetCursorPosition` и методы `Frame` (`GetEffectiveScale`, `SetPoint`, `HookScript`) подтверждены через wow-api; in-game smoke не запускался в этой сессии.
- 2026-02-20 (Codex, pass-8, Iteration 3 complete): `UI/MainFrame.lua` — добавлены `activity rail` (категории с badge-счётчиками + быстрый kind-filter), optional bottom diagnostics panel (toggle `Diag`, live diagnostics text) и горизонтальный drag splitter с persistence в `mainShell` (`diagShown`, `diagRatio`, `activityKind`); `UI/DetailView.lua` — обновлены tab active/inactive visual states и dynamic badges (`Message/Stack/Locals/Doctor/Occur`); `todo.md` синхронизирован (`CONTEXT RESUME SNAPSHOT`, чекбоксы Iteration 3); проверка API: `GetCursorPosition` + `Frame:GetEffectiveScale` подтверждены через wow-api в текущей сессии; in-game smoke не запускался в этой сессии.
- 2026-02-20 (Codex, pass-9, Iteration 4 complete): `UI/DetailView.lua` — добавлены copy-actions (`Copy Message`, `Copy Locals`, `Copy All` через `Copy ▾`), quick actions (`Open Sig`, `Ignore Sig`, `Ignore Addon` через `Actions ▾`), и навигация Occur (`◄/►` + индекс `N/M`) с фильтрацией и single-occurrence view; `UI/MainFrame.lua` — вынесены reusable методы `UI:ToggleIgnoreSig()` и `UI:ToggleIgnoreAddon()` для переиспользования в detail; `UI/Monitor.lua` — добавлен Bus Inspector panel (live breadcrumbs + dropdown filter по addon) и стабилизирована сортировка TopN (deterministic tie-break в `SafeSort`), сохранение `busAddonFilter` в `monitorShell`; API/source proof: `CreateFrame` подтверждён через wow-api, `UIDropDownMenu_Initialize` и `ToggleDropDownMenu` подтверждены в `C:\Tools\WoW_Dev_Tools\wow-ui-source/Blizzard_UI_12.0.1.65867/Blizzard_SharedXML/UIDropDownMenu.lua:77` и `C:\Tools\WoW_Dev_Tools\wow-ui-source/Blizzard_UI_12.0.1.65867/Blizzard_SharedXML/UIDropDownMenu.lua:1049`; `todo.md` синхронизирован (Iteration 4 чекбоксы + `CONTEXT RESUME SNAPSHOT` post-pass-9); in-game smoke не запускался в этой сессии.
- 2026-02-20 (Codex, pass-10, Iteration 6 complete): `Export/Export.lua` — добавлен `BuildGitHubIssueText(sig, opts)` (issue-template с environment, message/stack, optional `locals`, `bus breadcrumbs`, `doctor extra`) и hardening `SafeDate`; `UI/Report.lua` — `UI:OpenExportGitHub(sig)`; `UI/MainFrame.lua` — dropdown action `GitHub Issue (Selected)`; `UI/Slash.lua` — команда `/rdev export github`; `UI/ExportFrame.lua` и `UI/Monitor.lua` — `OnHide` persist через `Skin:SaveFrameState(\"export\"|\"monitor\", f)`; `Export/Packer.lua` — Phase 6 rewrite: явный `byteBudgetPolicy`, последовательная deterministic деградация лимитов, лимиты/компактизация `breadcrumbs/metrics/doctor/timeline`, и deterministic tie-break для timeline сортировки; API/source proof: `GetBuildInfo`, `GetLocale`, `UnitName`, `GetRealmName`, `GetRealZoneText`, `GetSubZoneText` подтверждены через wow-api; `UIDropDownMenu_Initialize` и `ToggleDropDownMenu` подтверждены в `C:\Tools\WoW_Dev_Tools\wow-ui-source/Blizzard_UI_12.0.1.65867/Blizzard_SharedXML/UIDropDownMenu.lua:77` и `C:\Tools\WoW_Dev_Tools\wow-ui-source/Blizzard_UI_12.0.1.65867/Blizzard_SharedXML/UIDropDownMenu.lua:1049`; in-game smoke не запускался в этой сессии.
- 2026-02-20 (Codex, pass-11, Iteration 7 partial): `UI/Report.lua` — добавлены `UI:BuildValidationChecklistText()` и `UI:OpenValidationChecklist()` (runtime checklist с матрицей RDL-only/chain/combat/stress, taint `/etrace`, perf gate, export gate и release checklist); `UI/MainFrame.lua` — в export dropdown добавлен пункт `Validation Checklist`; `UI/Slash.lua` — добавлены `/rdev validate` и `/rdev release` (alias), обновлён help output; `docs/ADDON_RU.md` и `docs/INTEGRATION_RU.md` обновлены под новые команды/экспорт UX (`export github`, validation); версия поднята до `1.0.0-alpha.19.0` в `Core/Core.lua` и `!RothDevLib.toc`; API/source proof: `C_AddOns.IsAddOnLoaded` подтверждён через wow-api, `C_AddOns.IsAddOnLoaded` usage подтверждён в `C:\Tools\WoW_Dev_Tools\wow-ui-source/Blizzard_UI_12.0.1.65867/Blizzard_ChatFrameBase/SlashCommands.lua:1239`, dropdown APIs (`UIDropDownMenu_Initialize`, `ToggleDropDownMenu`) подтверждены в `C:\Tools\WoW_Dev_Tools\wow-ui-source/Blizzard_UI_12.0.1.65867/Blizzard_SharedXML/UIDropDownMenu.lua:77` и `C:\Tools\WoW_Dev_Tools\wow-ui-source/Blizzard_UI_12.0.1.65867/Blizzard_SharedXML/UIDropDownMenu.lua:1049`; in-game smoke/taint/perf execution не запускались в этой сессии.
- 2026-02-20 (Codex, pass-12, roadmap re-audit): выполнена повторная статическая сверка `MASTER ROADMAP V2` с текущим кодом (`Capture/ErrorHandler.lua`, `UI/GroupGrid.lua`, `UI/Skin.lua`, `UI/MainFrame.lua`, `UI/DetailView.lua`, `UI/Monitor.lua`, `UI/Slash.lua`, `UI/Report.lua`, `Integration/Bus.lua`, `Perf/CPU.lua`, `Perf/Mem.lua`, `Export/Export.lua`, `Export/Packer.lua`), а также docs/version (`docs/ADDON_RU.md`, `docs/INTEGRATION_RU.md`, `Core/Core.lua`, `!RothDevLib.toc`); исправлена двусмысленность статуса Iteration 7: пункт матрицы разделён на `[x] подготовить checklist template` и `[ ] выполнить in-game`; `CONTEXT RESUME SNAPSHOT` обновлён до `post-pass-12`; in-game smoke/taint/perf execution не запускались в этой сессии.
- 2026-02-20 (Codex, pass-13, UI readability hotfix): по фактическому фидбеку на UI внесены точечные правки читабельности: `UI/MainFrame.lua` — удалены проблемные Unicode-глифы из кнопок (`Sidebar/Diag/Export`), расширен activity rail (`railW`), и устранено наложение label+badge (переход на единый текст кнопки формата `Label Count`); `UI/DetailView.lua` — заменены проблемные glyph-кнопки (`Copy/Actions/Occur prev/next`) на ASCII; `UI/GroupGrid.lua`, `UI/Monitor.lua`, `UI/Report.lua` — заменены runtime Unicode-строки (`…`, `—`, `▲/▼`) на ASCII-эквиваленты для стабильного рендера шрифтов клиента; `UI/Slash.lua` — добавлена команда `/rdev uireset` (reset `uiFrames/uiPanes`), `docs/ADDON_RU.md` обновлён; статическая проверка `rg` подтвердила отсутствие non-ASCII в `UI/*.lua`; in-game visual smoke не запускался в этой сессии.
- 2026-02-20 (Codex, pass-14, UI usability layout simplification): выполнен более глубокий usability-патч по Main UI: `UI/MainFrame.lua` — activity rail отключён в default layout (`showActivityRail=false`) и убран из рабочей области, `contentLeft` пересчитан без rail, добавлен auto-select первой группы при `Refresh()` (чтобы detail pane не оставался в состоянии `No selection` при наличии ошибок), обновление grid после автоселекта; `UI/DetailView.lua` — введён `UpdateSelectionUI()` (кнопки `Export/Copy/Actions` disabled+dim без selected group), `UpdateToolbar()` теперь скрывает Occur-controls при отсутствии selection, `SetDetailPlaceholder`/`UpdateDetailView` синхронизированы с selection-state; `UI/GroupGrid.lua` — default filter area упрощён (`FILTER_H=74`), advanced controls (`session dropdown`, quick `Errors/Taints` toggles) скрыты по умолчанию для разгрузки интерфейса; статическая проверка (`rg`) подтверждает новые entry-points и отсутствие non-ASCII в `UI/*.lua`; in-game visual smoke не запускался в этой сессии.

---

## LEGACY DETAILED ITEMS (v1)
Ниже сохранён исходный детальный список (code-level), используется как технический backlog для реализации итераций.
Актуальность статусов legacy-пунктов проверяется только по `AUDIT SNAPSHOT` выше (часть legacy уже реализована частично/полностью).

---

## PHASE 1: Capture — Проверка и Доработка

### 1.1 BUG: `_BuildFilteredGroups()` не фильтрует по сессии

**Проблема:** В `UI/GroupGrid.lua:_BuildFilteredGroups()` нет параметра session.
BugSack фильтрует по All / Current / Previous, а у нас — нет.
DB уже имеет `sessionIndex` и `IterSessionGroups()`, но UI это не использует.

**Файл:** `UI/GroupGrid.lua`, функция `_BuildFilteredGroups()`

**Текущий код (строка ~260):**
```lua
for sig, g in RDL.DB:IterGroups() do
  -- фильтры: kind, addon, query, ignored
end
```

**Нужно добавить:**
```lua
-- В grid добавить поле:
grid.sessionFilter = "ALL"  -- "ALL" | "CURRENT" | "PREV" | число sessionId

-- В _BuildFilteredGroups():
local sessionFilter = grid.sessionFilter or "ALL"
local sessionId = nil
if sessionFilter == "CURRENT" then
  sessionId = RDL.DB.sessionId
elseif sessionFilter == "PREV" then
  local sessions = RDL.DB:GetSessions()
  if sessions and sessions[2] then sessionId = sessions[2].id end
elseif type(sessionFilter) == "number" then
  sessionId = sessionFilter
end

local iterator
if sessionId and sessionFilter ~= "ALL" then
  -- Используем per-session index из DB
  iterator = function()
    return RDL.DB:IterSessionGroups(sessionId)
  end
else
  iterator = function()
    return RDL.DB:IterGroups()
  end
end

for sig, g in iterator() do
  -- ... существующие фильтры kind/addon/query/ignored ...
end
```

**UI элемент — dropdown сессий:**
Добавить рядом с Kind dropdown в `InitGroupGrid()`:
```lua
local ddSession = CreateFrame("Frame", "RothDevLibSessionDropDown",
    listFrame, "UIDropDownMenuTemplate")
ddSession:SetPoint("TOPLEFT", ddAddon, "TOPRIGHT", 4, 0)
UIDropDownMenu_SetWidth(ddSession, 140)
UIDropDownMenu_SetText(ddSession, "All sessions")

UIDropDownMenu_Initialize(ddSession, function(_, level)
  local info = UIDropDownMenu_CreateInfo()
  -- "All time"
  info.text = "All time"
  info.func = function() SetSession("ALL") end
  UIDropDownMenu_AddButton(info, level)
  -- "Current session"
  info.text = "Current session"
  info.func = function() SetSession("CURRENT") end
  UIDropDownMenu_AddButton(info, level)
  -- "Previous session"
  local sessions = RDL.DB:GetSessions()
  if sessions and sessions[2] then
    info.text = "Previous: " .. (sessions[2].character or "?")
    info.func = function() SetSession("PREV") end
    UIDropDownMenu_AddButton(info, level)
  end
  -- Older sessions (до 5 штук)
  for i = 3, math.min(#sessions, 7) do
    local s = sessions[i]
    info.text = string.format("#%d %s (%s)",
        s.id, s.character or "?",
        date("%m/%d %H:%M", s.started or 0))
    info.func = function() SetSession(s.id) end
    UIDropDownMenu_AddButton(info, level)
  end
end)
```

---

### 1.2 BUG: Дублирование `_ownerTicker` и `Suppress:SuppressAll`

**Проблема:** В `ErrorHandler.lua` код создания `_ownerTicker` и вызов
`Suppress:SuppressAll` дублируется в `EarlyInit()` и `Init()`.
Тикер создаётся дважды → два watchdog'а бегают параллельно.

**Файл:** `Capture/ErrorHandler.lua`

**Где дублируется (строки ~490-520 и ~560-590):**
```lua
-- В EarlyInit():
if _G.C_Timer ... and not self._ownerTicker then
  self._ownerTicker = _G.C_Timer.NewTicker(interval, function() ... end)
end
-- ... и RDL.Suppress:SuppressAll()

-- В Init():
-- ТОТ ЖЕ КОД ПОВТОРНО
if _G.C_Timer ... and not self._ownerTicker then
  self._ownerTicker = _G.C_Timer.NewTicker(interval, function() ... end)
end
-- ... и RDL.Suppress:SuppressAll()
```

**Фикс:** Удалить дубликаты из `Init()`. Оставить только в `EarlyInit()`:
```lua
function Capture:Init()
  self:EarlyInit()  -- ← уже создаёт тикер и suppress

  -- ChatTap init (только здесь, не в EarlyInit)
  if self.ChatTap and self.ChatTap.Init then
    ...
  end

  -- ownership sync + fallback (только здесь)
  pcall(function() self:SyncOwnership("init") end)
  pcall(function() self:InstallFallbackHooks() end)

  -- Post-load recheck (только здесь)
  if _G.C_Timer ... then
    _G.C_Timer.After(1.5, function() ... end)
  end

  -- НЕ повторять: _ownerTicker, Suppress:SuppressAll
end
```

---

### 1.3 ПРОВЕРКА: ScriptErrorsFrame messageType фильтрация

**Проблема:** В `SyncScriptErrorsFrameDelta()` фильтруем `mt == 0` (hard errors).
Но в Midnight 12.x `messageType` может быть `nil` для старых записей.

**Текущий код:**
```lua
local mt = tonumber(rec.messageType)
if mt == nil or mt == 0 then  -- hard errors only
```

**Это корректно** — `nil` и `0` = hard errors, `1` = warnings.
НО нужен smoke test: `/rdev test warning` → убедиться что warning НЕ дублируется
через ScriptErrorsFrame sync (проверить что `mt == 1` пропускается).

**Тест-кейс для in-game:**
```
/rdev test warning
/rdev  → открыть UI
-- Должен быть ОДИН LUA_WARNING, не два.
-- Если два — значит ScriptErrorsFrame sync ловит warnings тоже.
```

---

### 1.4 MISSING: Сканирование версий аддонов в стеке (BugGrabber `findVersions`)

**Проблема:** BugGrabber сканирует каждую строку стека и приписывает версии аддонов.
Например: `ElvUI\Core\Modules\ActionBars.lua` → `ElvUI-13.76\Core\Modules\ActionBars.lua`
Это критично для диагностики — сразу видно какая версия аддона сломалась.

**BugGrabber код (строки ~210-260):**
```lua
local matchCache = setmetatable({}, { __index = function(self, object)
  -- 1) LibStub(object, true) → minor
  -- 2) GetAddOnMetadata(object, "X-Curse-Packaged-Version") или "Version"
  -- 3) _G[object] → scanObject → ищет .version/.revision
  -- 4) _G[OBJECT_VERSION]
end })

-- Вызывается для каждой строки стека:
function findVersions(line)
  if not line or line:find("FrameXML\\") then return line end
  for i = 1, 4 do
    line = line:gsub(matchers[i], replacer)
  end
  return line
end
```

**Где добавить в RDL:** `Util/Util.lua` — новая функция `Util:AnnotateStackVersions(stack)`

**Примерная реализация:**
```lua
local versionCache = setmetatable({}, { __index = function(self, name)
  if type(name) ~= "string" or #name < 2 then return end
  local ver
  -- 1. Metadata
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    ver = C_AddOns.GetAddOnMetadata(name, "Version")
  end
  -- 2. Global object .version
  if not ver then
    local obj = _G[name]
    if type(obj) == "table" then
      ver = obj.version or obj.Version or obj.VERSION
    end
  end
  if ver then
    self[name] = tostring(ver)
    return tostring(ver)
  end
end })

function Util:AnnotateStackVersions(stack)
  if type(stack) ~= "string" then return stack end
  local out = {}
  for line in stack:gmatch("([^\n]*)\n?") do
    local addon = line:match("Interface/AddOns/([^/]+)/")
        or line:match("AddOns\\([^\\]+)\\")
    if addon then
      local ver = versionCache[addon]
      if ver then
        line = line:gsub(addon, addon .. "-" .. ver, 1)
      end
    end
    out[#out + 1] = line
  end
  return table.concat(out, "\n")
end
```

**Где вызывать:** В `BuildEntry()` (`ErrorHandler.lua`) после получения `stackText`:
```lua
-- После строки: local stackText = tostring(stack or "")
if U and U.AnnotateStackVersions then
  stackText = U:AnnotateStackVersions(stackText)
end
```

---

### 1.5 ПРОВЕРКА: Блокировка `seterrorhandler()` другими аддонами

**Факт:** BugGrabber делает `function seterrorhandler() end` — глобальный noop.
Это значит что наш `EarlyInit()` вызов `self._real_seterrorhandler(self._handler)`
может **молча провалиться**, если BugGrabber загрузился раньше.

**Текущая защита (ErrorHandler.lua строка ~470):**
```lua
self._real_seterrorhandler = (type(_G.seterrorhandler) == "function")
    and _G.seterrorhandler or nil
```
Проблема: если BugGrabber уже заменил `seterrorhandler` на noop,
то `_real_seterrorhandler` = noop, а не настоящий `seterrorhandler`.

**Фикс — ProbeSetErrorHandler уже есть**, но не вызывается автоматически.

**Нужно:**
1. Вызвать `ProbeSetErrorHandler()` в `EarlyInit()` ПЕРЕД сохранением `_real_seterrorhandler`
2. Если проба показала что `global_ok == false` → не пытаться вызывать `seterrorhandler`,
   сразу переходить на fallback (BugGrabber import + AddLuaErrorHandler hook)

```lua
-- В EarlyInit(), ПЕРЕД self._real_seterrorhandler = ...
local probe = self:ProbeSetErrorHandler()
if probe and probe.global_ok == false then
  -- seterrorhandler заблокирован (скорее всего BugGrabber)
  self._real_seterrorhandler = nil
  self:_SetOwnershipState("blocked", "seterrorhandler-noop", {
    blockedBy = probe.before_addon or "unknown"
  })
  RDL:Log("WARN", "CAPTURE", "seterrorhandler blocked by " ..
      tostring(probe.before_addon), probe)
  -- Не пытаемся ставить handler, сразу fallback
  self:InstallFallbackHooks()
  return
end
```

---

### 1.6 MISSING: Unregister LUA_WARNING с UIParent и ScriptErrorsFrame

**Факт:** BugGrabber делает:
```lua
UIParent:UnregisterEvent("LUA_WARNING")
if ScriptErrorsFrame then
  ScriptErrorsFrame:UnregisterEvent("LUA_WARNING")
end
```
Это предотвращает показ Blizzard popup для warnings.

**Текущее состояние RDL:** В `Capture/Suppress.lua` есть `SuppressAll()` но нужно
проверить что LUA_WARNING unregister'ится.

**Файл для проверки:** `Capture/Suppress.lua`

**Нужно убедиться что есть:**
```lua
function Suppress:SuppressAll()
  -- ... existing suppress code ...

  -- Prevent Blizzard warning popups (BugGrabber parity)
  if UIParent then
    pcall(function() UIParent:UnregisterEvent("LUA_WARNING") end)
  end
  if ScriptErrorsFrame then
    pcall(function() ScriptErrorsFrame:UnregisterEvent("LUA_WARNING") end)
  end
end
```

---

### 1.7 SMOKE TEST PROTOCOL (In-Game)

Конкретные шаги для тестирования:

**Конфигурация A: RDL only (BugGrabber выключен)**
```
1. /reload
2. /rdev test hard       → проверить: группа LUA_ERROR, count=1
3. /rdev test hard       → проверить: count=2 (инкремент)
4. /rdev test warning    → проверить: группа LUA_WARNING, count=1
5. /rdev test suppressed → проверить: группа SUPPRESSED, count=1
6. /rdev test taint      → проверить: группа TAINT_BLOCKED, count=1
7. /rdev test alert      → проверить: группа ALERT, count=1
8. /rdev diag            → проверить: ownership = "owned"
```

**Конфигурация B: RDL + BugGrabber (chain mode)**
```
1. /reload
2. /rdev diag            → ownership может быть "not-owned" или "owned"
3. /buggrabber           → показывает BugGrabber DB
4. Вызвать реальную ошибку: /run error("TEST_CHAIN_MODE")
5. /rdev                 → должна быть группа с "TEST_CHAIN_MODE"
6. /buggrabber 1         → BugGrabber тоже должен её видеть
7. Проверить: в RDL UI count = 1 (не 2!)
   Если 2 → проблема с dedup между primary и fallback
```

**Конфигурация C: Combat test**
```
1. Зайти в бой (дуэль/трейнинг)
2. /run C_Timer.After(0.5, function() error("COMBAT_TEST") end)
3. После боя: /rdev → должна быть группа "COMBAT_TEST"
4. Проверить: chat notification отложена до выхода из боя
5. Проверить: /rdev diag → нет taint от RDL
```

---


## PHASE 2: UI — Конкретные Доработки

### 2.1 Session Selector (BugSack parity) — GroupGrid.lua

**Проблема:** `_BuildFilteredGroups()` итерирует ВСЕ группы.
DB уже имеет `sessionIndex` + `IterSessionGroups()` + `GetSessions()`, но UI не использует.

**Файл:** `UI/GroupGrid.lua`

**Шаг 1: Добавить state в `InitGroupGrid()`** (после строки `grid.showIgnored = false`):
```lua
grid.sessionFilter = "ALL"  -- "ALL" | "CURRENT" | "PREV" | sessionId (number)
```

**Шаг 2: Добавить dropdown в `InitGroupGrid()`** (после `ddAddon`):
```lua
local ddSession = CreateFrame("Frame", "RDLSessionDropDown",
    listFrame, "UIDropDownMenuTemplate")
ddSession:SetPoint("LEFT", chkT, "RIGHT", 64, 1)
UIDropDownMenu_SetWidth(ddSession, 145)
UIDropDownMenu_SetText(ddSession, "All sessions")
grid.sessionDropDown = ddSession

local function SetSession(val)
  grid.sessionFilter = val
  local label = "All sessions"
  if val == "CURRENT" then label = "Current"
  elseif val == "PREV" then label = "Previous"
  elseif type(val) == "number" then label = "Session #" .. val end
  UIDropDownMenu_SetText(ddSession, label)
  if UI and UI.RequestRefresh then UI:RequestRefresh("session") end
end

UIDropDownMenu_Initialize(ddSession, function(_, level)
  local info = UIDropDownMenu_CreateInfo()
  info.notCheckable = true

  info.text = "All sessions"; info.func = function() SetSession("ALL") end
  UIDropDownMenu_AddButton(info, level)

  info.text = "Current session"; info.func = function() SetSession("CURRENT") end
  UIDropDownMenu_AddButton(info, level)

  local sessions = RDL.DB and RDL.DB:GetSessions() or {}
  if sessions[2] then
    info.text = "Previous: " .. (sessions[2].character or "?")
    info.func = function() SetSession("PREV") end
    UIDropDownMenu_AddButton(info, level)
  end
  for i = 3, math.min(#sessions, 7) do
    local s = sessions[i]
    info.text = string.format("#%d %s (%s)",
      s.id, s.character or "?",
      date("%m/%d %H:%M", s.started or 0))
    local sid = s.id
    info.func = function() SetSession(sid) end
    UIDropDownMenu_AddButton(info, level)
  end
end)
```

**Шаг 3: Изменить `_BuildFilteredGroups()`** — заменить итератор:
```lua
function UI:_BuildFilteredGroups()
  local grid = self.groupGrid
  if not grid or not RDL.DB then return {} end
  -- ... существующие переменные ...

  -- NEW: Resolve session filter
  local sessionFilter = grid.sessionFilter or "ALL"
  local sessionId = nil
  if sessionFilter == "CURRENT" then
    sessionId = RDL.DB.sessionId
  elseif sessionFilter == "PREV" then
    local sessions = RDL.DB:GetSessions()
    if sessions and sessions[2] then sessionId = sessions[2].id end
  elseif type(sessionFilter) == "number" then
    sessionId = sessionFilter
  end

  -- NEW: Choose iterator
  local out = {}
  if sessionId and sessionFilter ~= "ALL" then
    -- Per-session: используем DB:IterSessionGroups (берёт из sessionIndex)
    for sig, g, _rec in RDL.DB:IterSessionGroups(sessionId) do
      if g then
        g._sig = g._sig or sig
        g.sig = g.sig or sig
        -- ... те же фильтры kind/addon/query/ignored что были ...
        -- (вынести в local function PassesFilters(g, sig))
      end
    end
  else
    -- All sessions: как было раньше
    for sig, g in RDL.DB:IterGroups() do
      -- ... фильтры ...
    end
  end
  -- ... сортировка как была ...
  return out
end
```

**Рефактор:** Вынести фильтрацию в helper чтобы не дублировать:
```lua
local function PassesFilters(g, sig, kindFilter, addonFilter,
    showIgnored, wantQuery, q)
  if not g then return false end
  if (not showIgnored) and RDL.DB:IsIgnored(sig, g.addon, g.message) then
    return false
  end
  if addonFilter ~= "ALL" and tostring(g.addon or "") ~= addonFilter then
    return false
  end
  if not MatchKind(kindFilter, g.kind) then return false end
  if wantQuery then
    local hay = Lower(BuildSearchHay(g))
    if not string.find(hay, q, 1, true) then return false end
  end
  return true
end
```

---

### 2.2 DetailView: Кнопка "Copy Message" и "Copy Locals"

**Проблема:** Сейчас есть "Copy Stack" и "Copy Sig", но нет быстрого копирования
message и locals — приходится переключать таб и делать Ctrl+A.

**Файл:** `UI/DetailView.lua`, функция `InitDetailView()`

**Добавить после `btnCopyStack`:**
```lua
local btnCopyMsg = CreateButton(tabsRow, "Copy Msg", 90, 22)
btnCopyMsg:SetPoint("RIGHT", btnCopyStack, "LEFT", -6, 0)
btnCopyMsg:SetScript("OnClick", function()
  if not UI or not UI.selectedSig or not RDL.DB then return end
  local g = RDL.DB:GetGroup(UI.selectedSig)
  local msg = (g and g.message) or ""
  if UI.ShowExport then
    UI:ShowExport("RothDevLib Copy Message", msg)
  end
end)
dv.btnCopyMsg = btnCopyMsg

local btnCopyLocals = CreateButton(tabsRow, "Copy Locals", 100, 22)
btnCopyLocals:SetPoint("RIGHT", btnCopyMsg, "LEFT", -6, 0)
btnCopyLocals:SetScript("OnClick", function()
  if not UI or not UI.selectedSig or not RDL.DB then return end
  local g = RDL.DB:GetGroup(UI.selectedSig)
  local loc = (g and g.locals) or "<no locals>"
  if UI.ShowExport then
    UI:ShowExport("RothDevLib Copy Locals", loc)
  end
end)
dv.btnCopyLocals = btnCopyLocals
```

---

### 2.3 Occur tab: Навигация prev/next + diff

**Проблема:** Occur tab показывает список, но нет навигации по отдельным occurrence.
Если 10 вхождений — трудно сравнить message/stack/locals между ними.

**Файл:** `UI/DetailView.lua`

**Шаг 1: Добавить state:**
```lua
-- В InitDetailView():
dv.occIndex = 1   -- текущий occurrence (1 = newest)
```

**Шаг 2: Добавить кнопки Prev/Next в toolbar:**
```lua
local btnOccPrev = CreateButton(tabsRow, "◄", 30, 22)
btnOccPrev:SetPoint("LEFT", dv.searchBox, "RIGHT", 6, 0)
btnOccPrev:SetScript("OnClick", function()
  dv.occIndex = math.max(1, (dv.occIndex or 1) - 1)
  if UI.UpdateDetailView then UI:UpdateDetailView(UI.selectedSig) end
end)
dv.btnOccPrev = btnOccPrev

local btnOccNext = CreateButton(tabsRow, "►", 30, 22)
btnOccNext:SetPoint("LEFT", btnOccPrev, "RIGHT", 2, 0)
btnOccNext:SetScript("OnClick", function()
  dv.occIndex = (dv.occIndex or 1) + 1
  if UI.UpdateDetailView then UI:UpdateDetailView(UI.selectedSig) end
end)
dv.btnOccNext = btnOccNext

local occLabel = tabsRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
occLabel:SetPoint("LEFT", btnOccNext, "RIGHT", 6, 0)
dv.occLabel = occLabel
```

**Шаг 3: В `UpdateDetailView()` для tab "occ" — показать single occurrence:**
```lua
elseif key == "occ" then
  local occ = g.occurrences or {}
  local idx = math.min(dv.occIndex or 1, #occ)
  if idx < 1 then idx = 1 end
  dv.occIndex = idx

  -- Update label
  if dv.occLabel then
    dv.occLabel:SetText(string.format("%d / %d", idx, #occ))
  end
  -- Show/hide prev/next based on tab
  if dv.btnOccPrev then dv.btnOccPrev:Show() end
  if dv.btnOccNext then dv.btnOccNext:Show() end

  local o = occ[idx]
  if not o then
    body = "<no occurrences>"
  else
    body = string.format("=== Occurrence %d/%d ===\n", idx, #occ)
      .. "Time: " .. SafeDate(o.ts) .. "\n"
      .. "Kind: " .. tostring(o.kind or "?") .. "\n"
      .. "Addon: " .. tostring(o.addon or "?") .. "\n"
      .. "Func: " .. tostring(o.func or "?") .. "\n"
      .. "Session: " .. tostring(o.sessionId or "?") .. "\n"
      .. "\n--- Message ---\n" .. tostring(o.message or "") .. "\n"
      .. "\n--- Stack ---\n" .. tostring(o.stack or "") .. "\n"
    if o.locals and o.locals ~= "" then
      body = body .. "\n--- Locals ---\n" .. tostring(o.locals) .. "\n"
    end
    if o.sys then
      local U = RDL.Util
      body = body .. "\n--- Sys ---\n"
        .. (U and U:SafeSerializeTable(o.sys) or tostring(o.sys)) .. "\n"
    end
  end
end
```

**Шаг 4: Скрывать occ-кнопки на других табах:**
В `UpdateToolbar`:
```lua
if dv.btnOccPrev then
  if isOcc then dv.btnOccPrev:Show() else dv.btnOccPrev:Hide() end
end
if dv.btnOccNext then
  if isOcc then dv.btnOccNext:Show() else dv.btnOccNext:Hide() end
end
if dv.occLabel then
  if isOcc then dv.occLabel:Show() else dv.occLabel:Hide() end
end
```

---

### 2.4 GroupGrid: Column resize + drag

**Проблема:** Ширина колонок жёстко задана в `COLS`, не учитывает размер окна.
Колонка Message получает `w=999` (fill), но Kind=90 может быть слишком много, а Addon=120 мало.

**Файл:** `UI/GroupGrid.lua`

**Минимальный подход — автоширина по frame:**
В `ApplyGroupGridLayout()` пересчитать колонки:
```lua
function UI:ApplyGroupGridLayout(reason)
  local grid = self.groupGrid
  if not grid or not grid.listFrame then return end
  local listFrame = grid.listFrame
  local totalW = listFrame:GetWidth() - 30  -- scrollbar

  -- Proportional: Kind=10%, Addon=15%, Count=7%, Last=8%, Msg=60%
  local proportions = { 0.10, 0.15, 0.07, 0.08, 0.60 }
  for i, hb in ipairs(grid.headers or {}) do
    local w = math.floor(totalW * (proportions[i] or 0.10))
    if w < 40 then w = 40 end
    hb:SetWidth(w)
  end

  -- Обновить ряды: пересчитать x-позиции колонок
  -- ... (аналогично) ...
end
```

**Сложнее (drag resize):** Требует drag handle между headers.
Пока рекомендуется **пропустить** drag и сделать пропорциональное авто-sizing.

---

### 2.5 Export: Format Selector dropdown

**Проблема:** Сейчас 4 кнопки Export (All, Selected, JSON, Pack).
Нужен единый dropdown с выбором формата + scope.

**Файл:** `UI/MainFrame.lua`, секция `btnExport`

**Улучшение:** Добавить "Export Current View" (filtered) рядом с существующими:
```lua
-- В exportDD UIDropDownMenu_Initialize добавить:
info.text = "Export Current View"
info.func = function()
  if UI.OpenGridExport then
    UI:OpenGridExport({ includeOccurrences = true })
  end
end
UIDropDownMenu_AddButton(info, level)

-- Разделитель
info.text = ""
info.disabled = true
info.notClickable = true
UIDropDownMenu_AddButton(info, level)

-- Диагностический отчёт (Phase 5 — Debug Report)
info.text = "Debug Report"
info.disabled = false
info.notClickable = false
info.func = function()
  if UI.OpenDebugReport then UI:OpenDebugReport() end
end
UIDropDownMenu_AddButton(info, level)
```

---



## PHASE 3: Bus Inspector + Profiling Доработки

### 3.1 NEW: `/rdev bus [addonName]` — Просмотр breadcrumbs из чата

**Проблема:** Bus breadcrumbs видны только через Doctor tab в DetailView (при выборе группы).
Нет способа посмотреть текущие breadcrumbs live без ошибки.

**Файл:** `UI/Slash.lua`

**Добавить после блока `if msg == "storm" then ... end`:**
```lua
local busCmd, busArg = msg:match("^(bus)%s*(.*)$")
if busCmd == "bus" then
  if not RDL.Bus then
    print("|cffffff00RothDevLib|r Bus module not loaded.")
    return
  end

  local addonName = busArg ~= "" and rawMsg:match("^[Bb][Uu][Ss]%s+(.+)$") or nil

  if not addonName then
    -- List all registered addons
    print("|cffffff00RothDevLib|r Bus — registered addons:")
    local count = 0
    if RDL.Bus._addons then
      for name, a in pairs(RDL.Bus._addons) do
        local sz = a.size or 0
        local mx = a.max or 80
        print(("  %s: %d/%d breadcrumbs"):format(name, sz, mx))
        count = count + 1
      end
    end
    if count == 0 then
      print("  (none — use RDL:InitAddon('MyAddon') to register)")
    end
    return
  end

  -- Show breadcrumbs for specific addon
  local crumbs = RDL.Bus:GetBreadcrumbSnapshot(addonName, 20)
  if not crumbs or #crumbs == 0 then
    print("|cffffff00RothDevLib|r No breadcrumbs for: " .. addonName)
    return
  end

  print("|cffffff00RothDevLib|r Bus [" .. addonName .. "] last " .. #crumbs .. ":")
  for i, c in ipairs(crumbs) do
    local ts = c.ts and date("%H:%M:%S", c.ts) or "?"
    local line = ("  %d) [%s] [%s] %s"):format(
      i, ts, tostring(c.cat or "?"), tostring(c.msg or ""))
    if c.data and c.data ~= "" then
      local d = tostring(c.data)
      if #d > 80 then d = d:sub(1, 80) .. "…" end
      line = line .. " | " .. d
    end
    print(line)
  end
  return
end
```

**Также добавить в help-блок:**
```lua
print("  /rdev bus — list registered addons")
print("  /rdev bus <AddonName> — show last 20 breadcrumbs")
```

---


### 3.2 NEW: Bus Inspector Panel в Monitor

**Проблема:** Monitor показывает CPU/Mem/Alerts, но не Bus breadcrumbs.
Для live-debugging нужно видеть последние breadcrumbs всех аддонов в реальном времени.

**Файл:** `UI/Monitor.lua`

**Шаг 1: Добавить третью inset-панель под Alerts:**

Реорганизация layout в `InitMonitorFrame()`:
- Уменьшить CPU/Mem панели: `BOTTOMLEFT` → `f, "BOTTOMLEFT", 16, 280` (было 152)
- Alerts: высота 120, `BOTTOMLEFT ... 16, 152` (как было)
- **NEW Bus panel:** высота 120, `BOTTOMLEFT ... 16, 16`

```lua
-- Bus Inspector panel (добавить после alertsFrame)
local busFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
busFrame:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 16)
busFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 16)
busFrame:SetHeight(120)
if Skin and Skin.ApplyInset then Skin:ApplyInset(busFrame) end

-- Сдвинуть alertsFrame вверх:
alertsFrame:ClearAllPoints()
alertsFrame:SetPoint("BOTTOMLEFT", busFrame, "TOPLEFT", 0, 6)
alertsFrame:SetPoint("BOTTOMRIGHT", busFrame, "TOPRIGHT", 0, 6)
alertsFrame:SetHeight(120)

local busLabel = busFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
busLabel:SetPoint("TOPLEFT", busFrame, "TOPLEFT", 10, -8)
busLabel:SetText("Bus Live")

-- Addon selector dropdown
local ddBusAddon = CreateFrame("Frame", "RDLMonitorBusDD",
    busFrame, "UIDropDownMenuTemplate")
ddBusAddon:SetPoint("TOPLEFT", busLabel, "TOPRIGHT", 4, 8)
UIDropDownMenu_SetWidth(ddBusAddon, 140)
UIDropDownMenu_SetText(ddBusAddon, "(all)")
self._monitor.busAddonFilter = nil

UIDropDownMenu_Initialize(ddBusAddon, function(_, level)
  local info = UIDropDownMenu_CreateInfo()
  info.notCheckable = true

  info.text = "(all registered)"
  info.func = function()
    UI._monitor.busAddonFilter = nil
    UIDropDownMenu_SetText(ddBusAddon, "(all)")
    UI:RefreshMonitor()
  end
  UIDropDownMenu_AddButton(info, level)

  if RDL.Bus and RDL.Bus._addons then
    for name, _ in pairs(RDL.Bus._addons) do
      info.text = name
      local n = name
      info.func = function()
        UI._monitor.busAddonFilter = n
        UIDropDownMenu_SetText(ddBusAddon, n)
        UI:RefreshMonitor()
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end
end)

local busScroll = CreateFrame("ScrollFrame", nil, busFrame,
    "UIPanelScrollFrameTemplate")
busScroll:SetPoint("TOPLEFT", busFrame, "TOPLEFT", 8, -28)
busScroll:SetPoint("BOTTOMRIGHT", busFrame, "BOTTOMRIGHT", -28, 8)

local busEdit = CreateFrame("EditBox", nil, busScroll)
busEdit:SetMultiLine(true)
busEdit:SetAutoFocus(false)
busEdit:SetFontObject(ChatFontNormal)
-- ... стандартный UpdateWidth pattern ...
busEdit:SetText("")
busEdit:SetScript("OnEscapePressed", function() busEdit:ClearFocus() end)
busScroll:SetScrollChild(busEdit)

self._monitor.busEdit = busEdit
```

**Шаг 2: Добавить helper `CollectBusBreadcrumbs()` в Monitor.lua:**
```lua
local function CollectBusBreadcrumbs(addonFilter, limit)
  limit = limit or 15
  if not RDL.Bus or not RDL.Bus._addons then return "(bus not loaded)" end

  local lines = {}
  local addons = {}
  if addonFilter then
    addons[1] = addonFilter
  else
    for name in pairs(RDL.Bus._addons) do
      addons[#addons + 1] = name
    end
    table.sort(addons)
  end

  for _, name in ipairs(addons) do
    local crumbs = RDL.Bus:GetBreadcrumbSnapshot(name, limit)
    if crumbs and #crumbs > 0 then
      lines[#lines + 1] = "— " .. name .. " (" .. #crumbs .. ") —"
      for i, c in ipairs(crumbs) do
        local ts = c.ts and date("%H:%M:%S", c.ts) or "?"
        local entry = ("[%s] [%s] %s"):format(ts, c.cat or "?", c.msg or "")
        if c.data and c.data ~= "" then
          local d = tostring(c.data)
          if #d > 60 then d = d:sub(1, 60) .. "…" end
          entry = entry .. " | " .. d
        end
        lines[#lines + 1] = entry
      end
      lines[#lines + 1] = ""
    end
  end

  if #lines == 0 then return "(no breadcrumbs)" end
  return table.concat(lines, "\n")
end
```

**Шаг 3: В `RefreshMonitor()` добавить:**
```lua
if self._monitor.busEdit then
  local busText = CollectBusBreadcrumbs(
    self._monitor.busAddonFilter, 15)
  self._monitor.busEdit:SetText(busText or "")
end
```

---


### 3.3 BUG: CPU/Mem spike thresholds не настраиваются через UI

**Проблема:** Spike thresholds задаются в DB settings (`cpuSpikeMs=16`, `memSpikeKB=64`),
но нет UI для их изменения. Пользователь должен вручную менять SavedVariables.

**Файл:** `UI/MainFrame.lua` — секция Settings (если есть) или новый Settings panel.

**Минимальное решение — slash command `/rdev set`:**

**Файл:** `UI/Slash.lua`

```lua
local setCmd, setKey, setVal = msg:match("^(set)%s+(%S+)%s+(.+)$")
if setCmd == "set" then
  local settings = RDL.DB and RDL.DB:GetSettings()
  if not settings then
    print("|cffff3333RothDevLib|r DB not ready.")
    return
  end

  -- Whitelist of safe keys
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
    maxBreadcrumbsPerAddon = "number",
    breadcrumbsPerError = "number",
    monitorTopN = "number",
    monitorRefreshSec = "number",
    stormBurstLimit = "number",
    stormPerSecondLimit = "number",
  }

  local keyType = allowed[setKey]
  if not keyType then
    print("|cffff3333RothDevLib|r Unknown setting: " .. tostring(setKey))
    print("  Allowed: " .. table.concat((function()
      local ks = {}
      for k in pairs(allowed) do ks[#ks+1] = k end
      table.sort(ks)
      return ks
    end)(), ", "))
    return
  end

  local parsed
  if keyType == "number" then
    parsed = tonumber(setVal)
    if not parsed then
      print("|cffff3333RothDevLib|r Expected number for " .. setKey)
      return
    end
  elseif keyType == "bool" then
    if setVal == "true" or setVal == "1" or setVal == "on" then
      parsed = true
    elseif setVal == "false" or setVal == "0" or setVal == "off" then
      parsed = false
    else
      print("|cffff3333RothDevLib|r Expected true/false for " .. setKey)
      return
    end
  end

  local old = settings[setKey]
  settings[setKey] = parsed
  print("|cffffff00RothDevLib|r set " .. setKey .. " = "
    .. tostring(parsed) .. " (was " .. tostring(old) .. ")")
  return
end
```

**Также `/rdev get [key]`:**
```lua
local getCmd, getKey = msg:match("^(get)%s*(.*)$")
if getCmd == "get" then
  local settings = RDL.DB and RDL.DB:GetSettings()
  if not settings then
    print("|cffff3333RothDevLib|r DB not ready.")
    return
  end
  if getKey and getKey ~= "" then
    print("|cffffff00RothDevLib|r " .. getKey .. " = " .. tostring(settings[getKey]))
  else
    -- Dump all numeric/bool settings
    local keys = {}
    for k, v in pairs(settings) do
      if type(v) == "number" or type(v) == "boolean" then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys)
    print("|cffffff00RothDevLib|r settings:")
    for _, k in ipairs(keys) do
      print("  " .. k .. " = " .. tostring(settings[k]))
    end
  end
  return
end
```

**Help:**
```lua
print("  /rdev set <key> <value> — change setting")
print("  /rdev get [key] — show settings")
```

---

### 3.4 MISSING: CPU.lua и Mem.lua — нет ResetStats()

**Проблема:** Нет способа сбросить накопленную статистику без `/rdev clear` (который стирает всё).
Нужен отдельный сброс профилинга.

**Файл:** `Perf/CPU.lua`

**Добавить:**
```lua
function CPU:ResetStats()
  for k in pairs(self._stats) do self._stats[k] = nil end
  for k in pairs(self._lastAlert) do self._lastAlert[k] = nil end
end
```

**Файл:** `Perf/Mem.lua`

**Добавить:**
```lua
function Mem:ResetStats()
  for k in pairs(self._stats) do self._stats[k] = nil end
  for k in pairs(self._lastAlert) do self._lastAlert[k] = nil end
  for k in pairs(self._lastSample) do self._lastSample[k] = nil end
end
```

**Файл:** `UI/Slash.lua` — добавить команду:
```lua
if msg == "perfclear" or msg == "perfreset" then
  if RDL.CPU and RDL.CPU.ResetStats then RDL.CPU:ResetStats() end
  if RDL.Mem and RDL.Mem.ResetStats then RDL.Mem:ResetStats() end
  print("|cffffff00RothDevLib|r Profiling stats cleared.")
  if UI and UI.RefreshMonitor then UI:RefreshMonitor() end
  return
end
```

---

### 3.5 MISSING: Bus:GetAllAddonNames() — helper для UI

**Проблема:** Monitor dropdown и `/rdev bus` оба итерируют `Bus._addons` напрямую.
Нужен clean public API.

**Файл:** `Integration/Bus.lua`

**Добавить:**
```lua
function Bus:GetAllAddonNames()
  local out = {}
  if self._addons then
    for name in pairs(self._addons) do
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

function Bus:GetAddonStats(addonName)
  local a = self._addons and self._addons[addonName]
  if not a then return nil end
  return {
    name = a.name,
    size = a.size or 0,
    max = a.max or 80,
    head = a.head or 0,
  }
end
```

---


## PHASE 4: Export / Share Доработки

### 4.1 MISSING: Clipboard-friendly одноклик export

**Проблема:** Чтобы скопировать ошибку нужно: выбрать → Copy Stack → Ctrl+A → Ctrl+C.
Для отправки в Discord/GitHub нужен форматированный блок с message+stack+locals за один клик.

**Файл:** `UI/DetailView.lua`

**Добавить кнопку "Copy All" рядом с "Export View":**
```lua
local btnCopyAll = CreateButton(tabsRow, "Copy All", 90, 22)
btnCopyAll:SetPoint("RIGHT", dv.btnExportFiltered, "LEFT", -6, 0)
btnCopyAll:SetScript("OnClick", function()
  if not UI or not UI.selectedSig or not RDL.DB then return end
  local g = RDL.DB:GetGroup(UI.selectedSig)
  if not g then return end

  local parts = {}
  parts[#parts + 1] = "**" .. tostring(g.kind or "ERROR") .. "** — "
    .. tostring(g.addon or "?") .. " (x" .. tostring(g.count or 1) .. ")"
  parts[#parts + 1] = ""
  parts[#parts + 1] = "Message:"
  parts[#parts + 1] = "```"
  parts[#parts + 1] = tostring(g.message or "")
  parts[#parts + 1] = "```"
  parts[#parts + 1] = ""
  parts[#parts + 1] = "Stack:"
  parts[#parts + 1] = "```"
  parts[#parts + 1] = tostring(g.stack or "")
  parts[#parts + 1] = "```"
  if g.locals and g.locals ~= "" then
    parts[#parts + 1] = ""
    parts[#parts + 1] = "Locals:"
    parts[#parts + 1] = "```"
    parts[#parts + 1] = tostring(g.locals)
    parts[#parts + 1] = "```"
  end
  if g.origin and g.origin.addon then
    parts[#parts + 1] = ""
    parts[#parts + 1] = "Origin: " .. tostring(g.origin.addon)
      .. " " .. tostring(g.origin.file or "?")
      .. ":" .. tostring(g.origin.line or "?")
  end

  local text = table.concat(parts, "\n")
  if UI.ShowExport then
    UI:ShowExport("RothDevLib — Copy All (Markdown)", text)
  end
end)
dv.btnCopyAll = btnCopyAll
```

**Также сдвинуть кнопки: btnCopyStack, btnCopySig, btnCopyMsg, btnCopyLocals
якорить от btnCopyAll влево.**

---

### 4.2 ENHANCEMENT: Packer — включить Bus breadcrumbs в packed JSON

**Проблема:** `Packer:BuildPackedJSON()` включает группы и timeline, но не breadcrumbs.
Для LLM-анализа breadcrumbs дают контекст "что делал аддон до ошибки".

**Файл:** `Export/Packer.lua`

**В функции `BuildPackedJSON()` после секции groups, добавить:**
```lua
-- Breadcrumbs section (if Bus registered addons exist)
if RDL.Bus and RDL.Bus._addons then
  local busData = {}
  for addonName, a in pairs(RDL.Bus._addons) do
    if (a.size or 0) > 0 then
      local crumbs = RDL.Bus:GetBreadcrumbSnapshot(addonName, 8)
      if crumbs and #crumbs > 0 then
        local compact = {}
        for i, c in ipairs(crumbs) do
          compact[i] = {
            t = c.ts,
            c = Trim(c.cat, 20),
            m = Trim(c.msg, 60),
          }
          if c.data and c.data ~= "" then
            compact[i].d = Trim(tostring(c.data), 80)
          end
        end
        busData[addonName] = compact
      end
    end
  end
  if next(busData) then
    obj.bus = busData
  end
end
```

---

### 4.3 ENHANCEMENT: Export — structured JSON для GitHub issue template

**Проблема:** JSON export (`/rdev export json`) выдаёт полный дамп.
Для GitHub issue нужен компактный шаблон.

**Файл:** `Export/Export.lua`

**Добавить функцию:**
```lua
function Export:BuildGitHubIssueText(sig)
  local g = sig and RDL.DB and RDL.DB:GetGroup(sig)
  if not g then return nil end

  local lines = {}
  lines[#lines + 1] = "## Bug Report (auto-generated by RothDevLib)"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "**Addon:** " .. tostring(g.addon or "?")
  lines[#lines + 1] = "**Kind:** " .. tostring(g.kind or "?")
  lines[#lines + 1] = "**Count:** " .. tostring(g.count or 0)
  lines[#lines + 1] = "**WoW Build:** " .. tostring(select(4, GetBuildInfo()))
  lines[#lines + 1] = ""
  lines[#lines + 1] = "### Error Message"
  lines[#lines + 1] = "```"
  local msg = tostring(g.message or "")
  if #msg > 500 then msg = msg:sub(1, 500) .. "…" end
  lines[#lines + 1] = msg
  lines[#lines + 1] = "```"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "### Stack Trace"
  lines[#lines + 1] = "```lua"
  local stack = tostring(g.stack or "")
  if #stack > 2000 then stack = stack:sub(1, 2000) .. "\n…" end
  lines[#lines + 1] = stack
  lines[#lines + 1] = "```"

  if g.locals and g.locals ~= "" then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "<details><summary>Locals</summary>"
    lines[#lines + 1] = ""
    lines[#lines + 1] = "```"
    local loc = tostring(g.locals)
    if #loc > 2000 then loc = loc:sub(1, 2000) .. "\n…" end
    lines[#lines + 1] = loc
    lines[#lines + 1] = "```"
    lines[#lines + 1] = "</details>"
  end

  return table.concat(lines, "\n")
end
```

**Добавить в ExportFrame.lua (dropdown) или DetailView:**
```lua
-- В export dropdown или как кнопку в DetailView:
info.text = "GitHub Issue Template"
info.func = function()
  local text = RDL.Export:BuildGitHubIssueText(UI.selectedSig)
  if text then
    UI:ShowExport("GitHub Issue Template", text)
  else
    UI:ShowExport("GitHub Issue", "Select an error group first.")
  end
end
```

**Slash:** `/rdev export github` → вызывает `BuildGitHubIssueText(UI.selectedSig)`.

---

### 4.4 BUG: ExportFrame не запоминает позицию при повторном открытии

**Проблема:** `EnsureExportFrame()` вызывает `Skin:RestoreFrameState("export", f, ...)`,
но `SaveFrameState` вызывается только при drag-stop. Если окно закрывается через X —
позиция может не сохраняться.

**Файл:** `UI/ExportFrame.lua`

**Исправить:** Добавить OnHide handler:
```lua
f:SetScript("OnHide", function()
  if Skin and Skin.SaveFrameState then
    Skin:SaveFrameState("export", f)
  end
end)
```

**Проверить:** то же самое для MonitorFrame (`UI/Monitor.lua`):
```lua
-- В InitMonitorFrame(), после f:Hide():
f:SetScript("OnHide", function()
  if Skin and Skin.SaveFrameState then
    Skin:SaveFrameState("monitor", f)
  end
end)
```

---


## PHASE 5: Debug Report + Diagnostics

### 5.1 NEW: `UI:OpenDebugReport()` — Comprehensive One-Click Diagnostic

**Проблема:** `/rdev diag` выводит только в чат (ограничено длиной), `/rdev status` — минимум.
Нужен полный Debug Report в ExportFrame для копирования в Discord/GitHub.

**Файл:** Новый файл `UI/DebugReport.lua` (или добавить в `UI/Report.lua`)

**Рекомендация:** Добавить в `UI/Report.lua` — там уже есть `BuildHeader()` и export helpers.

```lua
-- В UI/Report.lua добавить:

function UI:BuildDebugReportText()
  if not RDL.DB then return "DB not loaded" end
  local settings = RDL.DB:GetSettings() or {}
  local cap = RDL.Capture
  local lines = {}

  -- Header
  table.insert(lines, "=== RothDevLib Debug Report ===")
  table.insert(lines, "Time: " .. date("%Y-%m-%d %H:%M:%S"))
  table.insert(lines, "Version: " .. tostring(RDL.version or "?"))
  table.insert(lines, "WoW Build: " .. tostring(select(4, GetBuildInfo())))
  table.insert(lines, "Player: " .. tostring(UnitName("player") or "?")
    .. "-" .. tostring(GetRealmName() or "?"))
  table.insert(lines, "Zone: " .. tostring(GetRealZoneText() or "?")
    .. " / " .. tostring(GetSubZoneText() or "?"))
  table.insert(lines, "")

  -- Handler Ownership
  table.insert(lines, "--- Error Handler ---")
  if cap then
    if cap.SyncOwnership then
      pcall(function() cap:SyncOwnership("report") end)
    end
    table.insert(lines, "ownsHandler: " .. tostring(cap.ownsHandler))
    if cap.ownerInfo then
      local oi = cap.ownerInfo
      table.insert(lines, "reason: " .. tostring(oi.reason or "?"))
      table.insert(lines, "nowHandlerAddon: " .. tostring(oi.nowHandlerAddon or "?"))
      table.insert(lines, "nowHandlerSrc: " .. tostring(oi.nowHandlerSrc or "?"))
      table.insert(lines, "seterrorhandlerSrc: "
        .. tostring(oi.seterrorhandlerSrc or "?"))
      if oi.addons then
        table.insert(lines, "BugGrabber: "
          .. tostring(oi.addons.BugGrabber))
        table.insert(lines, "BugSack: "
          .. tostring(oi.addons.BugSack))
        table.insert(lines, "DebugTools: "
          .. tostring(oi.addons.DebugTools))
      end
    end

    -- Probe seterrorhandler state
    if cap.ProbeSetErrorHandler then
      local ok, p = pcall(function() return cap:ProbeSetErrorHandler() end)
      if ok and p then
        table.insert(lines, "setEH.global_ok: " .. tostring(p.global_ok))
        table.insert(lines, "setEH.global_src: " .. tostring(p.global_src))
        table.insert(lines, "setEH.real_ok: " .. tostring(p.real_ok))
        table.insert(lines, "handler.before_addon: "
          .. tostring(p.before_addon or "?"))
      end
    end

    -- Fallback hooks
    if cap._fallback then
      local fb = cap._fallback
      table.insert(lines, "fallback.scriptErrorsHooked: "
        .. tostring(fb.scriptErrorsHooked))
      table.insert(lines, "fallback.bugGrabberEnabled: "
        .. tostring(fb.bugGrabberEnabled))
    end
  else
    table.insert(lines, "Capture: NOT LOADED")
  end
  table.insert(lines, "")

  -- Session
  table.insert(lines, "--- Session ---")
  if RDL.DB.session then
    local s = RDL.DB.session
    table.insert(lines, "id: " .. tostring(s.id))
    table.insert(lines, "started: " .. date("%Y-%m-%d %H:%M:%S",
      s.started or 0))
    table.insert(lines, "character: " .. tostring(s.character or "?"))
    table.insert(lines, "errors: " .. tostring(s.errors or 0))
    table.insert(lines, "warnings: " .. tostring(s.warnings or 0))
    table.insert(lines, "taints: " .. tostring(s.taints or 0))
    table.insert(lines, "suppressed: " .. tostring(s.suppressed or 0))
    table.insert(lines, "alerts: " .. tostring(s.alerts or 0))
    table.insert(lines, "asserts: " .. tostring(s.asserts or 0))
  end
  table.insert(lines, "")

  -- DB Stats
  table.insert(lines, "--- Database ---")
  local groupCount = 0
  local byKind = {}
  if RDL.DB.IterGroups then
    for _, g in RDL.DB:IterGroups() do
      groupCount = groupCount + 1
      local k = g.kind or "?"
      byKind[k] = (byKind[k] or 0) + 1
    end
  end
  table.insert(lines, "groups: " .. groupCount
    .. " / " .. tostring(settings.maxGroups or 200))
  for k, n in pairs(byKind) do
    table.insert(lines, "  " .. k .. ": " .. n)
  end
  local sessions = RDL.DB.GetSessions and RDL.DB:GetSessions() or {}
  table.insert(lines, "sessions: " .. #sessions)
  table.insert(lines, "")

  -- Storm Stats
  table.insert(lines, "--- Storm (Flood Protection) ---")
  if RDL.Storm then
    local stats = RDL.Storm:GetStats()
    table.insert(lines, "total: " .. tostring(stats.total))
    table.insert(lines, "throttled: " .. tostring(stats.throttled))
    if stats.buckets then
      for kind, b in pairs(stats.buckets) do
        table.insert(lines, "  " .. kind .. ": tokens="
          .. string.format("%.1f", b.tokens or 0))
      end
    end
  else
    table.insert(lines, "Storm: NOT LOADED")
  end
  table.insert(lines, "")

  -- Bus Stats
  table.insert(lines, "--- Bus (Breadcrumbs) ---")
  if RDL.Bus and RDL.Bus._addons then
    local count = 0
    for name, a in pairs(RDL.Bus._addons) do
      table.insert(lines, "  " .. name .. ": "
        .. tostring(a.size or 0) .. "/" .. tostring(a.max or 80))
      count = count + 1
    end
    if count == 0 then
      table.insert(lines, "  (no registered addons)")
    end
  else
    table.insert(lines, "Bus: NOT LOADED")
  end
  table.insert(lines, "")

  -- Perf Stats Summary
  table.insert(lines, "--- Perf Profiling ---")
  table.insert(lines, "enabled: " .. tostring(settings.enablePerfProfiling))
  table.insert(lines, "cpuSampleRate: " .. tostring(settings.cpuSampleRate))
  table.insert(lines, "cpuSpikeMs: " .. tostring(settings.cpuSpikeMs))
  table.insert(lines, "memWatchEnabled: " .. tostring(settings.memWatchEnabled))
  if RDL.CPU and RDL.CPU._stats then
    local n = 0
    for _ in pairs(RDL.CPU._stats) do n = n + 1 end
    table.insert(lines, "CPU tracked keys: " .. n)
  end
  if RDL.Mem and RDL.Mem._stats then
    local n = 0
    for _ in pairs(RDL.Mem._stats) do n = n + 1 end
    table.insert(lines, "MEM tracked keys: " .. n)
  end
  table.insert(lines, "")

  -- UI State
  table.insert(lines, "--- UI ---")
  table.insert(lines, "uiLoaded: "
    .. tostring(UI and type(UI.Toggle) == "function"))
  table.insert(lines, "liveDisabled: "
    .. tostring(UI and UI._liveDisabled))
  if UI and UI._lastUIError then
    table.insert(lines, "lastUIError: " .. tostring(UI._lastUIError))
  end
  table.insert(lines, "minimapHidden: "
    .. tostring(settings.minimap and settings.minimap.hide))
  table.insert(lines, "")

  -- Event Registration Errors
  local evErrs = RDL._eventRegErrors or {}
  if #evErrs > 0 then
    table.insert(lines, "--- Event Registration Errors ---")
    for i = math.max(1, #evErrs - 4), #evErrs do
      local e = evErrs[i]
      table.insert(lines, "  " .. tostring(e.event or "?")
        .. " — " .. tostring(e.err or "?"))
    end
    table.insert(lines, "")
  end

  -- Key Settings
  table.insert(lines, "--- Key Settings ---")
  local keySettings = {
    "errorHandlerMode", "chainCallPrevHandler",
    "maintainOwnership", "lockErrorHandler",
    "hideTaintPopups", "hideBlizzardScriptErrors",
    "chatNotifyOnError", "captureChatErrors",
    "fallbackHookScriptErrors", "importBugGrabber",
    "captureLocals", "stormErrorsPerSec",
  }
  for _, k in ipairs(keySettings) do
    table.insert(lines, "  " .. k .. ": " .. tostring(settings[k]))
  end
  table.insert(lines, "")

  -- Loaded Addons (error-related)
  table.insert(lines, "--- Related Addons ---")
  local checkAddons = {
    "!BugGrabber", "BugSack", "!Swatter", "TekErr",
    "ErrorMonster", "!BugGrabber_ErrorLog",
  }
  for _, name in ipairs(checkAddons) do
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
      and C_AddOns.IsAddOnLoaded(name)
    if loaded then
      local ver = C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata(name, "Version") or "?"
      table.insert(lines, "  " .. name .. ": LOADED v" .. tostring(ver))
    end
  end
  table.insert(lines, "")

  return table.concat(lines, "\n")
end

function UI:OpenDebugReport()
  if not self.ShowExport then return end
  local text = self:BuildDebugReportText()
  self:ShowExport("RothDevLib Debug Report", text)
end
```

---

### 5.2 Slash command: `/rdev debug`

**Файл:** `UI/Slash.lua`

```lua
if msg == "debug" or msg == "debugreport" then
  if UI and UI.Init and not UI.frame then
    pcall(function() UI:Init() end)
  end
  if UI and UI.OpenDebugReport then
    UI:OpenDebugReport()
  else
    -- Fallback: print to chat
    print("|cffff3333RothDevLib|r Debug report UI not available. Use /rdev diag.")
  end
  return
end
```

**Help:**
```lua
print("  /rdev debug — full debug report (exportable)")
```

---

### 5.3 TOC: Register DebugReport или убедиться Report.lua загружается

**Файл:** `!RothDevLib.toc`

**Проверить:** `UI/Report.lua` уже в TOC? Если да — достаточно добавить
`BuildDebugReportText()` + `OpenDebugReport()` в этот файл.
Если нет — добавить строку:
```
UI\Report.lua
```
после `UI\ExportFrame.lua`.

---
