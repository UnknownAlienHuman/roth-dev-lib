# !RothDevLib

A bounded diagnostics library and UI for World of Warcraft addon development. It captures hard Lua errors, warnings, restricted-action signals, explicitly reported failures, execution context, breadcrumbs and lightweight performance metrics.

## Compatibility

- Retail target: **12.1.5**
- Interface: **120105**
- Version: **1.0.0-alpha.20.0**
- Saved variables: `RothDevLibDB`

The implementation is aligned with Blizzard UI source build **12.1.5 (70783)**. The complete offline regression suite and first-party Lua syntax gate pass in GitHub Actions. The named-client validation matrix remains required before release.

## Installation

Copy the `!RothDevLib` directory into `World of Warcraft/_retail_/Interface/AddOns/`, then restart the client or run `/reload`.

Open the UI with `/rdev`, the addon-compartment entry, or the minimap launcher.

## Integration

Add this optional dependency:

```toc
## OptionalDeps: !RothDevLib
```

Then acquire a scoped client:

```lua
local Dev = LibStub and LibStub("RothDevLib-1.0", true)
local dev = Dev and Dev:NewAddon("MyAddon")
```

See [docs/INTEGRATION.md](docs/INTEGRATION.md) and [docs/INTEGRATION_RU.md](docs/INTEGRATION_RU.md).

## Safety model

- External diagnostic values cross a bounded ordinary-value boundary before persistence, logging, callbacks or UI.
- Secret/inaccessible values become explicit markers; foreign tables are copied, never retained by reference.
- Table traversal has depth, entry, node, string and total-byte budgets; JSON/export adds scan/output limits.
- SavedVariables are available during file loading, but player/session initialization is gated until `PLAYER_LOGIN`.
- Persistence uses compact occurrence summaries, hard group/session/ignore caps and one-shot `SAVED_VARIABLES_TOO_LARGE` recovery.
- Runtime registries—Bus, profiling, callbacks, Doctor, Locals, ChatTap, BugGrabber, Storm and Logger—have explicit saturation behavior.
- File-load errors use a bounded boot queue and receive the real session only when committed.
- Blizzard UI is observed or post-hooked. RothDevLib does not replace Blizzard frame methods, mutate popup definitions or unregister events owned by other frames.

## Validation

Offline checks live in `tests/` and run through `.github/workflows/ci.yml`. Runtime gates are `/rdev gate`, `/rdev stress`, `/rdev reloadloop`, and the matrix in [todo.md](todo.md).

## License

MIT. Bundled third-party libraries retain their own notices.
