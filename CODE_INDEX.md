# Code index

| Path | Responsibility |
| --- | --- |
| `!RothDevLib.toc` | Metadata and definitive load order. |
| `Core/Core.lua`, `Core/Version.lua` | Namespace and runtime release metadata. |
| `Core/DB.lua`, `Core/Events.lua`, `Core/Internal.lua` | Persistence, lifecycle/event bootstrap and guarded internal dispatch. |
| `Util/SecretGuard.lua`, `Util/Util.lua` | Ordinary-value boundary, bounded snapshots and shared normalization. |
| `Util/JSON.lua` | Deterministic bounded JSON encoding. |
| `Integration/` | Public API, callbacks, per-addon breadcrumb bus and LibStub bridge. |
| `Capture/ErrorHandler.lua`, `Capture/Safety.lua` | Error ownership and non-invasive safety policy. |
| `Capture/` | Report, warning, taint, chat, flood and presentation capture modules. |
| `Doctor/` | Execution context, validation and correlation breadcrumbs. |
| `Perf/` | CPU and memory observations. |
| `Export/` | Bounded report packing and export formatting. |
| `UI/` | Main frame, lists, monitor, links, export views, launchers and slash commands. |
| `tests/` | Offline contract/regression tests; not loaded by WoW. |
| `docs/` | User and integration documentation. |
