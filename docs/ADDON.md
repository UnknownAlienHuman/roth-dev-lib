# !RothDevLib addon documentation

Version **1.0.0-alpha.20.0** targets WoW Retail **12.1.5** (`120105`).

RothDevLib provides one bounded diagnostics pipeline for hard Lua errors, warnings, restricted-action signals, explicitly reported failures, execution context, breadcrumbs, lightweight profiling and structured exports.

Open it with `/rdev`, the addon-compartment entry or the minimap launcher. The database groups repeated occurrences by signature, so the active count represents groups rather than raw event volume.

External values are normalized before storage: inaccessible/secret values become markers, payload tables are copied and all major buffers/exports are bounded. Blizzard presentation is hidden only through settings-aware post-hooks; foreign frame methods and event registrations remain untouched.

See:

- [Integration guide](INTEGRATION.md)
- [Russian integration guide](INTEGRATION_RU.md)
- [Russian user guide](ADDON_RU.md)
- [Runtime release gate](../todo.md)
