# Changelog

## 1.0.0-alpha.20.0 — 2026-11-06

### Compatibility

- Target Retail 12.1.5, Interface 120105.
- Register `rothdevlib` links through the current `LinkUtil` dispatcher, with a bounded legacy fallback.
- Load Blizzard menu support through `C_AddOns.LoadAddOn`.

### Correctness and safety

- Normalize external values before comparison, formatting, iteration, persistence or callback delivery.
- Deep-copy and bound diagnostic payloads; inaccessible values are represented explicitly.
- Bound JSON traversal, strings, arrays, object entries and total output.
- Add a total node budget and raw traversal for diagnostic table copies, preventing exponential graphs and hostile `__pairs`/`__index` execution.
- Preserve newest breadcrumbs when a ring is resized.
- Retire the invasive global error-handler lock and force compatibility-first chain mode.
- Install the error handler once; stop automatic reclaim/watchdog fights after another addon becomes owner. Explicit `/rdev reclaim` remains available.
- Do not call secure-only `AddLuaErrorHandler` or hook private ScriptErrorsFrame internals. Fallback is bounded BugGrabber import or an explicit unavailable state.
- Baseline existing BugGrabber counters by default and use content-stable keys, preventing historical replay and list-reorder duplicates.
- Rebuild ChatTap and BugGrabber import as bounded, secret-safe external intake paths.
- Stop replacing Blizzard frame methods, mutating `StaticPopupDialogs`, or unregistering Blizzard-owned events.
- Give callbacks deterministic mutation semantics and an independent detached payload per consumer.
- Preserve arbitrary function return tuples through safe wrappers, profiling wrappers, Doctor scopes and internal calls.
- Add token-aware Doctor cleanup, including a one-frame cleanup fallback for hard errors handled by another owner.

### UI

- Fix manual minimap dragging with `math.atan2` and effective-scale coordinates.
- Recover a missing LibDBIcon button correctly.
- Use owner-aware tooltip cleanup for the addon-compartment entry.

### Validation

- Strengthened 6 existing regression tests and added 6 focused second-pass tests for the compact capture engine, ownership policy, callback isolation/mutation, Doctor cleanup, internal calls, profiling return tuples, BugGrabber baselining and traversal budgets. The suite now contains 28 test files.
- All modified production Lua files pass `texluac -p`.
- In-game matrix: not run in this environment.
