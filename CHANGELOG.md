# Changelog

## 1.0.0-alpha.20.0 — 2026-11-06

### Compatibility

- Target Retail 12.1.5, Interface 120105.
- Declare `LoadSavedVariablesFirst` because file-load capture policy intentionally reads persisted settings.
- Register `rothdevlib` links through current `LinkUtil`, with a bounded legacy fallback.
- Load Blizzard menu support through `C_AddOns.LoadAddOn`.
- Preserve protected-call argument and return tuples through explicit packed closures instead of depending on runtime-specific `xpcall` vararg forwarding.

### Correctness and safety

- Normalize external values before comparison, formatting, iteration, persistence, logging, callback delivery or UI use.
- Traverse foreign diagnostic tables with raw `next`/`rawget`; never invoke `__pairs`, `__index` or `__len`.
- Bound diagnostic copies by depth, entries, nodes, strings and total bytes; bound JSON by arrays, scans and total output too.
- Preserve unique JSON object keys after the final key-byte cap and filter unterminated `|K` secret escapes instead of leaking their opaque tail.
- Keep `Core/Core.lua` limited to namespace/integrity ownership; final public wrappers have one owner in `Core/CallSafety.lua`.
- Retire the global error-handler lock and force compatibility-first one-time chain ownership.
- Observe later handler replacement without automatic reclaim/watchdog fights; explicit `/rdev reclaim` remains available.
- Do not call secure-only `AddLuaErrorHandler` or hook private ScriptErrorsFrame internals.
- Guard the pre-`Safety.lua` handler window inside the installed process handler so capture faults clear recursion state and prior-handler delivery occurs exactly once.
- Preserve successful `nil` scrub results so absent stack fallbacks reach `debugstack` instead of becoming `<unavailable>`.
- Treat only `stored`, `queued` and `ignored` as successful intake statuses.
- Preserve warning tuple arity, inaccessible restriction-state values and explicit report signatures.
- Recognize ChatTap stack continuations before generic headers and hard-cap its dedup map during unique bursts.
- Baseline existing BugGrabber counters once, use bounded per-record message/stack identities, import the first newly observed occurrence immediately and never replay a newly seen foreign counter as full history.
- Retain BugGrabber counters across incomplete scans, cap retained counter state to the configured scan window and stop the fallback immediately when ineligible.
- Bound Storm token buckets; dynamic integration kinds share one overflow bucket and cannot bypass throttling by rotating names.
- Bound locals calibration state; read foreign options through raw access and match addon paths literally instead of as Lua patterns.
- Bound Doctor scope depth, detach retained contexts, preserve newest scopes if callers leak tokens and carry exact opaque tokens through every public integration surface.
- Give callbacks deterministic mutation semantics, independent detached payloads and hard per-event/total registry ceilings.
- Bound Bus addon/metric identities and CPU/memory profiling/sample identities; profiling wrappers snapshot normalized identities/options instead of retaining mutable caller tables.
- Bound in-memory logging by per-field/per-line limits and a 2 MiB total retained-byte budget.
- Preserve newest breadcrumbs when a ring is resized.
- Remove invasive Blizzard frame-method replacement, popup mutation and foreign event unregistration.

### Persistence and lifecycle

- Separate early SavedVariables availability from player-session readiness; construct sessions only at `PLAYER_LOGIN`.
- Treat DB/session startup as the root initialization gate; failed DB init never starts consumers or leaves a false initialized state.
- Queue file-load errors without a session and bind them to the first real session when committed.
- Normalize persisted settings/groups/session indexes once per DB root and pre-trim malformed/excess data before the legacy DB owner scans it.
- Migrate to schema 5 with compact occurrence summaries instead of duplicating full locals/context payloads per occurrence.
- Bound persisted group messages, stacks, locals, total groups and sessions; pinning affects eviction priority, not the cap.
- Bound persisted signature/addon ignore maps with a bounded startup scan and timestamp-based oldest-rule eviction.
- Handle `SAVED_VARIABLES_TOO_LARGE` through one emergency-compaction path: keep a small newest/pinned set, strip heavy context, shrink ignore maps and suspend writes for the session without retry loops.
- Use one idempotent `ADDONS_UNLOADING` / `PLAYER_LOGOUT` teardown, including pending ChatTap invalidation and watcher/ticker shutdown.
- Keep `Core/Events.lua` as the single late-Blizzard-readiness owner.

### UI

- Fix manual minimap dragging with `math.atan2` and effective-scale coordinates.
- Recover a missing LibDBIcon button correctly.
- Use owner-aware addon-compartment tooltip cleanup.
- Mark the embedded monitor as built only after panel construction succeeds, allowing a failed first attempt to retry cleanly.
- Load menus through current APIs while retaining explicit fallback behavior.

### Validation

- Add GitHub Actions CI for the complete `tests/test_*.lua` suite and first-party `texluac -p` syntax gate.
- Add regression matrices for manifest/load order, lifecycle failure/retry/teardown, bootstrap handler recovery and store-status semantics.
- Add hostile-input and saturation tests for bounded copy/JSON, persistence, ignore maps, Logger, Bus, CPU/memory, callbacks, Doctor, Locals, ChatTap, BugGrabber and Storm.
- Add second-pass regressions for final JSON-key collisions, malformed secret escapes, same-message BugGrabber records, exact Doctor-token forwarding, pre-Safety handler containment and immutable profiler-wrapper options.
- Add argument/return-tuple tests with interior and trailing nils for safe/internal/profiling paths.
- Complete offline regression suite: pass.
- All first-party production Lua files pass `texluac -p`.
- In-game matrix: not run in this environment; remaining client gates are explicit in `todo.md`.
