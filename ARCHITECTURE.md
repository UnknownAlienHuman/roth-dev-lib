# Architecture

The TOC loads vendored libraries first, then core and utility code, followed by export, performance, doctor, integration, capture, UI, and finally the event bootstrap.

`Core/Events.lua` owns lifecycle dispatch. It initializes the database and subsystems after addon loading, runs login-time checks, and routes diagnostics-related events. Capture collects errors, warnings, taint signals, chat data, and breadcrumbs; Doctor validates the resulting context. Export serializes bounded reports. UI is a consumer of those services, while Integration exposes the bus/API to other addons.

Persistent configuration and captured state are owned by `RothDevLibDB` through `Core/DB.lua`. Session health, logs, and UI frame state remain module-owned.

Risks: the capture/UI boundary must keep degrading safely when a source or Blizzard widget is unavailable; combat and taint behavior require in-game validation. Test with `/rdev gate`, `/rdev stress`, `/rdev reloadloop`, and the matrix recorded in [todo.md](todo.md).
