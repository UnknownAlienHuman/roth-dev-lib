# Agent guide: !RothDevLib

## Start here

The executable contract is [`!RothDevLib.toc`](!RothDevLib.toc), not archived planning documents. Its load order is deliberate: embedded libraries, Core and utilities, Export, Perf, Doctor, Integration, Capture, UI, then `Core/Events.lua`.

The runtime path is:

`Capture/Policy.lua` -> one-time chain ownership policy -> `Capture/Engine.lua:EarlyInit` -> `ADDON_LOADED("!RothDevLib")` -> DB/capture readiness -> `PLAYER_LOGIN` -> `InitAll`.

`Capture/Policy.lua` must load immediately before `Capture/Engine.lua`. It establishes the chain-once settings consumed by file-load EarlyInit. `Capture/Safety.lua` then installs the richer bounded intake and fallback policy. Do not reorder these files casually.

## Runtime map

- `Core/DB.lua` owns defaults, settings, grouped entries, sessions, indexes and trimming.
- `Core/CallSafety.lua` owns public safe/unsafe wrappers and Doctor-token cleanup; `Core/Core.lua` retains namespace and self-check ownership.
- `Core/Internal.lua` owns guarded internal execution; it must preserve arbitrary return tuples and always release its exact Doctor token.
- `Doctor/Doctor.lua` owns the context stack. `Leave(expectedToken)` removes exactly that scope so delayed cleanup cannot pop an unrelated later context.
- `Integration/Callbacks.lua` snapshots registrations before dispatch. New registrations wait for the next dispatch, replacements/unregistrations before a callback turn are respected, and every callback receives its own detached bounded payload.
- `Integration/Bus.lua` owns bounded transient breadcrumbs/metrics.
- `Capture/Engine.lua` owns initial handler construction, ownership state, entry construction and storage routing. `Capture/Safety.lua` owns the richer hard/suppressed/integration intake and fallback diagnostics.
- `Capture/BugGrabber.lua` is the only hard-error fallback when RothDevLib loses handler ownership. It baselines existing history unless `importBugGrabberHistory == true`.
- `Export/Export.lua` and `Export/Packer.lua` produce bounded reports. `LibDeflate` is optional.
- UI modules are consumers; they do not own capture state.

## Ownership contract

The global error handler is shared process state:

1. RothDevLib chain-wraps the current handler once during EarlyInit.
2. It forwards to the previous handler in chain mode.
3. If a later addon replaces it, RothDevLib records the new owner and attaches BugGrabber fallback when available.
4. It does **not** automatically reclaim, poll or fight the later owner.
5. `/rdev reclaim` is the only supported explicit reclaim path.

Do not reintroduce:

- `_G.seterrorhandler = function() end`;
- periodic ownership reclaim;
- reclaim from the `seterrorhandler` post-hook;
- a mutating “probe” that temporarily swaps the handler;
- `AddLuaErrorHandler` from ordinary addon execution (selected Blizzard source asserts secure execution);
- ScriptErrorsFrame private polling or method hooks.

## State and data boundaries

`RothDevLibDB` is the only durable table. Persist only bounded ordinary copies. External tables, secret-capable values, frames, callbacks, timers and pooled objects must not survive into DB state.

`Util:CopyDiagnosticValue` owns the generic copy boundary:

- gate value/table access before Lua operations;
- traverse with raw `next`/`rawget`, not foreign `__pairs`/`__index`;
- bound depth, per-table entries, total nodes and string bytes;
- preserve nil only as tuple position, not as an invented table value;
- replace cycles, inaccessible values and unsupported runtime types with explicit markers.

Callbacks are not an ownership shortcut. `RDL:Fire` provides independent detached copies; consumers must not depend on table identity or mutate DB state through callback payloads.

## Change routing

- Persistence/schema/trimming: `Core/DB.lua`.
- Initial ownership policy: `Capture/Policy.lua`.
- Handler construction/ownership state: `Capture/Engine.lua`.
- Current intake, manual reclaim and fallback selection: `Capture/Safety.lua`.
- BugGrabber counters/history: `Capture/BugGrabber.lua`.
- Public wrappers: `Core/CallSafety.lua`, `Integration/API.lua`, `Integration/LibStub.lua`.
- Callback semantics: `Integration/Callbacks.lua`.
- Context lifecycle: `Doctor/Doctor.lua`, `Core/Internal.lua`.
- Performance wrappers: `Perf/CPU.lua`, `Perf/Mem.lua`; preserve the complete return tuple and keep telemetry best-effort.
- Export format/budgets: `Export/*`.
- Display only: `UI/*`.

## Verification

Offline:

```sh
./tests/run.sh
find Core Capture Doctor Integration Perf Util UI Export -name '*.lua' -print0 | xargs -0 -n1 texluac -p
```

Required client matrix:

- RothDevLib only: login/reload, hard/suppressed/report/warning/taint paths.
- RothDevLib + BugGrabber/BugSack: no duplicate import or ownership churn.
- Replace the handler after login: no automatic reclaim; fallback/unavailable state is accurate.
- Explicit `/rdev reclaim`: one bounded user-requested attempt.
- Combat and restriction transitions: zero RothDevLib-caused blocked/forbidden actions.
- Stress/reload/export/DB persistence and SavedVariables inspection.

Static review cannot certify client taint, secure execution, frame timing or actual Secret Value behavior. Record exact client build, Interface and addon commit for runtime PASS.
