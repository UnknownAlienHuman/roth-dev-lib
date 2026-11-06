# Architecture

The TOC is the executable composition root. It loads vendored libraries, Core/utilities, Export, Perf, Doctor, Integration, Capture, UI and finally `Core/Events.lua`.

## Capture ownership

`Capture/Policy.lua` runs immediately before `Capture/Engine.lua` and establishes a compatibility-first policy before file-load EarlyInit:

```text
current handler
  -> one RothDevLib chain wrapper
  -> previous handler forwarded once
  -> later owner may replace RothDevLib
  -> no automatic reclaim fight
  -> BugGrabber delta fallback or explicit unavailable state
  -> optional user `/rdev reclaim`
```

`Capture/Engine.lua` is the complete loaded ownership implementation; the obsolete legacy monolith is no longer loaded. `Capture/Safety.lua` adds the richer bounded intake and fallback diagnostics. Secure-only `AddLuaErrorHandler`, private ScriptErrorsFrame hooks/polling and global setter locking are not supported addon paths.

## Data flow

```text
external or runtime diagnostic input
  -> immediate access gate
  -> bounded detached ordinary copy
  -> Capture entry construction
  -> bounded DB group/session storage
  -> callback dispatch with one copy per consumer
  -> UI/export consumers
```

`Util:CopyDiagnosticValue` uses raw traversal and bounds depth, entries, total nodes and string bytes. Callback payloads never expose live DB/bus tables or shared mutable copies between consumers.

## Context and wrappers

`Core/CallSafety.lua` is loaded after `Util/BoundedCopy.lua`, so public wrappers use the final ordinary-value boundary without duplicating the namespace/self-check owner.

Doctor scopes are identity tokens. Normal calls remove their exact token. Hard-error wrappers keep the token available to the synchronous global handler and arm a one-frame token cleanup in case another owner handles the error. CPU/memory wrappers and internal calls preserve arbitrary return tuples, including nil positions; telemetry failure cannot alter a successful target result.

## State

`RothDevLibDB` is the only TOC-declared durable table. Capture queues, bus rings, callback registrations, profiler samples, timer handles and UI frames are transient. Export reads bounded ordinary snapshots.

## Runtime gate

Static tests cannot prove combat lockdown, taint propagation, secure execution or frame timing. Use `/rdev gate`, `/rdev stress`, `/rdev reloadloop` and the named-client matrix in [todo.md](todo.md), recording exact client build, Interface and addon commit.
