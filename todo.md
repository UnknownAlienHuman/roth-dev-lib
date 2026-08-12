# !RothDevLib — TODO (canonical)

> Version line in .toc: **1.0.0-alpha.19.0**
> 
> This file is the single source of truth for work-in-progress. Older, detailed audit notes moved to:
> `docs/TODO_LEGACY_alpha19.md`.
> 
> Additional legacy UI rewrite notes moved to: `docs/legacy_ui_rewrite/`.

## Problem statement

Current UI is not usable for triage:
- Group list can render empty even when DB contains groups (repro shown in screenshot).
- Mixed styling: Blizzard UIDropDownMenu + custom dark widgets.
- Unicode UI glyphs (e.g. `▾`) render as tofu squares on some clients.
- Splitters can be hard to see / interact with.

## Principles / constraints

1. **Safe in combat**: no protected action mutation, no secure template overrides.
2. **Modular**: Capture/DB/Export/Perf/Doctor/UI remain separate; UI is consumer-only.
3. **Performance**: no per-frame allocations; throttle UI refresh; avoid string-heavy work in hot paths.
4. **Diagnostics first**: keep log + `/rdev diag` useful; any UI failure must degrade gracefully.

## Roadmap

### Stage 1 — Critical UI hotfixes (make current UI usable)
**Goal:** unblock day-to-day use without a full rewrite.

- [x] Fix init order: apply list/detail layout **before** GroupGrid/DetailView init.
- [x] Remove Unicode glyphs from buttons (`Copy ▾`, `Actions ▾`, `Export ▾`).
- [x] Make splitter interaction obvious (highlight, tooltip, larger hit rect, clamp feedback).
- [x] Add a one-shot UI self-check (`/rdev uicheck`) that reports:
  - listFrame size, scroll frame size, numRows, groups count, last UpdateGroupGrid error.

  (implemented as `/rdev uicheck` in `UI/Slash.lua`.)

**DoD:** opening the window with existing errors always shows rows + auto-selects the first group.

### Stage 2 — UI stabilization (minimal surgery)
**Goal:** eliminate remaining visual/UX glitches while keeping the current architecture.

- [x] Fix dropdown visuals on dark background (skin UIDropDownMenuTemplate).
- [x] Resolve DetailView overlaps: consistent spacing, enforce minimum widths, hide-only when needed.
- [x] Ensure all panes persist reliably (main/monitor/export) on OnHide and drag/resize.

**DoD:** no overlapping widgets; all interactive controls are readable.

### Stage 3 — UI rewrite to Blizzard templates (recommended)
**Goal:** stop fighting custom styling and align with Blizzard’s modern UI stack.

- [x] MainFrame: migrate to `ButtonFrameTemplate` (+ `PanelDragBarTemplate`, `PanelResizeButtonTemplate`, `SearchBoxTemplate`).
- [x] Group list: add a `WowScrollBoxList` backend + `CreateDataProvider` (toggle via `settings.uiUseScrollBoxList`).
- [x] Group list: finish the full rewrite (ScrollBox-only, remove FauxScroll codepath, add resizable columns).
- [x] Filters: replace `UIDropDownMenuTemplate` with `WowStyle*DropdownTemplate` (or equivalent used by Blizzard tools).

**DoD:** list rendering is deterministic; no layout sensitivity to init order.

### Stage 4 — Monitor UX upgrade
- [x] Replace text-dump panels with stable tables (TopN + sort) and small graphs where cheap.
- [x] Add a live Bus Inspector that is useful at a glance (addon filter + recent breadcrumbs).

**DoD:** monitor answers "what is spiking" within 5–10 seconds.

### Stage 5 — Export/Share hardening
- [x] Ensure all exports are bounded (size budgets) and deterministic.
- [x] Add a "GitHub issue" exporter that includes environment + reproduction checklist.

**DoD:** one-click issue text usable without manual edits.

### Stage 6 — Validation + release gate

- [x] Add QA tooling: `/rdev gate`, `/rdev passlog`, `/rdev stress`, `/rdev reloadloop`.
- [ ] Execute in-game test matrix: RDL-only / RDL+BugGrabber, combat, stress flood, reload loops.
- [ ] Confirm taint sanity on target build: `self taint blocked/forbidden == 0` during matrix.

**DoD:** ship-ready alpha (matrix executed and `gate` remains PASS).

## Changelog (this repo)

### 2026-02-21 — Stage 1 partial
- MainFrame: apply layout before initializing GroupGrid/DetailView.
- UI: removed Unicode glyphs from Export/Copy/Actions button labels.
- GroupGrid: force row framelevel above list inset.
- Slash: added `/rdev uicheck` (prints UI/grid sizing + last grid update error).

### 2026-02-21 — Stage 1 done + Stage 2 started
- MainFrame: splitter now has larger hit area, hover highlight, clamp feedback, and tooltip.
- MainFrame: window position saved on drag end (mouse up) as well as on close.
- Skin: added `Skin:SkinUIDropDown()` and applied to Kind/AddOn/Session dropdown controls.


### 2026-02-21 — Stage 2 UI stabilization
- DetailView: tabs area now clips; action buttons never overlap tabs.
- DetailView: Occur filter controls moved into content inset (no overlap with tabs).
- GroupGrid: ApplyGroupGridLayout now reflows headers/scroll/rows on resize and splitter moves.

### 2026-02-21 — Stage 1 DoD fix + TODO hygiene
- GroupGrid: auto-select first visible group when selection is empty/filtered; reset scroll to top.
- Repo: moved legacy UI rewrite planning docs into `docs/legacy_ui_rewrite/`.

### 2026-02-21 — Stage 3 started (ScrollBox backend)
- UI: added `UI/Templates.xml` with `RothDevLibGroupRowTemplate` for ScrollBox rows.
- GroupGrid: optional ScrollBox-based backend (`WowScrollBoxList` + `CreateDataProvider`) gated by `settings.uiUseScrollBoxList`.
- Slash: `/rdev uicheck` now prints `grid.mode` and ScrollBox widget sizes when active.

### 2026-02-21 — Stage 3.1 shell migration
- MainFrame: prefers `ButtonFrameTemplate` when available (auto-fallback), hides default art, uses `PanelDragBarTemplate` + `PanelResizeButtonTemplate` when present.
- MainFrame: Search uses `SearchBoxTemplate` when available (fallback to dark custom SearchBox).

### 2026-02-21 — Stage 3.2 group list completion
- GroupGrid: ScrollBox-only implementation (removed FauxScroll codepath).
- GroupGrid: column widths persisted in settings (`uiGroupGridCols`) + header resize grips.
- Slash: `/rdev uicheck` updated to report ScrollBox rows shown.

### 2026-02-21 — Stage 3.3 filter dropdown migration
- GroupGrid: migrated Kind/AddOn/Session filters to Blizzard_Menu `DropdownButton` using `WowStyle1FilterDropdownTemplate`.
- GroupGrid: addon filter menu auto-buckets into letter submenus for large addon lists.
- UI: added `UI/Menu.lua` wrapper and updated .toc.

### 2026-02-21 — Stage 4 Monitor tables
- Monitor: replaced multiline text panels with ScrollBox tables (CPU/Mem/Alerts/Bus) with sortable headers.
- Monitor: added per-row bar visualization for Top CPU/Top Mem (EMA) to spot spikes at a glance.
- Monitor: migrated Bus addon filter dropdown to Blizzard_Menu (fallback to UIDropDownMenu).
- UI: added `UI/Table.lua` helper and `RothDevLibMonitorRowTemplate`.

### 2026-02-21 — Stage 5 Export hardening
- Report: bounded text exports (All/View/Selected/Filtered) with deterministic sorting and per-field budgets (message/stack/locals/breadcrumbs/metrics/log).
- Export: GitHub issue template exporter already present (`RDL.Export:BuildGitHubIssueText`) and wired to UI.

### 2026-02-21 — Stage 6 tooling (release gate)
- Validation: added Release Gate (`/rdev gate`) with PASS/FAIL checks and a persisted pass log (`/rdev passlog`).
- Validation: added stress harness (`/rdev stress`) and persisted reload-loop runner (`/rdev reloadloop`).

### 2026-02-21 — Bugfixes after Stage 3–6 integration
- UI: create `MinimalScrollBarTemplate` as a **Slider** (fixes FrameXML parse error: "Unknown script element OnValueChanged").
- GroupGrid: fixed DB iterators that return `(iter, state, var)` (was capturing only `iter`, causing `bad argument #1 to '(for generator)'`).

### 2026-02-21 — Hotfix: ScrollBoxList resolution + Export visibility
- UI: ScrollBox list creation now resolves real ScrollBox/ScrollBar when `WowScrollBoxList` is a container (fixes empty lists/tables on some builds).
- Skin: restored window positions are reset to CENTER when saved coords are fully off-screen (fixes Export/Copy/Export View appearing to do nothing).
- Menu: default text setter hardened for DropdownButton variants (prevents stuck "Filter" label).
