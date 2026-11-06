# Architecture

!RothDevLib is one addon with five ownership layers:

```text
loader/persistence
  -> ordinary-value boundary
  -> diagnostics and capture
  -> bounded storage/export
  -> UI consumers
```

`!RothDevLib.toc` is authoritative. `LoadSavedVariablesFirst` makes only the persisted root available before the first Lua file. File-load capture policy may read that root, but `Core/DBLifecycle.lua` blocks full DB/session construction until `PLAYER_LOGIN`. Errors captured earlier stay in a bounded boot queue and receive the real session ID when committed after login.

`Core/Core.lua` only creates the namespace and integrity fingerprints. `Core/CallSafety.lua` owns public wrappers after Secret Value guards and bounded-copy utilities are loaded. `Core/DB.lua` remains the persistence owner; `Core/DBLifecycle.lua` supplies the readiness gate, pre-scan repair and hard runtime bounds without creating a second store. Pinning affects eviction priority but cannot bypass the global cap.

`Capture/Policy.lua` configures one-time chain ownership. `Capture/Engine.lua` installs and observes the global error handler without reclaim wars. `Capture/Safety.lua` normalizes hard/suppressed/integration intake. If ownership is lost, `Capture/BugGrabber.lua` provides bounded counter-delta import; otherwise fallback is explicitly unavailable.

All external diagnostic data crosses `Util/BoundedCopy.lua` or an equivalent narrow intake boundary before storage or callbacks. Raw table traversal avoids foreign metamethods and enforces depth, entry, node and string budgets. `Util/JSON.lua` applies the same rule plus an output-byte budget.

Doctor scopes use exact tokens. Callback dispatch snapshots registrations and gives each consumer an independent bounded payload. Profiling is best-effort traffic and must not change target return tuples or hard-error behavior.

UI modules read DB/service state and expose commands, filters and exports. They do not own capture, persistence or security policy. `Core/Events.lua` is also the only `ADDON_LOADED` owner for late ScriptErrors presentation attachment.

Runtime-only claims remain unverified until the named-client matrix in [todo.md](todo.md) is executed.
