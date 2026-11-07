# Changelog

## 1.0.0-alpha.20.0 — 2026-11-06

### Compatibility

- Target Retail 12.1.5, Interface 120105.
- Declare `LoadSavedVariablesFirst` because capture policy and handler installation intentionally read persisted settings during file loading.
- Register `rothdevlib` links through the current `LinkUtil` dispatcher, with a bounded legacy fallback.
- Load Blizzard menu support through `C_AddOns.LoadAddOn`.

### Correctness and safety

- Normalize external values before comparison, formatting, iteration, persistence or callback delivery.
- Deep-copy and bound diagnostic payloads; inaccessible values are represented explicitly.
- Traverse foreign diagnostic tables with raw `next`/`rawget`; never invoke `__pairs`, `__index` or `__len`.
- Bound JSON traversal by depth, table entries, scan entries, total nodes, strings, arrays and total output.
- Add total-node and total-byte table-copy budgets, preventing broad diagnostic graphs from bypassing per-string limits.
- Keep `Core/Core.lua` limited to namespace/integrity ownership; the final public wrappers have one owner in `Core/CallSafety.lua`.
- Preserve newest breadcrumbs when a ring is resized.
- Retire the invasive global error-handler lock and force compatibility-first chain mode.
- Install the error handler once; stop automatic reclaim/watchdog fights after another addon becomes owner. Explicit `/rdev reclaim` remains available.
- Do not call secure-only `AddLuaErrorHandler` or hook private ScriptErrorsFrame internals. Fallback is bounded BugGrabber import or an explicit unavailable state.
- Baseline existing BugGrabber counters by default and use content-stable keys, preventing historical replay and list-reorder duplicates.
- Import the first occurrence of a new BugGrabber error immediately after the one-time attach baseline instead of silently waiting for its counter to reach two.
- Keep BugGrabber counter state when a bounded raw-key scan is incomplete; stale-key pruning now requires proof of a complete scan.
- Scan BugGrabber records without the foreign length operator, so hostile `__len` code cannot run.
- Rebuild ChatTap and BugGrabber import as bounded, secret-safe external intake paths.
- Enforce the configured ChatTap dedup limit during bursts of recent unique errors, not only after entries become stale.
- Stop replacing Blizzard frame methods, mutating `StaticPopupDialogs`, or unregistering Blizzard-owned events.
- Give callbacks deterministic mutation semantics and an independent detached payload per consumer.
- Preserve arbitrary function return tuples through safe wrappers, profiling wrappers, Doctor scopes and internal calls.
- Add token-aware Doctor cleanup, including a one-frame cleanup fallback for hard errors handled by another owner.
- Guard the pre-`Safety.lua` handler window so capture faults clear recursion state and retain prior-handler delivery.
- Preserve a successful `nil` scrub result instead of converting it to `<unavailable>`; stack capture now reaches `debugstack` when no fallback was supplied.
- Treat only `stored`, `queued` and `ignored` as successful intake statuses; throttled/failed writes are not reported as captured.
- Tear down the BugGrabber fallback immediately when ownership or settings make it ineligible.
- Preserve inaccessible restriction-state values instead of coercing them to `false`.
- Reject inaccessible external signature overrides rather than using them as grouping keys.
- Preserve warning tuple arity and recognize ChatTap stack continuations before generic headers.
- Separate early SavedVariables access from player-session readiness; construct sessions only at `PLAYER_LOGIN`.
- Treat DB/session startup as the root initialization gate: failed DB initialization no longer starts consumers or leaves a false `_initialized` state.
- Use one idempotent final teardown for `ADDONS_UNLOADING` and `PLAYER_LOGOUT`, including pending ChatTap invalidation.
- Queue file-load errors without a session and bind them to the first real session when committed.
- Normalize persisted settings/groups/session indexes once per DB root and trim stale/excess persisted data before normal use.
- Persist compact occurrence summaries instead of duplicating full locals/context payloads for every occurrence.
- Bound persisted group messages, stacks and locals and migrate existing occurrence history to schema 5.
- Handle `SAVED_VARIABLES_TOO_LARGE` as one emergency-compaction path: keep the newest/pinned groups, strip heavy context, pause writes for the current session and require explicit clear/reload recovery.
- Enforce the global group cap even when groups are pinned; pinning changes eviction priority, not the memory/persistence bound.
- Pre-normalize persisted sessions/groups before the legacy DB owner scans them, bounding login work as well as steady-state storage.
- Remove the duplicate suppression `ADDON_LOADED` watcher; `Core/Events.lua` is the single late-Blizzard-readiness owner.

### UI

- Fix manual minimap dragging with `math.atan2` and effective-scale coordinates.
- Recover a missing LibDBIcon button correctly.
- Use owner-aware tooltip cleanup for the addon-compartment entry.

### Validation

- Add manifest/load-order coverage for `LoadSavedVariablesFirst` and capture ordering.
- Add regression coverage for raw JSON traversal, hostile metamethods, JSON node/byte budgets and raw BugGrabber list scanning.
- Add focused regression coverage for bootstrap handler recovery, fallback teardown, store statuses, warning arity, restriction-state markers, report signatures and ChatTap continuation/timer behavior.
- Add regressions for first-occurrence BugGrabber import, incomplete-scan retention, ChatTap dedup hard bounds, failed-root initialization and idempotent unload/logout teardown.
- Add persistence regressions for compact occurrence migration, bounded root payloads, oversized-SavedVariables recovery, write suspension and explicit resume.
- Run the complete repository regression suite and first-party `texluac -p` syntax gate on every branch/PR through GitHub Actions.
- Complete repository regression suite: pass.
- All first-party production Lua files pass `texluac -p`.
- In-game matrix: not run in this environment.
