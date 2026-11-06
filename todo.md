# !RothDevLib — release gate

Current version: **1.0.0-alpha.20.0**  
Target: **Retail 12.1.5 / Interface 120105**

## Remaining work

Only client-runtime validation remains:

- [ ] RothDevLib only: login, `/reload`, hard error, warning, taint/restriction event, report, export and UI smoke tests.
- [ ] RothDevLib + BugGrabber/BugSack: verify chain ownership, no duplicate groups and no error-handler churn.
- [ ] Combat: capture/report/open-after-combat flows with zero blocked or forbidden actions caused by RothDevLib.
- [ ] Stress: `/rdev stress`, bounded DB growth, responsive UI and stable export budgets.
- [ ] Reload loop: `/rdev reloadloop`, preserved settings and no duplicate hooks/tickers.
- [ ] Final `/rdev gate`: PASS; self-taint blocked/forbidden count remains zero.

## Alpha 20 completed

- Updated the manifest and documentation to Retail 12.1.5 (`120105`).
- Added TOC-derived runtime version metadata.
- Replaced legacy-only chat-link handling with `LinkUtil.RegisterLinkHandler`, retaining a legacy fallback.
- Removed invasive popup/frame suppression and foreign event unregistration.
- Retired the `seterrorhandler` global lock while preserving normal chain/exclusive capture ownership.
- Replaced ScriptErrorsFrame polling with the current `AddLuaErrorHandler` fallback.
- Rebuilt ChatTap and BugGrabber import around bounded ordinary-value snapshots.
- Added a bounded ordinary-value boundary for public API, reports, taint/restriction data, JSON and breadcrumbs.
- Fixed minimap drag angle/scale handling and LDB button recovery.
- Fixed breadcrumb ring resize semantics and option alias compatibility.
- Updated load-on-demand menu loading to `C_AddOns.LoadAddOn`.
- Added 22 focused offline regression tests under `tests/`.
