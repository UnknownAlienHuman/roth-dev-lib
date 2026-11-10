# Architecture

!RothDevLib is one addon with explicit ownership layers:

```text
loader + persisted-root repair
  -> ordinary-value boundary
  -> diagnostics/capture services
  -> bounded registries + persistence
  -> export
  -> UI consumers
```

`!RothDevLib.toc` is authoritative. `LoadSavedVariablesFirst` exposes only the persisted root before the first Lua file. `Core/DBLifecycle.lua` blocks player/session construction until `PLAYER_LOGIN`; `Core/IgnoreBounds.lua` can normalize persisted ignore maps during file loading without crossing that gate. Errors captured earlier stay in a bounded boot queue and receive the real session ID only when committed after login.

`Core/Core.lua` creates the namespace and integrity fingerprints. `Core/CallSafety.lua` and `Core/Internal.lua` own guarded calls after Secret Value utilities are available. They preserve complete argument/return tuples through explicit packed closures and do not rely on runtime-specific `xpcall` vararg forwarding.

`Core/DB.lua` is the only SavedVariables store. `Core/DBLifecycle.lua` adds readiness, schema-5 migration, compact occurrence summaries, root payload limits, total group/session caps and one-shot `SAVED_VARIABLES_TOO_LARGE` recovery. Recovery keeps a small newest/pinned working set, strips heavy context and suspends writes for the current session instead of retrying. `Core/IgnoreBounds.lua` separately caps signature/addon ignore rules and applies smaller emergency limits during persistence recovery. Pinning or ignoring changes policy, never memory ownership.

All external diagnostic data crosses `Util/BoundedCopy.lua` or an equivalent narrow boundary before storage, logging, callbacks or UI. Raw traversal avoids foreign metamethods and enforces depth, entry, node, per-string and total-byte budgets. `Util/JSON.lua` adds array/scan/output limits. `Util/Logger.lua` enforces both per-line and total retained-byte budgets.

Long-lived runtime registries are explicitly capped:

- Bus addon and metric identities;
- CPU/memory profiling and sample identities;
- callback events, callbacks per event and callbacks in total;
- Doctor correlation depth and detached contexts;
- locals-calibration cache;
- ChatTap dedup state;
- BugGrabber counter/signature state;
- Storm token buckets, with dynamic kinds sharing one overflow bucket.

`Capture/Policy.lua` configures one-time chain ownership. `Capture/Engine.lua` installs and observes the global error handler without reclaim wars. `Capture/Safety.lua` normalizes hard/suppressed/integration intake. If ownership is lost, `Capture/BugGrabber.lua` provides bounded counter-delta import; otherwise fallback is explicitly unavailable. `Core/Events.lua` owns lifecycle dispatch, including one idempotent `ADDONS_UNLOADING`/`PLAYER_LOGOUT` teardown.

UI modules read service state and expose commands, filters and exports. They do not own capture, persistence or security policy.

The complete offline regression suite and first-party Lua syntax gate run in GitHub Actions. Runtime-only claims remain unverified until the named-client matrix in [todo.md](todo.md) is executed.
