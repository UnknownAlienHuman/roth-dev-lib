# !RothDevLib — руководство

Версия **1.0.0-alpha.20.0**. Цель: WoW Retail **12.1.5**, Interface **120105**.

RothDevLib собирает в одном месте:

- hard Lua errors;
- `LUA_WARNING`;
- `ADDON_ACTION_BLOCKED/FORBIDDEN`, macro/restriction events;
- ошибки, явно переданные через `Report*` или safe wrappers;
- Doctor context, breadcrumbs, CPU/memory observations;
- ограниченные JSON/LLM/GitHub-issue exports.

## Установка и открытие

Скопируй `!RothDevLib` в `_retail_/Interface/AddOns/` и сделай `/reload`.

Открытие: `/rdev`, Addon Compartment или minimap-кнопка.

## Как устроены данные

Повторяющиеся события объединяются по сигнатуре. Счётчик показывает активные **группы**, а не суммарное число occurrences.

Внешние значения проходят строгую границу до сохранения:

- secret/inaccessible values превращаются в явные маркеры;
- таблицы копируются, а не сохраняются по ссылке;
- глубина, число элементов, строки, ring buffers и exports ограничены.

## Основные команды

- `/rdev` — открыть/закрыть UI;
- `/rdev status` — состояние error-handler ownership;
- `/rdev clear` — очистить базу;
- `/rdev monitor` — CPU/memory/alerts;
- `/rdev export json|pack|share|github` — экспорт;
- `/rdev bus [AddonName]` — breadcrumbs;
- `/rdev test <kind>` — диагностические тестовые события;
- `/rdev gate` — release gate;
- `/rdev stress` — flood/stress проверка;
- `/rdev reloadloop` — reload-loop проверка.

## Error handler и Blizzard UI

Обычные режимы chain/exclusive сохраняются. Устаревший `lockErrorHandler`, который заменял глобальный `seterrorhandler`, отключён как небезопасный.

Подавление Blizzard error/taint presentation не меняет методы фреймов, не переписывает `StaticPopupDialogs` и не снимает события с чужих фреймов. Используются settings-aware post-hooks и `Hide`.

## Ключевые настройки

`RothDevLibDB.settings`:

- `maxGroups`, `maxOccurrencesPerGroup`;
- `hideBlizzardScriptErrors`, `hideTaintPopups`;
- `captureChatErrors`;
- `captureLocals`, `maxLocalsSize`, `localsProbeMax`;
- `enablePerfProfiling`, `cpuSampleRate`, `cpuSpikeMs`, `memSpikeKB`;
- `memWatchEnabled`, `memWatchIntervalSec`;
- `uiRefreshThrottleSec`.

## Ограничения

Аддон не может восстановить ошибку, которую другой код полностью проглотил и никак не сообщил. Для таких путей интегрируй `LibStub("RothDevLib-1.0")` и вызывай `dev:Error`, `dev:Report`, `dev:Breadcrumb`.

Offline-тесты не доказывают отсутствие taint/combat проблем. Перед релизом обязателен in-game matrix из [`todo.md`](../todo.md).
