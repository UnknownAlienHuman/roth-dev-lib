# !RothDevLib — release gate

Current version: **1.0.0-alpha.20.0**  
Target: **Retail 12.1.5 / Interface 120105**

## Remaining work

Only named-client validation remains:

- [ ] RothDevLib only: login, `/reload`, hard error, warning, taint/restriction event, report, export and UI smoke tests.
- [ ] RothDevLib + BugGrabber/BugSack: verify one-time chain ownership, no historical replay, no duplicate groups and no automatic handler churn.
- [ ] Deliberately replace the handler after login: RothDevLib must switch to BugGrabber fallback/unavailable state and must not reclaim until `/rdev reclaim`.
- [ ] Combat: capture/report/open-after-combat flows with zero blocked or forbidden actions caused by RothDevLib.
- [ ] Stress: `/rdev stress`, bounded DB growth, responsive UI and stable export budgets.
- [ ] Reload loop: `/rdev reloadloop`, preserved settings and no duplicate hooks/tickers.
- [ ] Final `/rdev gate`: PASS; self-taint blocked/forbidden count remains zero.

## Alpha 20 completed

- Updated the manifest and documentation to Retail 12.1.5 (`120105`).
- Added TOC-derived runtime version metadata.
- Replaced legacy-only chat-link handling with `LinkUtil.RegisterLinkHandler`, retaining a legacy fallback.
- Removed invasive popup/frame suppression and foreign event unregistration.
- Replaced the loaded 48-KB legacy error-handler monolith with the compact `Capture/Engine.lua` owner and retired the global setter lock.
- Forced one-time chain ownership and disabled automatic reclaim/watchdog fights; manual reclaim remains explicit.
- Rejected secure-only `AddLuaErrorHandler` as an ordinary-addon fallback; retained bounded BugGrabber import only.
- Baseline BugGrabber history by default and use stable content keys across list reordering.
- Rebuilt ChatTap and BugGrabber import around bounded ordinary-value snapshots.
- Added bounded ordinary-value boundaries for public API, reports, taint/restriction data, JSON, callbacks and breadcrumbs.
- Added total-node table-copy budgets and raw traversal that bypasses hostile metatables.
- Defined callback dispatch mutation semantics and isolated each callback payload from DB state and other consumers.
- Preserved arbitrary return tuples through Core, Internal, Doctor, CPU and memory wrappers.
- Added token-aware Doctor cleanup for normal, suppressed and externally handled hard-error paths.
- Fixed minimap drag angle/scale handling and LDB button recovery.
- Fixed breadcrumb ring resize semantics and option alias compatibility.
- Updated load-on-demand menu loading to `C_AddOns.LoadAddOn`.
- Repository test suite now contains 28 focused offline tests; the twelve tests changed or added by the second pass pass locally.
