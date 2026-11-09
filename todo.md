# !RothDevLib — release gate

Current version: **1.0.0-alpha.20.0**  
Target: **Retail 12.1.5 / Interface 120105**

## Remaining work

### Static/offline gate

- [x] One-time chain ownership with no automatic reclaim or global setter lock.
- [x] Bounded hard/suppressed/report/warning/taint/chat/BugGrabber intake.
- [x] Depth/entry/node/string/total-byte/output budgets for diagnostic copies and encoding.
- [x] PLAYER_LOGIN DB/session gate, failed-root retry semantics and bounded boot-entry binding.
- [x] Schema-5 compact occurrence persistence and hard group/session/payload caps.
- [x] Bounded persisted ignore registries and one-shot `SAVED_VARIABLES_TOO_LARGE` recovery.
- [x] Idempotent `ADDONS_UNLOADING` / `PLAYER_LOGOUT` teardown.
- [x] Hard caps for Bus, CPU/memory, callbacks, Doctor, Locals, ChatTap, BugGrabber, Storm and Logger retained state.
- [x] Portable protected-call argument/return tuples, including interior and trailing nils.
- [x] Complete repository regression suite and first-party Lua syntax gate in CI.
- [x] Architecture, code index, agent guide and changelog synchronized with the executable load order.
- [x] Second-pass logic audit: handler forwarding, BugGrabber record identity, JSON key uniqueness, Doctor tokens, profiler wrapper ownership, packer telemetry and retryable monitor construction.

### Named-client validation

- [ ] RothDevLib only: login, `/reload`, hard error, warning, taint/restriction event, explicit report, export and UI smoke tests.
- [ ] RothDevLib + BugGrabber/BugSack: one-time chain ownership, no historical replay, no duplicate groups and no ownership churn.
- [ ] Deliberately replace the handler after login: switch to BugGrabber fallback/unavailable state and do not reclaim until `/rdev reclaim`.
- [ ] Combat: capture/report/open-after-combat flows with zero RothDevLib-caused blocked or forbidden actions.
- [ ] Stress: `/rdev stress`, bounded DB/registry growth, responsive UI and stable export budgets.
- [ ] Persistence failure drill: synthetic oversized SavedVariables event, emergency compaction notice, suspended writes, `/rdev clear`, `/reload` recovery.
- [ ] Reload loop: `/rdev reloadloop`, preserved settings and no duplicate hooks/tickers.
- [ ] Final `/rdev gate`: PASS; self-taint blocked/forbidden count remains zero.

## Alpha 20 implementation summary

- Retail 12.1.5 (`120105`) manifest and current `LinkUtil`/`C_AddOns` integration.
- Bounded ordinary-value and Secret Value boundaries across capture, API, callbacks, logs, persistence and UI-facing data.
- Compact handler owner plus explicit BugGrabber/unavailable fallback policy.
- Bounded ChatTap, locals calibration, storm throttling, Doctor correlation and telemetry/callback registries.
- Schema-5 bounded persistence with compact occurrences, ignore-map caps and oversized-SavedVariables recovery.
- Complete CI-backed offline regression and syntax gates.

Only the real WoW client matrix above remains before release certification.
