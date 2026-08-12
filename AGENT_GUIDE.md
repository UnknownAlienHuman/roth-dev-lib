# Agent guide: !RothDevLib

## Start here

The executable contract is [`!RothDevLib.toc`](!RothDevLib.toc), not the archived planning documents. Its load order is deliberate: embedded LibStub/CallbackHandler/LibDataBroker/LibDBIcon, `Core/*` and utilities, Export, Perf, Doctor, Integration, Capture, UI, and finally `Core/Events.lua`. `Core/Events.lua:InitAll` is the lifecycle entry point; `Core/Core.lua` creates the `RDL` namespace and `Core/DB.lua` owns the `RothDevLibDB` SavedVariables table.

The runtime path is:

`ADDON_LOADED("!RothDevLib")` -> `DB:EnsureReady`/`Capture:EarlyInit` -> `PLAYER_LOGIN` -> `InitAll` -> DB, Logger, Doctor, Validation, Bus, memory watcher, Capture, UI, and minimap initialization. `PLAYER_LOGOUT` stops persistent/session work; `PLAYER_REGEN_ENABLED` flushes leave-combat capture work.

## Runtime map

- `Core/DB.lua` initializes defaults, settings, groups, session indexes, bounded trimming, and clear/export-facing reads.
- `Capture/ErrorHandler.lua` is the high-risk ingestion path. It captures Lua errors/warnings, locals, stack/addon attribution, taint/restriction events, boot-queue entries, and forwards structured entries to `DB:UpsertGroup`.
- `Doctor/Doctor.lua`, `Doctor/Breadcrumbs.lua`, and `Doctor/Validation.lua` provide context, breadcrumbs, gates, stress tests, and reload-loop checks used by Capture and UI.
- `Integration/Bus.lua` is the low-allocation cross-addon ring-buffer bus. `Integration/API.lua` exposes `RDL:InitAddon`, `Breadcrumb`, `Metric`, `Profile`, `MemDelta`, `Report*`, `Enter`, and `NewAddon`. `Integration/LibStub.lua` registers `RothDevLib-1.0` only when LibStub is available.
- `Export/Export.lua` and `Export/Packer.lua` read bounded DB/context state and produce share/export text. `LibDeflate` is an optional runtime lookup, not a TOC dependency.
- `UI/MainFrame.lua`, `DetailView.lua`, `Report.lua`, `Monitor.lua`, `ExportFrame.lua`, and `UI/Slash.lua` are consumers. `/rdev` is registered at `UI/Slash.lua:10-11`; addon-compartment callbacks are in `UI/AddonCompartment.lua`.

## State and dependencies

`RothDevLibDB` is the only TOC-declared durable table. Settings, grouped signatures, session data, ignore lists, bounded indexes, and exported diagnostics are written through `RDL.DB`; capture boot queues and module state are transient until DB readiness. Do not treat `RDL.Bus` ring buffers, UI frames, CPU/memory samplers, or Doctor snapshots as durable API.

The four embedded libraries are bundled and loaded before addon code. There is no required external addon dependency. Other in-house addons may consume the public Integration API or `LibStub("RothDevLib-1.0", true)`, but `!RothDevLib` does not load them. Preserve third-party library notices when changing vendored files.

## Change routing

- Change persistence, defaults, migration, trimming, or schema: `Core/DB.lua` (`DB:Init`, `EnsureReady`, `UpsertGroup`) and corresponding validation in `Core/DB.lua`.
- Change event/lifecycle ordering: `Core/Events.lua`; keep early capture before `PLAYER_LOGIN` and keep calls wrapped by `ICall`/`Internal:Call`.
- Change error ownership, handler reclaim, locals filtering, or taint capture: `Capture/ErrorHandler.lua`, then `Capture/Locals.lua`, `Reported.lua`, `Taint.lua`, or `Suppress.lua` as appropriate.
- Add an integration capability: implement the bounded primitive in `Integration/Bus.lua`, expose it through `Integration/API.lua`, and document the consumer contract in `docs/INTEGRATION.md`.
- Change export size/format: `Export/Export.lua` and `Export/Packer.lua`; keep output bounded and secret-safe.
- Change display only: `UI/*`; do not let UI bypass DB/Bus/Capture ownership.
- Change performance sampling: `Perf/CPU.lua`/`Perf/Mem.lua`; preserve sampling intervals and reset semantics.

## Invariants/risks

- The global error handler is shared process state. `Capture:EnsureHandler`, `ApplyHandlerLock`, and `TryReclaimHandler` must remain idempotent and must not recursively report their own failures.
- `hooksecurefunc`, protected frames, `InCombatLockdown`, restricted/secret values, and addon-action taint are explicit risk boundaries. Keep capture/diagnostic calls protected with `pcall`/`Internal:Call`; never perform protected UI mutations from the error path.
- Error ingestion and `DB:UpsertGroup` are hot paths. Keep group/session indexes bounded, preserve Storm throttling, and avoid per-event frame/UI creation.
- Capture can run before SavedVariables are ready; the boot queue must flush only after `DB:IsReady()`.
- UI and optional LibDeflate/LibStub integrations must degrade to no-op/diagnostic states when unavailable.

## Verification

Static checks from the repository root:

```powershell
rg -n "RothDevLibDB|InitAll|Capture:EarlyInit|EnsureHandler|SlashCmdList" _Addons/!RothDevLib
Get-Content _Addons/!RothDevLib/!RothDevLib.toc
```

In-game smoke checks: `/rdev status`, `/rdev gate`, `/rdev test error`, `/rdev test warning`, `/rdev test taint`, `/rdev stress`, `/rdev reloadloop 2`, `/rdev export`, and `/rdev clear`. Verify standalone operation, BugGrabber coexistence, combat/leave-combat, bounded export, reload persistence, and zero self-generated blocked/forbidden actions. Confirm the resulting `RothDevLibDB` shape in the client SavedVariables file rather than assuming a UI message proves persistence.

## Unknowns

Static review cannot prove current Retail frame names, Blizzard handler ownership, or the exact behavior of restricted values on every 12.x build. Those claims require the target client and the existing release-gate matrix in `todo.md`.
