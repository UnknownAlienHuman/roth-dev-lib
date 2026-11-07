# Code index

| Path | Responsibility |
| --- | --- |
| `!RothDevLib.toc` | Metadata and definitive load order, including early SavedVariables availability. |
| `Core/Core.lua` | Namespace bootstrap and integrity fingerprints only. |
| `Core/CallSafety.lua`, `Core/Internal.lua` | Public/internal guarded calls, portable argument/return-tuple preservation and Doctor cleanup. |
| `Core/Version.lua` | TOC-derived runtime version/interface metadata. |
| `Core/DB.lua` | Authoritative SavedVariables store, grouping and session implementation. |
| `Core/DBLifecycle.lua` | PLAYER_LOGIN readiness gate, schema-5 repair, compact occurrence persistence, hard root bounds and oversized-SavedVariables recovery. |
| `Core/IgnoreBounds.lua` | Bounded persisted signature/addon ignore registries with bounded startup scan and emergency compaction. |
| `Core/Events.lua` | Lifecycle/event routing, failed-root initialization gate and idempotent final teardown. |
| `Capture/Policy.lua` | Raw persisted chain-once policy without constructing DB/session state. |
| `Capture/Engine.lua` | Compact handler construction, ownership observation, entry construction and storage routing. |
| `Capture/Safety.lua` | Rich bounded intake, manual reclaim and BugGrabber/unavailable fallback diagnostics. |
| `Capture/BugGrabber.lua` | Bounded counter-delta fallback import with one-time history baseline and bounded signatures/state. |
| `Capture/ChatTap.lua` | Bounded heuristic chat intake and hard-capped dedup state. |
| `Capture/Locals.lua` | Bounded locals probing, foreign-option access and capped calibration cache. |
| `Capture/Storm.lua` | Token-bucket flood control with a shared overflow bucket for dynamic kinds. |
| `Capture/Reported.lua`, `Capture/Taint.lua`, `Capture/Warnings.lua`, `Capture/Suppress.lua` | Explicit report, restriction/warning intake and non-invasive presentation suppression. |
| `Doctor/Doctor.lua` | Capped token-aware correlation stack with detached contexts. |
| `Doctor/Breadcrumbs.lua`, `Doctor/Validation.lua` | Error context routing, runtime gates, stress and reload-loop validation. |
| `Integration/Callbacks.lua` | Deterministic callback dispatch with independent payloads and hard registry caps. |
| `Integration/Bus.lua` | Bounded breadcrumb rings plus capped addon/metric identities. |
| `Integration/API.lua`, `Integration/LibStub.lua` | Public diagnostics and optional LibStub integration surfaces. |
| `Perf/CPU.lua`, `Perf/Mem.lua` | Best-effort profiling with capped identity maps and complete return-tuple preservation. |
| `Util/SecretGuard.lua`, `Util/Util.lua`, `Util/BoundedCopy.lua` | Secret/access gating and bounded ordinary diagnostic copies, including total-byte budgets. |
| `Util/JSON.lua` | Deterministic raw JSON traversal with depth/entry/scan/node/string/output limits. |
| `Util/Logger.lua` | Per-line and total-byte-bounded in-memory log. |
| `Export/` | Bounded report packing and formatting. |
| `UI/` | Main frame, lists, monitor, report/export views and slash commands; consumers only. |
| `tests/` | Complete offline regression suite, including saturation and hostile-input matrices. |
| `.github/workflows/ci.yml` | Full test suite plus first-party `texluac -p` gate on pushes and pull requests. |
| `docs/` | User and integration documentation; legacy plans remain explicitly archived. |
