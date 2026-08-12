# RothDevLib UI Rewrite — TODO Tracker
# Обновлять по мере выполнения!
# Создано: 2026-02-20
# Последнее обновление: ALL STAGES COMPLETE (0-6) — остался только тест в игре

## RECOVERY INFO (если контекст сжался)
## Проект: корень репозитория `!RothDevLib`
## План: UI_REWRITE_PLAN.md (v2 — лёгкий подход, 0 новых файлов)
## Суть: заменить cluttered UI на чистый тёмный layout с tab-переключением режимов
## Ключевые изменения:
##   - BasicFrameTemplateWithInset → BackdropTemplate + custom TitleBar
##   - Tabs: Errors / Monitor / Log (вместо кнопок в header)
##   - StatusBar внизу: summary + Export/Ignore/Clear
##   - Search в toolbar (не в GroupGrid)
##   - Тёмная палитра через Skin.C + helpers (Skin:DarkFrame, StyledButton, TabButton, etc.)
##   - Удалены: ActivityRail, DiagnosticsFrame, hSplitter, header/footer scattered buttons

## ФАЙЛЫ ИЗМЕНЁННЫЕ (финальный стейт):
## [DONE] UI/Skin.lua — добавлены Skin.C (палитра), Skin.BD (backdrops), 6 helpers
## [DONE] UI/MainFrame.lua — ПОЛНАЯ ПЕРЕПИСКА + Stage4 embed + Stage6 closeBtn
## [DONE] UI/GroupGrid.lua — ПЕРЕПИСКА (FILTER_H 74→30, search удалён, тёмные строки/заголовки)
## [DONE] UI/DetailView.lua — ПЕРЕПИСКА (Skin:TabButton, StyledButton, DarkInset, no PanelTemplates)
## [DONE] UI/Monitor.lua — ПЕРЕПИСКА (_BuildMonitorPanels, embedded+standalone, dark theme)
## [DONE] UI/ExportFrame.lua — ПЕРЕПИСКА (BackdropTemplate, dark titleBar/body/buttons)
## [OK]   UI/Slash.lua — без изменений (совместим)
## [OK]   UI/MinimapButton.lua — без изменений (совместим)
## [OK]   UI/AddonCompartment.lua — без изменений (совместим)

---

## ЭТАП 0: Theme (палитра + helpers в Skin.lua) — DONE ✅
- [x] Skin.C — 25 цветов тёмной палитры
- [x] Skin.BD — dialog (border) + flat backdrops
- [x] Skin:DarkFrame(frame, bdKey) — apply dark panel
- [x] Skin:DarkInset(frame) — dark inset panel
- [x] Skin:StyledButton(parent, text, w, h) — тёмная кнопка с hover/press
- [x] Skin:TabButton(parent, text, w, h) — tab с active/inactive + badge
- [x] Skin:Badge(parent, size) — standalone badge circle
- [x] Skin:SearchBox(parent, w, h) — dark search input с placeholder + clear
- [ ] Тест в игре

## ЭТАП 1: MainFrame.lua — новый shell — DONE ✅
- [x] BackdropTemplate + custom TitleBar (drag area, title+version, status, close)
- [x] Toolbar: TabButton(Errors) + TabButton(Monitor) + TabButton(Log) + SearchBox
- [x] 3 content areas (contentErrors / contentMonitor / contentLog), только один видим
- [x] StatusBar: summaryText + Export▾ / IgnoreSig / IgnoreAddon / ClearAll
- [x] Errors content: listFrame + splitter + detailFrame (GroupGrid + DetailView)
- [x] Monitor content: placeholder + "Open Monitor Window" (до Этапа 4)
- [x] Log content: scrollable EditBox + Refresh button
- [x] Persist: splitRatio + activeMode в mainShell paneState
- [x] Live updates: RDL_CAPTURE callback
- [x] SearchBox → grid.query (fix: было grid.searchText)
- [x] Export dropdown menu перенесён в StatusBar
- [x] OpenLog() → переключает на Log tab
- [x] UpdateSummary() — groups/occurrences count + tab badge
- [ ] Тест в игре

## ЭТАП 2: GroupGrid.lua — фильтр cleanup — DONE ✅
- [x] Search box УДАЛЁН из GroupGrid (теперь в MainFrame toolbar)
- [x] FILTER_H 74 → 30 (одна компактная строка dropdown-ов)
- [x] Kind dropdown + Addon dropdown + Ignored checkbox в одну строку
- [x] Session dropdown скрыт (доступен программно)
- [x] Удалены: searchBox, searchLabel, onlyErrorCheck, onlyTaintCheck
- [x] Header background bar через Skin.C.titleBg
- [x] Header text через Skin.C.textBright
- [x] Row zebra stripes: even → Skin.C.rowAlt, odd → Skin.C.bg (transparent)
- [x] Selection overlay: Skin.C.rowSelected
- [ ] Тест в игре

## ЭТАП 3: DetailView.lua — визуальная чистка — DONE ✅
- [x] Tab кнопки → Skin:TabButton (no CharacterFrameTabButtonTemplate)
- [x] Action кнопки (Copy ▾ / Actions ▾ / Export View) → Skin:StyledButton
- [x] Occur nav buttons (< / >) → Skin:StyledButton
- [x] Occur search → Skin:SearchBox (with placeholder/clear)
- [x] Content area → BackdropTemplate + Skin:DarkInset + Skin.C.inputBg override
- [x] EditBox text → Skin.C.text color
- [x] Header sig/meta text → Skin.C.text / Skin.C.textDim
- [x] Occur index label → Skin.C.textDim
- [x] Removed: PanelTemplates_SetTab/SetNumTabs dependency
- [x] Removed: UIPanelButtonTemplate dependency
- [x] Removed: CharacterFrameTabButtonTemplate dependency
- [x] Removed: old CreateButton helper (inline fallbacks only)
- [ ] Тест в игре

## ЭТАП 4: Monitor.lua — embed в MainFrame — DONE ✅
- [x] _BuildMonitorPanels(parent, stateKey) — выделенный builder (CPU/Mem/Alerts/Bus/splitter/search)
- [x] BuildMonitorContent(parent) — public API, создаёт embedded instance
- [x] InitMonitorFrame() — standalone окно теперь тоже через _BuildMonitorPanels + dark theme
- [x] RefreshMonitor() — обновляет все видимые instances (embedded + standalone)
- [x] StartMonitorEmbedTicker() / StopMonitorEmbedTicker() — тикер для embedded
- [x] MainFrame SetMode: lazy build + ticker start/stop
- [x] MainFrame Toggle: ticker stop при закрытии
- [x] Удалены: placeholder text, "Open Monitor Window" button, _monitorPlaceholder
- [x] Standalone окно: BackdropTemplate + DarkFrame + custom titleBar (не BasicFrameTemplateWithInset)
- [x] Standalone: /rdev monitor backward compat сохранён
- [x] Panel builders: Skin:DarkInset, Skin.C.textBright/textDim, Skin:SearchBox
- [ ] Тест в игре

## ЭТАП 5: ExportFrame.lua — тёмная тема — DONE ✅
- [x] BasicFrameTemplateWithInset → BackdropTemplate + Skin:DarkFrame
- [x] Custom titleBar (28px, dark bg, drag, title text)
- [x] Bottom bar: Select All / Copy / Close → Skin:StyledButton
- [x] Body: Skin:DarkInset + Skin.C.inputBg override
- [x] EditBox: Skin.C.text color
- [x] Close button: Skin:StyledButton("X")
- [x] Removed: UIPanelButtonTemplate, CreateButton helper, f.TitleText, f.CloseButton
- [x] DIALOG strata for export overlay
- [ ] Тест в игре

## ЭТАП 6: Финал — DONE ✅
- [x] .toc — порядок правильный: Skin → DetailView → GroupGrid → MainFrame → Monitor → ExportFrame (0 новых файлов)
- [x] Slash.lua — OK, все вызовы Toggle/ToggleMonitor/OpenExportAll/OpenLog совместимы
- [x] MinimapButton.lua — OK, Toggle/OpenExportAll/OpenLog совместимы
- [x] AddonCompartment.lua — OK, Toggle совместим
- [x] MainFrame closeBtn: UIPanelCloseButton → Skin:StyledButton("X")
- [x] 0 оставшихся: BasicFrameTemplateWithInset, UIPanelButtonTemplate, CharacterFrameTab, PanelTemplates, InputBoxTemplate
- [ ] Persist state migration (можно после теста в игре)
- [ ] Version bump alpha.20 (после теста)
