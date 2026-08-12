# !RothDevLib

An alpha development-feedback library for World of Warcraft addons. It captures errors and warnings, retains diagnostic context and breadcrumbs, and provides structured exports for triage.

## Installation

Copy the `!RothDevLib` directory into `World of Warcraft/_retail_/Interface/AddOns/`, then restart the client or use `/reload`. The TOC vendors its LibStub, callback, data-broker, and minimap-button libraries.

## Compatibility and data

- Interface: `120001`, `120005`
- Version: `1.0.0-alpha.19.0`
- Saved variables: `RothDevLibDB`

## Usage

The addon exposes a main diagnostic UI, slash-command tooling under `/rdev`, an addon-compartment entry, and a minimap launcher. Its integration API and examples are documented in [docs/INTEGRATION.md](docs/INTEGRATION.md).

## Development status

Alpha. The implementation roadmap is complete through the release-gate tooling; the remaining work is to run the in-game matrix (standalone and BugGrabber, combat, stress flood, and reload loops) and confirm zero self-taint blocked/forbidden events. See [todo.md](todo.md).

## Developer documentation

- [Architecture](ARCHITECTURE.md)
- [Code index](CODE_INDEX.md)
- [Code graph](CODE_GRAPH.md)

## License

Licensed under the [MIT License](LICENSE). Bundled third-party components remain under their own notices.
