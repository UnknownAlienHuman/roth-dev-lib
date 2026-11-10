# !RothDevLib — release gate

Current version: **1.0.0-alpha.20.1**  
Target: **Retail 12.1.5 / Interface 120105**

## Offline coverage

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
- [x] Second-pass logic audit: handler forwarding, BugGrabber record identity, JSON key uniqueness, Doctor tokens, profiler wrapper ownership, packer telemetry and retryable monitor construction.
- [x] Persist native/instrumented performance, environment and capture-coverage evidence across reload normalization; retain five recent diagnostic sessions.
- [x] Preserve per-occurrence context, post-commit callback ordering and full/packed evidence exports.
- [x] Distinguish taint incidents from normal restriction transitions and observer stacks from causal fault locations.
- [x] Optional screenshot request limits, synchronous results, timeout/failure states, stale timers, opt-out, clear and shutdown.

## Named-client validation — NOT-RUN

- [ ] RothDevLib only: login, `/reload`, hard error, warning, taint/restriction event, explicit report, export and UI smoke tests.
- [ ] RothDevLib + BugGrabber/BugSack: one-time chain ownership, no historical replay, no duplicate groups and no ownership churn.
- [ ] Deliberately replace the handler after login: switch to BugGrabber fallback/unavailable state and do not reclaim until `/rdev reclaim`.
- [ ] Combat: capture/report/open-after-combat flows with zero RothDevLib-caused blocked or forbidden actions.
- [ ] Native performance: compare actual readings and checkpoint overhead in a controlled addon stack; unavailable must not appear as zero.
- [ ] Persist a scenario, `/rdev checkpoint`, normal `/reload`/logout, then inspect `!RothDevLib.lua` and the previous session's evidence/full JSON.
- [ ] Screenshots: manual and opt-in automatic requests, normal client output, visible scene, timestamp correlation, simultaneous external screenshot and failure behavior. Confirm no self-caused blocked action.
- [ ] Stress: `/rdev stress`, bounded DB/registry growth, responsive UI and stable export budgets.
- [ ] Persistence failure drill: synthetic oversized SavedVariables event, emergency compaction notice, suspended writes, `/rdev clear`, `/reload` recovery.
- [ ] Reload loop: `/rdev reloadloop`, preserved settings and no duplicate hooks/tickers.
- [ ] Final `/rdev gate`: PASS; self-taint blocked/forbidden count remains zero.

The agent workflow, retained evidence, measurement semantics and coverage limitations are defined in [docs/AGENT_DIAGNOSTICS.md](docs/AGENT_DIAGNOSTICS.md). Offline PASS is not a guarantee of complete capture, root-cause attribution, performance or real client behavior.
