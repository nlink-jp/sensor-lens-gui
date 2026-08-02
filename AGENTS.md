# AGENTS.md — sensor-lens-gui (SensorLens)

## What it is

macOS menu-bar SwiftUI app showing SwitchBot temperature / humidity / CO2. Thin
front end over the bundled [`sensor-lens`](../sensor-lens) Go CLI — **and, while
it runs, the collector**. macOS 14+, Apple Silicon.

## Build / test / run

```sh
make build-app   # -> signed dist/SensorLens.app (bundles the CLI)
make test        # swift test
make package     # notarize + staple + zip
swift run        # debug
```

Build the CLI first (`make build` in `../sensor-lens`) so `build-app` embeds a
fresh signed binary. The app icon is committed at `assets/AppIcon-1024.png`;
`scripts/make-appicon.swift` regenerates it but no build depends on that script.

## Layout

```
Sources/SensorLens/
  App.swift           @main, MenuBarExtra + the two Windows, MenuBarLabel
  Models.swift        Codable mirrors of the CLI's --json
  CLIRunner.swift     binary resolution, process invocation, typed queries
  SensorModel.swift   @MainActor ObservableObject: the tick, state, CO2 alerts
  Preferences.swift   menu-bar selection and thresholds (UserDefaults)
  Formatting.swift    PURE value rendering, mirroring the CLI's cmd/format.go
  PopoverView.swift   all collected devices; DeviceCard / MetricChip / ErrorBanner
  AnalysisView.swift  Swift Charts history with gaps drawn
  SettingsView.swift  menu-bar picks, collection, CO2 thresholds, about
```

## Design invariants / gotchas

- **The CLI owns everything real.** Credentials, API calls, the database,
  aggregation, staleness. This app decodes `--json`, formats and charts. Do not
  reimplement engine logic — including the staleness rule, which arrives as a
  field.

- **The bundled signed CLI is the trust anchor.** `CLIRunner.resolveBinary` puts
  it first and honours `$SENSOR_LENS_BIN` only in DEBUG. This matters more than
  in a purely local tool: the binary being launched holds a token that can
  *control* every device on the account.

- **Collection is `now --if-stale`, never a `daemonLoaded` check.** The flag
  polls only when the data has aged past the interval, so the app collects while
  it runs and costs nothing when a daemon is also collecting. Replacing it with
  "poll unless the daemon is loaded" reintroduces exactly the coordination
  problem it removes.

- **App Nap must stay opted out.** `SensorModel.start` holds a
  `beginActivity` token for the app's lifetime. Without it macOS freezes the
  timer of a windowless `LSUIElement` app — `claude-usage-lens-gui` shipped that
  bug, and here it would stop collection dead, not merely stale the display.

- **Settings is a `Window`, not a `Settings` scene.** An `LSUIElement` app cannot
  bring a `Settings` scene to the front, so its fields never take focus. Windows
  are opened through `openAppWindow`, which also calls
  `NSApp.activate(ignoringOtherApps:)` — `openWindow` alone leaves the window
  behind other apps.

- **`Format` must stay in lockstep with the CLI's `cmd/format.go`.**
  `FormattingTests` asserts the exact strings; if it fails, one side moved.

- **`prune(toCollected:)` ignores an empty device list.** A failed CLI call
  returns empty, and treating that as "nothing is collected" would wipe the
  user's menu-bar choices over a transient error.

- **A stale chip keeps its place on the bar**, marked, rather than vanishing. A
  number that disappears reads as a bug rather than as a warning.

- **Only CO2 is tinted.** Colouring every metric would make the colour mean
  nothing; CO2 is the one with a threshold worth acting on.

- Go marshals a nil slice as `null`, so `CLIRunner.decode` maps `null` to an
  empty list. "No gaps" is the good outcome, not an error to show.

## Status

Implemented and running: menu bar, popover, history with gaps, settings.
`swift test` green (27 tests). Verified live against 30 real devices, collecting
alongside the daemon without double-spending the API budget.

Not yet done: notarized release, submodule registration, org profile entry.
