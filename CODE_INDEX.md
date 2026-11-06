# Code index

| Path | Responsibility |
| --- | --- |
| `!RothDevLib.toc` | Metadata and definitive load order, including early SavedVariables availability. |
| `Core/Core.lua`, `Core/CallSafety.lua`, `Core/Internal.lua` | Namespace plus public/internal guarded calls, return-tuple preservation and Doctor cleanup. |
| `Core/Version.lua` | TOC-derived runtime version/interface metadata. |
| `Core/DB.lua` | Authoritative SavedVariables store, grouping and session implementation. |
| `Core/DBLifecycle.lua` | PLAYER_LOGIN readiness gate, one-time persisted-state repair and boot-entry session binding. |
| `Core/Events.lua` | Lifecycle/event routing; file-load capture is separate from player-session initialization. |
| `Capture/Policy.lua` | Raw persisted chain-once policy without constructing DB/session state. |
| `Capture/Engine.lua` | Compact handler construction, ownership observation, entry construction and storage routing. |
| `Capture/Safety.lua` | Rich bounded intake, manual reclaim and BugGrabber/unavailable fallback diagnostics. |
| `Capture/BugGrabber.lua` | Counter-delta fallback import with history baselining and stable keys. |
| `Capture/` | Remaining warning, taint, chat, locals and storm capture modules. |
| `Doctor/` | Token-aware context stack, breadcrumbs and validation. |
| `Integration/Callbacks.lua` | Deterministic callback dispatch with independent detached payloads. |
| `Integration/Bus.lua`, `Integration/API.lua`, `Integration/LibStub.lua` | Public diagnostics bus and integration surfaces. |
| `Export/` | Report packing and formatting. |
| `Perf/` | Best-effort CPU/memory observations that preserve complete return tuples. |
| `UI/` | Main frame, lists, monitor, report/export views and slash commands. |
| `Util/Util.lua`, `Util/BoundedCopy.lua`, `Util/JSON.lua` | Shared helpers plus bounded raw diagnostic copying and encoding. |
| `tests/` | Offline regression tests. |
| `docs/` | User and integration documentation; legacy plans remain explicitly archived. |
