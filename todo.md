# !RothDevLib — release gate

Current version: **1.0.0-alpha.20.0**  
Target: **Retail 12.1.5 / Interface 120105**

## Remaining work

### Static follow-up

- [x] Harden the tiny pre-`Safety.lua` error-handler window so an intake fault cannot strand `_inHandler` or skip the prior handler.
- [x] Recheck warning/taint/report store-status handling and fallback ticker teardown.
- [x] Recheck ChatTap continuation parsing and disabled-setting timer cleanup.
- [ ] Run the complete repository offline suite after the final static pass; the focused third-pass matrix is green.

### Named-client validation

- [ ] RothDevLib only: login, `/reload`, hard error, warning, taint/restriction event, report, export and UI smoke tests.
- [ ] RothDevLib + BugGrabber/BugSack: verify one-time chain ownership, no historical replay, no duplicate groups and no automatic handler churn.
- [ ] Deliberately replace the handler after login: RothDevLib must switch to BugGrabber fallback/unavailable state and must not reclaim until `/rdev reclaim`.
- [ ] Combat: capture/report/open-after-combat flows with zero blocked or forbidden actions caused by RothDevLib.
- [ ] Stress: `/rdev stress`, bounded DB growth, responsive UI and stable export budgets.
- [ ] Reload loop: `/rdev reloadloop`, preserved settings and no duplicate hooks/tickers.
- [ ] Final `/rdev gate`: PASS; self-taint blocked/forbidden count remains zero.

## Alpha 20 completed

- Updated the manifest and documentation to Retail 12.1.5 (`120105`).
- Added TOC-derived runtime version metadata and intentional early SavedVariables loading.
- Replaced legacy-only chat-link handling with `LinkUtil.RegisterLinkHandler`, retaining a legacy fallback.
- Removed invasive popup/frame suppression and foreign event unregistration.
- Replaced the loaded legacy error-handler monolith with the compact `Capture/Engine.lua` owner and retired the global setter lock.
- Forced one-time chain ownership and disabled automatic reclaim/watchdog fights; manual reclaim remains explicit.
- Rejected secure-only `AddLuaErrorHandler` as an ordinary-addon fallback; retained bounded BugGrabber import only.
- Baseline BugGrabber history by default, use stable content keys and avoid foreign `__len` execution.
- Rebuilt ChatTap and BugGrabber import around bounded ordinary-value snapshots.
- Added bounded ordinary-value boundaries for public API, reports, taint/restriction data, JSON, callbacks and breadcrumbs.
- Added raw JSON/table traversal plus depth, entry, scan, node, string and output budgets.
- Guarded bootstrap hard-error intake and made successful-store status explicit across hard, suppressed, report, warning, taint and chat paths.
- Preserved inaccessible restriction states, rejected inaccessible external signature identities and fixed ChatTap stack-line/header ordering.
- Defined callback dispatch mutation semantics and isolated each callback payload from DB state and other consumers.
- Preserved arbitrary return tuples through Core, Internal, Doctor, CPU and memory wrappers.
- Added token-aware Doctor cleanup for normal, suppressed and externally handled hard-error paths.
- Fixed minimap drag angle/scale handling and LDB button recovery.
- Fixed breadcrumb ring resize semantics and option alias compatibility.
- Updated load-on-demand menu loading to `C_AddOns.LoadAddOn`.
