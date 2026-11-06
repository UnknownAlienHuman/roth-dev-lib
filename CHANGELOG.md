# Changelog

## 1.0.0-alpha.20.0 — 2026-11-06

### Compatibility

- Target Retail 12.1.5, Interface 120105.
- Register `rothdevlib` links through the current `LinkUtil` dispatcher, with a bounded legacy fallback.
- Load Blizzard menu support through `C_AddOns.LoadAddOn`.

### Correctness and safety

- Normalize external values before comparison, formatting, iteration, persistence or callback delivery.
- Deep-copy and bound diagnostic payloads; inaccessible values are represented explicitly.
- Bound JSON traversal, strings, arrays, object entries and total output.
- Preserve newest breadcrumbs when a ring is resized.
- Retire the invasive global error-handler lock and restore the real setter for migrated installs.
- Use the current `AddLuaErrorHandler` fallback instead of ScriptErrorsFrame polling and legacy global hooks.
- Rebuild ChatTap and BugGrabber import as bounded, secret-safe external intake paths.
- Stop replacing Blizzard frame methods, mutating `StaticPopupDialogs`, or unregistering Blizzard-owned events.

### UI

- Fix manual minimap dragging with `math.atan2` and effective-scale coordinates.
- Recover a missing LibDBIcon button correctly.
- Use owner-aware tooltip cleanup for the addon-compartment entry.

### Validation

- Added 22 offline regression tests covering secret-value boundaries, hard/fallback error intake, ChatTap, BugGrabber, JSON, bus rings, reports, taint, links, suppression, menus, addon compartment and both minimap paths.
- In-game matrix: not run in this environment.
