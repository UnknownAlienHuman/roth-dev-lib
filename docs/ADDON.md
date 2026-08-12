# !RothDevLib — addon documentation

!RothDevLib is a developer tool for World of Warcraft (12.x) that provides a single diagnostics pipeline:
- hard Lua errors (global `seterrorhandler()`),
- taints (`ADDON_ACTION_BLOCKED/FORBIDDEN`),
- Lua warnings,
- suppressed/wrapped errors (via explicit reporting and safe wrappers),
- execution context (Doctor) + breadcrumbs/metrics,
- structured exports (JSON + byte-budgeted LLM pack).

If you want reliable correlation for issues hidden behind `xpcall` wrappers, integrate your addon using LibStub and report errors explicitly.

See:
- `INTEGRATION.md` (English)
- `INTEGRATION_RU.md` (Russian)
- `ADDON_RU.md` (full user manual in Russian)
