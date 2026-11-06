# Architecture

`!RothDevLib.toc` is the executable load-order contract: vendored libraries, core/version/database, the ordinary-value boundary, export/performance/context services, integration API, capture, UI, then the event bootstrap.

## Ownership

- `Core/Events.lua` owns lifecycle and event dispatch.
- `Core/DB.lua` exclusively owns `RothDevLibDB` normalization and persistence.
- `Capture/ErrorHandler.lua` owns error-handler capture; `Capture/Safety.lua` enforces the non-invasive ownership policy.
- `Integration/Bus.lua` owns bounded in-memory breadcrumb rings.
- UI modules consume services; they do not own capture or database state.

## Data boundary

`Util/SecretGuard.lua` and `Util/Util.lua` gate external values before ordinary Lua operations. Public API, reports, restricted-action events, breadcrumbs and JSON export convert caller data into bounded snapshots. Foreign tables are never retained by reference.

## Blizzard UI integration

Use documented APIs, events and post-hooks. Presentation suppression is reversible by setting and never replaces Blizzard methods, mutates popup definitions, or unregisters events from foreign frames.

## Validation boundary

Offline syntax and mocked contract tests cannot prove combat lockdown, taint propagation, real secret-value behavior or Blizzard frame timing. Those remain explicit in-game release gates in [todo.md](todo.md).
