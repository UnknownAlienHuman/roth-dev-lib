# Runtime evidence for addon development

Alpha 20.1 adds persisted session diagnostics and opt-in screenshots. RothDevLib is an evidence collector for an offline agent, not a gameplay controller or a universal cause detector.

## Collect a reproduction

1. Install the addon under `!RothDevLib`, reproduce with the target addon, and note the input sequence and expected result. Repeat with a controlled addon stack when investigating causality.
2. Run `/rdev checkpoint` after the scenario. This updates the in-memory SavedVariables root; it does **not** flush a file.
3. Use normal `/reload` or logout to let the client write `WTF/Account/<account>/SavedVariables/!RothDevLib.lua`. The variable inside is `RothDevLibDB`. A client crash before saving can lose current-session evidence. An addon has no arbitrary filesystem-write or force-flush API here.
4. Give the agent that saved file, the exact target addon revision, reproduction steps and relevant screenshots. `/rdev export json` exposes fuller structured data; `/rdev export pack` produces a budgeted summary and explicitly reports omitted diagnostics.

The collector checkpoints on login, every 30 seconds and at final shutdown. The interval is collection cadence, **not** a native profiler measurement window. `/rdev set persistDiagnostics false` stops periodic checkpoints; error capture and screenshot settings remain independent.

## What survives reload

`RothDevLibDB.groups[signature]` contains bounded error/message/stack/locals data, origin, system state, Doctor context and breadcrumbs. Each retained occurrence also contains a small `evidence` snapshot of that occurrence's extra context. Repeated reports therefore do not replace every earlier expected/observed pair with the newest one. Large locals/context payloads are not duplicated on every repeat.

`RothDevLibDB.sessions[i].diagnostics` records:

- actual client/build/Interface and collector version, installed addon names/versions and loaded status (first 128; omitted count is explicit);
- capture ownership/fallback, ChatTap hook state, event-registration/init failures and intake outcome counters;
- top 32 instrumented CPU and memory records, CPU sample rate, recent breadcrumbs and a bounded log tail;
- native `C_AddOnProfiler` top 20 addons by `RecentAverageTime`, with available session averages, peaks and slow-tick counters;
- up to 60 checkpoint samples of FPS, global Lua heap KB and overall recent native CPU time.

Only the five newest sessions retain these snapshots and screenshot metadata. Diagnostic payload strings have a 256 KiB aggregate-copy budget per session plus node/entry limits; this is not a byte-exact serialized-file or Lua-table-memory bound. Screenshot ledgers have a separate 128 KiB string budget and at most 20 requests per UI session. Omission/truncation markers are evidence, not empty/success values. Persistence-failure recovery can remove these snapshots and suspend writes.

The full JSON envelope exposes these records in `diagnosticSessions`. A packed export includes only the newest session, up to three rows per profiler and three recent screenshot outcomes. At tight budgets the diagnostic summary is omitted explicitly before further reducing error groups. The saved file/full JSON remain the fuller evidence source.

## Interpret measurements correctly

`wrappedCPU` measures instrumented synchronous calls, possibly sampled. It does not measure all code in an addon. Its window is since UI load or an explicit profiling reset.

`wrappedMemory` and `globalLuaHeapKB` concern the global Lua heap. Garbage collection and other allocations affect them; neither is addon-retained-memory attribution or proof of a leak.

Native time metrics are milliseconds; `CountTimeOver5Ms` and `CountTimeOver50Ms` are **counts of profiler ticks**, not milliseconds. Recent average covers 60 profiler ticks, not 60 seconds or 60 rendered frames. Session/peak/count values are cumulative in the application's profiler session. Compare counters over matched intervals; do not subtract peaks as counters. Missing/disabled/inaccessible metrics are not zero. The collector never changes profiling CVars or calls internal performance-warning telemetry.

The native top list is a ranking, not proof that an addon caused a hitch. The collector's `collectionBeforePersistenceMs` excludes final SavedVariables copying and later rendering/saving; use controlled A/B measurements to evaluate total overhead.

## Error attribution, taint and Secret Values

`ctx.extra.evidence` distinguishes evidence from conclusions. A parsed message path is stronger location evidence than a guessed addon from a wrapper stack, but neither alone proves a root cause. `rootCause = "not-established"` is deliberate.

For blocked/forbidden action events, the client reports the blocked addon/action. That addon is **not necessarily the original taint source**. A stack collected inside the event callback belongs to the observer: it is marked `stackProvenance = "event-observer"`, retained as `observerOrigin`, and not promoted to the original fault location. The self-taint gate no longer blames RothDevLib merely because its observer appears in that stack.

`TAINT_STATE` is a normal restriction transition, not a failure: it increments `restrictionChanges`, not the session taint-error count, and never triggers an automatic screenshot. Blocked/forbidden events still count as taint incidents.

Ordinary Lua error messages mentioning secret values/tables get the searchable `SECRET_ACCESS_MESSAGE` category with `classification = "message-heuristic"`. This is not a hidden-value reader. Inaccessible values and opaque escape text remain markers; no declassification, private UI inspection, protected-action retry or inferred combat data is attempted.

Capture is best-effort. The library cannot guarantee every failure: another owner may hide hard errors, a foreign `pcall` may swallow errors without reporting, and a logic/UI defect may never raise an exception. Ignore rules, throttling, queue eviction and retention limits can omit records. Intake counters count attempts, including boot-queue retries, not unique errors.

## Report incorrect behavior explicitly

Use existing integration APIs for invariant failures and ordinary addon-owned state. Do not pass managed/forbidden frame objects, secret values or unbounded gameplay logs as diagnostic payloads.

```lua
local RDL = _G.RothDevLib
if RDL then
    -- Evaluate only your own ordinary configuration/model state here.
    RDL:Report("MyAddon", "ANOMALY", "Layout result differs from requested state", {
        func = "ApplyLayout",
        code = "LAYOUT_MISMATCH",
        extra = {
            scenario = "profile-switch",
            expected = "two-columns",
            observed = "one-column",
            revision = "my-addon-commit-or-version",
        },
    })
end
```

`SafeCall`, `Assert`, breadcrumbs and explicit reports remain useful for swallowed errors and failed expectations. They cannot automatically establish that arbitrary gameplay or UI behavior is wrong.

## Screenshots

```text
/rdev screenshot on       enable automatic requests
/rdev screenshot off      disable automatic requests and cancel queued work
/rdev screenshot now      request one manual diagnostic image
/rdev screenshot status   inspect enablement and the request budget
```

Automatic capture is **off by default**. It responds only to newly committed `LUA_ERROR`, `SUPPRESSED`, `ASSERT`, `TAINT_BLOCKED`, `TAINT_FORBIDDEN` and explicit `ANOMALY` records after initialization. It does not screenshot every ordinary restriction event, warning, CPU alert or repeated signature.

Requests are deferred outside immediate error processing, at least 30 seconds apart, with one pending request and a total limit of 20 attempts per UI session. `/rdev clear` does not reset that attempt/cooldown budget. A missing completion event becomes `completion-unconfirmed` after 10 seconds; there is no retry loop.

The image is written by the normal client `Screenshot()` facility, separately from SavedVariables. The ledger `sessions[i].screenshots.records` stores request/session ID, signature, timestamps and observed outcome. Screenshot result events have **no request ID or filename**. A success event observed while our request is pending is useful correlation, not guaranteed file attribution when the user/another addon also takes screenshots. No filename is fabricated. Deferred images show the later rendered scene, not necessarily the exact error frame.

Screenshots contain the **whole visible screen, potentially names, chat and other private information**. RothDevLib does not hide the UI, alter CVars, read image pixels, upload files or send anything to an agent. Review images and SavedVariables before sharing them.

## Source and validation boundary

Public contracts inspected:

- `Gethe/wow-ui-source@297d7aaaa736f346b3e036f38ee088eaf7f8c07f`, Retail 12.1.5.70783: `Interface/AddOns/Blizzard_APIDocumentationGenerated/ClientDocumentation.lua:Screenshot` and `VideoDocumentation.lua:SCREENSHOT_SUCCEEDED/SCREENSHOT_FAILED`. No filename/request payload is declared.
- `Gethe/wow-ui-source@d07eb00237d8891f153215db98a5df880a26cfe5`, Retail 12.1.5.70688: `AddOnProfilerDocumentation.lua:IsEnabled/GetTopKAddOnsForMetric/GetAddOnMetric/GetOverallMetric`; the KB's reviewed 70783 delta does not change this contract.
- Owning KB guides: `KB/deep/WoWDevSecretValue_KB_12.1.5.md`, `KB/core/BlizzardUI_Performance_Modules.md`, selected 12.1.5 contract overlays.

Offline tests exercise persistence/reload normalization, measurement status/limits, the error-to-export path, screenshot lifecycle and failure paths, and event teardown. Actual WoW capture/rendering, hardware/client policy, real taint/Secret Values and save timing remain **NOT-RUN**. Verify screenshots, shutdown save/reload, native metric readings and no self-caused blocked actions in the named client before declaring runtime PASS.
