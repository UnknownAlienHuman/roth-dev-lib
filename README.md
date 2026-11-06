# !RothDevLib

A bounded diagnostics library and UI for World of Warcraft addon development. It captures hard Lua errors, warnings, restricted-action signals, explicitly reported failures, execution context, breadcrumbs and lightweight performance metrics.

## Compatibility

- Retail target: **12.1.5**
- Interface: **120105**
- Version: **1.0.0-alpha.20.0**
- Saved variables: `RothDevLibDB`

The implementation is aligned with Blizzard UI source build **12.1.5 (70783)**. Static focused tests pass; the in-game validation matrix remains required before release.

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

- External diagnostic values cross a bounded ordinary-value boundary before persistence or callbacks.
- Secret/inaccessible values become explicit markers; foreign tables are copied, not retained by reference.
- SavedVariables are available during file loading, but player/session initialization is gated until `PLAYER_LOGIN`.
- File-load errors use a bounded boot queue and are assigned to the real session only when committed.
- Blizzard UI is observed or post-hooked. RothDevLib does not replace Blizzard frame methods, mutate popup definitions, or unregister events owned by other frames.
- Exports, breadcrumb rings, strings and table traversal are bounded.

## Validation

Offline checks live in `tests/`. Runtime gates are `/rdev gate`, `/rdev stress`, `/rdev reloadloop`, and the matrix in [todo.md](todo.md).

## License

MIT. Bundled third-party libraries retain their own notices.
