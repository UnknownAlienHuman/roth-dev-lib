# RothDevLib UI Rewrite — Lightweight Plan (v2)
## Красивый UI на Blizzard-фреймах, без overengineering

> Создано: 2026-02-20
> Принцип: минимум новых файлов, максимум визуального эффекта
> Референс: DevForge — берём СТИЛЬ (тёмная тема, чистый layout), но НЕ архитектуру (модули/ActivityBar)

---

## ПОЧЕМУ НЕ DevForge-SHELL

DevForge = IDE с 12 модулями. RothDevLib = error tracker.
Основной сценарий: открыл → посмотрел ошибки → скопировал → закрыл.

- ActivityBar с 4 иконками — overkill, можно обычные tab-кнопки
- ModuleSystem — лишний слой абстракции для 3 экранов
- 10+ новых файлов — сложнее дебажить когда UI сам падает
- BottomPanel с REPL — не нужен error tracker-у

Вместо этого: **одно красивое окно** с простым переключением режимов.

---

## ЦЕЛЕВОЙ LAYOUT

```
┌────────────────────────────────────────────────────────────┐
│  RothDevLib 1.0.0-alpha.19    ErrorHandler: owned   [X]   │
├────────────────────────────────────────────────────────────┤
│  [Errors ▪12] [Monitor] [Log]  │  Search: [________]      │
├──────────────────────┬─────────┴───────────────────────────┤
│                      │                                     │
│   Error List         │   Detail View                       │
│   (GroupGrid)        │   [Message][Stack][Locals][Doctor]  │
│                      │                                     │
│   ▪ LUA_ERROR x3    │   Interface/AddOns/Foo/Bar.lua:42   │
│     Foo              │   attempt to index nil value        │
│   ▪ TAINT x1        │   ...                               │
│     Bar              │                                     │
│                      │   [Copy ▾] [Actions ▾] [Export ▾]   │
├──────────────────────┴─────────────────────────────────────┤
│  Filters: [All kinds ▾] [All addons ▾] [All sessions ▾]   │
│  ☐ Show ignored    Total: 12 groups, 47 occurrences       │
│                                                [Clear All] │
└────────────────────────────────────────────────────────────┘
```

**3 режима** переключаются tab-кнопками вверху:
- **Errors** (default) — GroupGrid + DetailView split, фильтры внизу
- **Monitor** — CPU/Mem/Alerts/Bus panels (текущий Monitor.lua контент)  
- **Log** — Logger tail (текущий OpenLog контент, но inline)

---

## ПЛАН ПО ЭТАПАМ

### ЭТАП 0: Theme (палитра + layout constants)
**Файл:** `UI/Skin.lua` (расширение, НЕ новый файл)
**Трудоёмкость:** маленькая

Добавляем в существующий Skin.lua:

```lua
-- Тёмная тема (DevForge-inspired)
Skin.C = {
    bg         = { 0.09, 0.09, 0.11, 0.97 },   -- основной фон
    bgAlt      = { 0.06, 0.06, 0.08, 0.95 },   -- вставки (inset panels)  
    titleBg    = { 0.13, 0.13, 0.15, 1.00 },   -- заголовок
    border     = { 0.28, 0.28, 0.30, 0.80 },   -- рамки
    tabActive  = { 0.20, 0.20, 0.23, 1.00 },   -- активный таб
    tabInactive= { 0.12, 0.12, 0.14, 1.00 },   -- неактивный таб  
    tabHover   = { 0.16, 0.16, 0.19, 1.00 },   -- hover
    splitter   = { 0.22, 0.22, 0.25, 1.00 },   -- разделитель
    accent     = { 0.35, 0.55, 0.85, 1.00 },   -- акцент (selection)
    danger     = { 0.90, 0.25, 0.25, 1.00 },   -- ошибки
    warning    = { 1.00, 0.76, 0.20, 1.00 },   -- предупреждения
    ok         = { 0.40, 0.85, 0.40, 1.00 },   -- ok статус
    text       = { 0.83, 0.83, 0.83, 1.00 },   -- обычный текст
    textDim    = { 0.55, 0.55, 0.55, 1.00 },   -- dim текст
    textBright = { 0.95, 0.95, 0.95, 1.00 },   -- яркий текст
    rowAlt     = { 0.11, 0.11, 0.13, 1.00 },   -- чередование строк
    rowSelected= { 0.18, 0.30, 0.50, 0.60 },   -- выбранная строка
    statusBar  = { 0.10, 0.10, 0.12, 1.00 },   -- статусбар
    btnNormal  = { 0.16, 0.16, 0.18, 1.00 },   -- кнопка нормальная
    btnHover   = { 0.22, 0.22, 0.25, 1.00 },   -- кнопка hover
    btnPress   = { 0.10, 0.10, 0.12, 1.00 },   -- кнопка нажатие
    inputBg    = { 0.06, 0.06, 0.08, 1.00 },   -- input background
    badge      = { 0.80, 0.25, 0.25, 1.00 },   -- badge background
    badgeText  = { 1.00, 1.00, 1.00, 1.00 },   -- badge text
}

-- Backdrops
Skin.BD = {
    dialog = {
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    },
    flat = {
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
    },
}

-- Helper: apply dark panel
function Skin:DarkFrame(frame, bdKey)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop(self.BD[bdKey or "dialog"])
    frame:SetBackdropColor(unpack(self.C.bg))
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(unpack(self.C.border))
    end
end

-- Helper: dark inset
function Skin:DarkInset(frame)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop(self.BD.dialog)
    frame:SetBackdropColor(unpack(self.C.bgAlt))
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(unpack(self.C.border))
    end
end

-- Helper: styled button (replaces UIPanelButtonTemplate)
function Skin:StyledButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)
    b:SetBackdrop(self.BD.flat)
    b:SetBackdropColor(unpack(self.C.btnNormal))
    
    local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", 0, 0)
    label:SetText(text)
    label:SetTextColor(unpack(self.C.text))
    b._label = label
    b.SetText = function(_, t) label:SetText(t) end
    b.GetText = function(_) return label:GetText() end
    
    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(unpack(Skin.C.btnHover))
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropColor(unpack(Skin.C.btnNormal))
    end)
    b:SetScript("OnMouseDown", function(self)
        self:SetBackdropColor(unpack(Skin.C.btnPress))
    end)
    b:SetScript("OnMouseUp", function(self)
        self:SetBackdropColor(unpack(Skin.C.btnHover))
    end)
    
    return b
end

-- Helper: tab button
function Skin:TabButton(parent, text, w, h)
    local b = self:StyledButton(parent, text, w, h)
    b:SetBackdropColor(unpack(self.C.tabInactive))
    b._isActiveTab = false
    
    function b:SetActive(active)
        b._isActiveTab = active
        if active then
            b:SetBackdropColor(unpack(Skin.C.tabActive))
            b._label:SetTextColor(unpack(Skin.C.textBright))
        else
            b:SetBackdropColor(unpack(Skin.C.tabInactive))
            b._label:SetTextColor(unpack(Skin.C.textDim))
        end
    end
    
    b:SetScript("OnEnter", function(self)
        if not self._isActiveTab then
            self:SetBackdropColor(unpack(Skin.C.tabHover))
        end
    end)
    b:SetScript("OnLeave", function(self)
        if not self._isActiveTab then
            self:SetBackdropColor(unpack(Skin.C.tabInactive))
        end
    end)
    
    return b
end
```

Что даёт: единая палитра + 3 helper-функции. Все фреймы ниже используют `Skin:DarkFrame()` вместо BasicFrameTemplate.

---

### ЭТАП 1: MainFrame.lua — замена shell (ядро всей переделки)
**Файл:** `UI/MainFrame.lua` (переписка)
**Трудоёмкость:** средняя

Ключевые изменения:

#### 1.1 Заменить BasicFrameTemplateWithInset на BackdropTemplate
```lua
-- БЫЛО:
local f = CreateFrame("Frame", "RothDevLibMainFrame", UIParent, 
    "BasicFrameTemplateWithInset")

-- СТАЛО:
local f = CreateFrame("Frame", "RothDevLibMainFrame", UIParent, 
    "BackdropTemplate")
f:SetFrameStrata("HIGH")
f:SetClampedToScreen(true)
f:SetToplevel(true)
Skin:DarkFrame(f)
```

#### 1.2 Кастомный TitleBar (вместо стандартного заголовка)
```lua
-- Тёмная полоса с drag support
local titleBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
titleBar:SetHeight(28)
titleBar:SetPoint("TOPLEFT", 0, 0)
titleBar:SetPoint("TOPRIGHT", 0, 0)
titleBar:SetBackdrop(Skin.BD.flat)
titleBar:SetBackdropColor(unpack(Skin.C.titleBg))

titleBar:EnableMouse(true)
titleBar:SetScript("OnMouseDown", function(_, btn)
    if btn == "LeftButton" then f:StartMoving() end
end)
titleBar:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
end)

-- Title + version
local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("LEFT", 10, 0)
title:SetText("RothDevLib " .. (RDL.version or ""))
title:SetTextColor(0.6, 0.75, 1, 1)

-- Status (ErrorHandler: owned ...)
local status = titleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
status:SetPoint("LEFT", title, "RIGHT", 12, 0)

-- Close button (простой X)
local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -2, -2)
closeBtn:SetScript("OnClick", function() UI:Toggle() end)
```

#### 1.3 Mode tabs (вместо ActivityBar) — одна строка кнопок
```lua
-- Toolbar row: mode tabs + search
local toolbar = CreateFrame("Frame", nil, f, "BackdropTemplate")
toolbar:SetHeight(26)
toolbar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -1)
toolbar:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -1)
toolbar:SetBackdrop(Skin.BD.flat)
toolbar:SetBackdropColor(unpack(Skin.C.statusBar))

-- Mode tabs
local tabErrors  = Skin:TabButton(toolbar, "Errors", 80, 24)
local tabMonitor = Skin:TabButton(toolbar, "Monitor", 80, 24)
local tabLog     = Skin:TabButton(toolbar, "Log", 60, 24)

tabErrors:SetPoint("LEFT", toolbar, "LEFT", 4, 0)
tabMonitor:SetPoint("LEFT", tabErrors, "RIGHT", 2, 0)
tabLog:SetPoint("LEFT", tabMonitor, "RIGHT", 2, 0)

-- Badge на Errors tab
local errorBadge = tabErrors:CreateFontString(nil, "OVERLAY")
errorBadge:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
errorBadge:SetPoint("LEFT", tabErrors._label, "RIGHT", 4, 0)
errorBadge:SetTextColor(1, 0.3, 0.3, 1)

-- Search box (правая часть toolbar)
local search = CreateFrame("EditBox", nil, toolbar, "SearchBoxTemplate")
search:SetSize(180, 20)
search:SetPoint("RIGHT", toolbar, "RIGHT", -8, 0)
```

#### 1.4 Content area — 3 режима, один видимый
```lua
-- Content zone (под toolbar, над statusbar)
local contentErrors  = CreateFrame("Frame", nil, f)  -- GroupGrid + Detail split
local contentMonitor = CreateFrame("Frame", nil, f)  -- Monitor panels
local contentLog     = CreateFrame("Frame", nil, f)  -- Log viewer

-- Все три anchored одинаково:
for _, c in ipairs({contentErrors, contentMonitor, contentLog}) do
    c:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -1)
    c:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 32)  -- 32 = statusbar height
    c:Hide()
end

local activeMode = "errors"

local function SetMode(mode)
    activeMode = mode
    contentErrors:SetShown(mode == "errors")
    contentMonitor:SetShown(mode == "monitor")
    contentLog:SetShown(mode == "log")
    tabErrors:SetActive(mode == "errors")
    tabMonitor:SetActive(mode == "monitor")
    tabLog:SetActive(mode == "log")
end

tabErrors:SetScript("OnClick", function() SetMode("errors") end)
tabMonitor:SetScript("OnClick", function() SetMode("monitor") end)
tabLog:SetScript("OnClick", function() SetMode("log") end)
```

#### 1.5 Status bar внизу
```lua
-- Status bar (внизу окна)
local statusBar = CreateFrame("Frame", nil, f, "BackdropTemplate")
statusBar:SetHeight(30)
statusBar:SetPoint("BOTTOMLEFT", 0, 0)
statusBar:SetPoint("BOTTOMRIGHT", 0, 0)
statusBar:SetBackdrop(Skin.BD.flat)
statusBar:SetBackdropColor(unpack(Skin.C.statusBar))

-- Filters (левая часть statusbar)
-- Kind dropdown, Addon dropdown, Session dropdown, ☐ Ignored
-- ... компактно в одну строку ...

-- Справа: [Clear All] + summary text "12 groups, 47 occurrences"
local btnClear = Skin:StyledButton(statusBar, "Clear All", 80, 22)
btnClear:SetPoint("RIGHT", statusBar, "RIGHT", -8, 0)

local summary = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
summary:SetPoint("RIGHT", btnClear, "LEFT", -10, 0)
```

#### 1.6 Errors content — GroupGrid + Detail + Splitter
Переиспользуем существующий код, но:
- GroupGrid монтируется в левую часть contentErrors
- DetailView монтируется в правую часть contentErrors
- Splitter между ними (уже есть, сохраняем)
- Фильтры ПЕРЕЕЗЖАЮТ из GroupGrid в StatusBar
- Кнопки Export/Copy/Actions остаются в DetailView

#### 1.7 Monitor content — прямой embed
Текущий Monitor.lua рендерит в отдельное окно. Рефакторим:
- Monitor panels (CPU/Mem/Alerts/Bus) монтируются в contentMonitor
- Убираем отдельное окно

#### 1.8 Log content — простой ScrollFrame
```lua
-- Log viewer = scrollable EditBox с Logger:GetText()
-- + auto-refresh при открытом табе
-- Reuse паттерн из текущего OpenLog, но inline
```

---

### ЭТАП 2: GroupGrid.lua — убрать filter area
**Файл:** `UI/GroupGrid.lua` (правка)
**Трудоёмкость:** маленькая

- [ ] Удалить filter area из GroupGrid (FILTER_H → 0)
- [ ] Фильтры (kind/addon/session dropdowns, search, ignored checkbox) переезжают в StatusBar
- [ ] GroupGrid остаётся чистым списком с header + rows
- [ ] Визуал: row alternation через Skin.C.rowAlt, selected через Skin.C.rowSelected
- [ ] Header тёмный (Skin.C.titleBg)

---

### ЭТАП 3: DetailView.lua — визуальная чистка
**Файл:** `UI/DetailView.lua` (правка)
**Трудоёмкость:** маленькая

- [ ] Tab кнопки (Message/Stack/Locals/Doctor/Occur) → Skin:TabButton стиль
- [ ] Action кнопки (Copy/Actions/Export) → Skin:StyledButton стиль
- [ ] Occur навигация (prev/next) — компактнее
- [ ] EditBox area → тёмный фон (Skin.C.inputBg)

---

### ЭТАП 4: Monitor.lua — рефактор из standalone в embedded
**Файл:** `UI/Monitor.lua` (правка)
**Трудоёмкость:** средняя

- [ ] Убрать создание отдельного Frame("BasicFrameTemplateWithInset")
- [ ] Экспортировать функцию `UI:BuildMonitorContent(parent)` → создаёт panels внутри parent
- [ ] MainFrame вызывает `BuildMonitorContent(contentMonitor)`
- [ ] Сохранить весь внутренний логику (CPU/Mem/Alerts/Bus, тикер, TopN)

---

### ЭТАП 5: ExportFrame.lua — аналогичный рефактор
**Файл:** `UI/ExportFrame.lua` (правка)
**Трудоёмкость:** маленькая

- [ ] Заменить BasicFrameTemplateWithInset → BackdropTemplate + Skin:DarkFrame
- [ ] Тёмная тема для export окна
- [ ] Остаётся отдельным popup (это нормально — export = temporary overlay)

---

### ЭТАП 6: Финальная доводка
**Трудоёмкость:** маленькая

- [ ] Обновить .toc (без новых файлов, порядок не меняется)
- [ ] Обновить Slash.lua — `/rdev` открывает обновлённый MainFrame
- [ ] Проверить persist state совместимость (ключи mainShell и т.д.)
- [ ] Version bump

---

## ИТОГО: ЧТО МЕНЯЕТСЯ

| Файл | Изменение |
|------|-----------|
| `UI/Skin.lua` | +палитра +helpers (StyledButton, TabButton, DarkFrame) |
| `UI/MainFrame.lua` | Полная переписка shell (BackdropTemplate, TitleBar, Mode tabs, StatusBar) |
| `UI/GroupGrid.lua` | Убрать filter area, визуал через Skin |
| `UI/DetailView.lua` | Визуальная чистка кнопок/табов |
| `UI/Monitor.lua` | Рефактор из standalone → embedded content |
| `UI/ExportFrame.lua` | BackdropTemplate + тёмная тема |

**0 новых файлов.** Всё в существующих.

---

## СРАВНЕНИЕ С ТЯЖЁЛЫМ ПЛАНОМ

| | Тяжёлый (v1) | Лёгкий (v2) |
|--|--------------|-------------|
| Новые файлы | 10+ | 0 |
| Строк кода | ~3000+ | ~800-1000 |
| Время разработки | 3-5 дней | 1-2 дня |
| Визуальный результат | IDE-подобный | Чистый тёмный UI |
| Сложность поддержки | Высокая | Низкая |
| Риск поломки | Средний (много новых связей) | Низкий (те же файлы) |
| Расширяемость | Высокая (модульная система) | Средняя (add mode tab) |

---

## ПОРЯДОК ВЫПОЛНЕНИЯ

```
Этап 0 (Skin палитра) → Этап 1 (MainFrame shell) → Этап 2 (GroupGrid чистка)
    → Этап 3 (DetailView визуал) → Этап 4 (Monitor embed) → Этап 5 (Export тема)
    → Этап 6 (финал)
```

Можно делать инкрементально: после Этапа 0+1 уже будет видимый результат в игре.

---

## CHANGELOG

- 2026-02-20: v2 плана — лёгкий подход. Заменяет v1 (DevForge-shell). 0 новых файлов, правки в 6 существующих.
