# Agent guide: !RothDevLib

## Start here

The executable contract is [`!RothDevLib.toc`](!RothDevLib.toc). Read it before changing code. The declared order is intentional:

1. embedded libraries;
2. namespace, version, DB, lifecycle/persistence bounds and internal calls;
3. Secret Value guards, bounded copy/JSON and public call safety;
4. export, profiling, Doctor and integration;
5. capture policy/engine/intake modules;
6. UI and the final lifecycle dispatcher.

`## LoadSavedVariablesFirst: 1` is required. `Capture/Policy.lua` and `Core/IgnoreBounds.lua` may inspect/repair only the persisted root during file loading; `Core/DBLifecycle.lua` prevents player/session construction until `PLAYER_LOGIN`. Early captured entries remain in the bounded boot queue and receive a real session only when committed.

## Runtime ownership

- `Core/Core.lua`: namespace bootstrap and integrity fingerprints only.
- `Core/CallSafety.lua`: public wrappers and portable packed argument/return tuples.
- `Core/Internal.lua`: guarded internal calls and exact Doctor cleanup.
- `Core/DB.lua`: authoritative persistence/group/session implementation.
- `Core/DBLifecycle.lua`: PLAYER_LOGIN gate, schema repair, compact persistence and oversized-SavedVariables recovery.
- `Core/IgnoreBounds.lua`: persisted signature/addon ignore caps; no session construction.
- `Util/BoundedCopy.lua`: raw bounded snapshots with depth/entry/node/string/total-byte budgets.
- `Util/JSON.lua`: deterministic raw traversal with array/scan/output budgets.
- `Util/Logger.lua`: per-line and total-byte-bounded in-memory logging.
- `Doctor/Doctor.lua`: capped token-aware context stack with detached contexts.
- `Integration/Callbacks.lua`: deterministic snapshot dispatch with per-event/total caps.
- `Integration/Bus.lua`: bounded breadcrumb rings and capped addon/metric identities.
- `Perf/CPU.lua`, `Perf/Mem.lua`: capped profiling identities; telemetry never changes target semantics.
- `Capture/Policy.lua`: one-time compatibility policy before handler installation.
- `Capture/Engine.lua`: handler construction, ownership state, entry construction and storage routing.
- `Capture/Safety.lua`: bounded hard/suppressed/integration intake and fallback selection.
- `Capture/BugGrabber.lua`: the only supported hard-error fallback after handler ownership is lost; retained state is capped.
- `Capture/ChatTap.lua`, `Capture/Locals.lua`, `Capture/Storm.lua`: bounded heuristic intake, calibration and flood-control state.
- UI modules are consumers; they do not own capture or persistence policy.

## Non-negotiable invariants

### Global error handler

1. Chain-wrap the current handler once during `EarlyInit`.
2. Forward to the prior handler in chain mode.
3. Observe later replacement without automatically reclaiming or polling.
4. Allow one explicit `/rdev reclaim` attempt.
5. Never replace `_G.seterrorhandler`, call secure-only `AddLuaErrorHandler`, or hook/poll private ScriptErrorsFrame internals.

### Foreign data

Before comparison, formatting, indexing, iteration, logging, callback delivery, export or persistence:

- gate Secret Value and table access;
- copy into bounded ordinary values;
- traverse foreign tables with raw `next`/`rawget`, never `pairs`, `#`, `__index`, `__pairs` or `__len`;
- cap depth, entries, total nodes, individual strings and total bytes;
- represent inaccessible/cyclic/unsupported data with explicit markers;
- never retain foreign tables, frames, timers, callbacks or pooled objects in `RothDevLibDB`.

### Retained state

A count limit is not a memory limit unless identities and payload bytes are bounded too. Every long-lived registry must have an explicit ceiling and saturation behavior. Current owners include DB groups/sessions/ignore rules, Bus identities, profiling identities, callback registrations, Doctor scopes, Locals calibration, ChatTap dedup, BugGrabber counters, Storm buckets and Logger bytes.

### Lifecycle and persistence

- Every registration/ticker has one owner and one terminal cleanup path. `Core/Events.lua` alone owns `ADDON_LOADED`; final teardown is one idempotent `ADDONS_UNLOADING`/`PLAYER_LOGOUT` path.
- DB/session readiness is the root initialization gate. Consumers never start after a failed DB init.
- `SAVED_VARIABLES_TOO_LARGE` is one emergency-compaction path, never a retry loop. Writes remain suspended until explicit clear/reload recovery.
- Doctor scopes are released by exact token and are capped even when callers leak them.
- Safe/internal/CPU/memory wrappers preserve complete argument and return tuples, including trailing nils, without relying on `xpcall` vararg extensions.
- A failed or throttled store is not reported as captured. Pinned records remain bounded; pinning only raises eviction priority.
- BugGrabber attaches at current counters by default; historical replay is opt-in and newly observed foreign counters do not replay their full history.

## Change routing

- schema/defaults/grouping: `Core/DB.lua`
- readiness, migration, occurrence compaction and failure recovery: `Core/DBLifecycle.lua`
- persisted ignore policy: `Core/IgnoreBounds.lua`
- public/internal wrappers: `Core/CallSafety.lua`, `Core/Internal.lua`, `Integration/API.lua`, `Integration/LibStub.lua`
- diagnostic copy/encoding/logging: `Util/BoundedCopy.lua`, `Util/JSON.lua`, `Util/Logger.lua`
- handler ownership: `Capture/Policy.lua`, `Capture/Engine.lua`, `Capture/Safety.lua`
- fallback/intake state: `Capture/BugGrabber.lua`, `Capture/ChatTap.lua`, `Capture/Locals.lua`, `Capture/Storm.lua`, `Capture/Reported.lua`, `Capture/Taint.lua`, `Capture/Warnings.lua`
- callbacks/bus/profiling: `Integration/Callbacks.lua`, `Integration/Bus.lua`, `Perf/*`
- UI only: `UI/*`

Do not add another generic framework, owner, event bus or compatibility layer when one of these files already owns the concern.

## Verification

```sh
./tests/run.sh
find Core Capture Doctor Integration Perf Util UI Export -name '*.lua' -print0 | xargs -0 -n1 texluac -p
```

GitHub Actions runs both gates on every branch/PR. Required client matrix:

- RothDevLib only: login/reload and hard/suppressed/report/warning/taint paths;
- RothDevLib + BugGrabber/BugSack: no replay, duplicates or ownership churn;
- later handler replacement: fallback/unavailable state, no automatic reclaim;
- explicit `/rdev reclaim`;
- combat/restriction transitions with zero RothDevLib-caused blocked/forbidden actions;
- stress, reload loop, bounded export and SavedVariables inspection.

Static review cannot certify client taint, secure execution, frame timing or actual Secret Value behavior. Record exact client build, Interface and addon commit for runtime PASS.
