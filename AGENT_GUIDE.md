# Agent guide: !RothDevLib

## Start here

The executable contract is [`!RothDevLib.toc`](!RothDevLib.toc). Read it before changing code. The declared order is intentional:

1. embedded libraries;
2. namespace, version, DB, DB lifecycle gate and internal calls;
3. Secret Value guards, bounded copy/JSON and public call safety;
4. export, profiling, Doctor and integration;
5. capture policy/engine/intake modules;
6. UI and the final lifecycle dispatcher.

`## LoadSavedVariablesFirst: 1` is required. `Capture/Policy.lua` reads only the persisted settings table during file loading; `Core/DBLifecycle.lua` prevents player/session construction until `PLAYER_LOGIN`. Early captured entries remain in the bounded boot queue and are bound to the real session only when committed.

## Runtime ownership

- `Core/Core.lua`: namespace bootstrap and integrity fingerprints only.
- `Core/CallSafety.lua`: public safe/unsafe wrappers and tuple-preserving Doctor cleanup.
- `Core/DB.lua`: authoritative persistence/group/session implementation.
- `Core/DBLifecycle.lua`: PLAYER_LOGIN readiness gate, one-time persisted-state repair and boot-entry session binding.
- `Util/BoundedCopy.lua`: raw bounded snapshots of foreign diagnostic values.
- `Util/JSON.lua`: deterministic raw traversal, node/depth/entry/string/output budgets.
- `Doctor/Doctor.lua`: token-aware context stack.
- `Integration/Callbacks.lua`: deterministic snapshot dispatch; every consumer receives a detached payload.
- `Capture/Policy.lua`: one-time compatibility policy before handler installation.
- `Capture/Engine.lua`: handler construction, ownership state, entry construction and storage routing.
- `Capture/Safety.lua`: bounded hard/suppressed/integration intake and fallback selection.
- `Capture/BugGrabber.lua`: the only supported hard-error fallback after handler ownership is lost.
- UI modules are consumers; they do not own capture state.

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
- cap depth, entries, total nodes and string bytes;
- represent inaccessible/cyclic/unsupported data with explicit markers;
- never retain foreign tables, frames, timers, callbacks or pooled objects in `RothDevLibDB`.

### Lifecycle

- Every registration/ticker has one owner and one terminal cleanup path.
- Doctor scopes are released by exact token.
- Safe, internal, CPU and memory wrappers preserve the complete return tuple, including nil positions.
- A failed or throttled store is not reported as captured.
- BugGrabber attaches at the current counters by default; historical replay is opt-in.

## Change routing

- schema/defaults/grouping: `Core/DB.lua`; readiness and persisted repair: `Core/DBLifecycle.lua`
- public wrappers: `Core/CallSafety.lua`, `Integration/API.lua`, `Integration/LibStub.lua`
- diagnostic copy/encoding: `Util/BoundedCopy.lua`, `Util/JSON.lua`
- handler ownership: `Capture/Policy.lua`, `Capture/Engine.lua`
- intake/fallback: `Capture/Safety.lua`, `Capture/BugGrabber.lua`, `Capture/Reported.lua`, `Capture/Taint.lua`, `Capture/Warnings.lua`
- callback semantics: `Integration/Callbacks.lua`
- UI only: `UI/*`

Do not add another generic framework, owner, event bus or compatibility layer when one of these files already owns the concern.

## Verification

```sh
./tests/run.sh
find Core Capture Doctor Integration Perf Util UI Export -name '*.lua' -print0 | xargs -0 -n1 texluac -p
```

Required client matrix:

- RothDevLib only: login/reload and hard/suppressed/report/warning/taint paths;
- RothDevLib + BugGrabber/BugSack: no replay, duplicates or ownership churn;
- later handler replacement: fallback/unavailable state, no automatic reclaim;
- explicit `/rdev reclaim`;
- combat/restriction transitions with zero RothDevLib-caused blocked/forbidden actions;
- stress, reload loop, bounded export and SavedVariables inspection.

Static review cannot certify client taint, secure execution, frame timing or actual Secret Value behavior. Record exact client build, Interface and addon commit for runtime PASS.
