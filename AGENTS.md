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
  Sparkline.swift     PURE y-domain and trend arithmetic for the popover charts
  PopoverView.swift   menu-bar picks with sparklines, then all collected devices
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

- **`history` and `historyBuckets` are separate calls, not one with a flag.**
  `--bucket` makes the CLI emit buckets — `{start,count,min,max,avg}` — which
  cannot decode as readings. An optional argument that silently changes the
  return shape is a decode failure waiting to happen.

- **Sparklines load when the popover opens**, not on every poll. They cost no
  API calls (local database only) but do spawn a process per series, and nobody
  is looking while the popover is shut.

- **The trend arrow describes the drawn line, not an absolute magnitude.** The
  sparkline is autoscaled, so a monotonic climb is drawn as clearly rising
  however small it is; an arrow saying "steady" beside it would contradict the
  picture. `Sparkline.domain`'s floor on padding is what still makes sensor
  wobble read as steady.

## Status

Implemented and running: menu bar, popover, history with gaps, settings.
`swift test` green (31 tests). Verified live against 30 real devices, collecting
alongside the daemon without double-spending the API budget.

Not yet done: notarized release, submodule registration, org profile entry.

## SwiftUI identity: a bug worth not repeating

The settings list identified its rows with `ForEach(metrics, id: \.self)`. A
`List`'s `ForEach` ids must be unique across the **whole list**, not within a
`Section` — and `"temperature_c"` appears under every sensor. SwiftUI therefore
treated every device's temperature row as one row, and checking one appeared to
check them all. The store was never wrong; only the view's identity was.

Row identity now carries the device (`MenuBarSettings.rows(for:)` returns
`MenuBarItem`s, whose `id` is `deviceID/metric`), and
`MenuBarSettingsTests.testRowIdentitiesAreUniqueAcrossDevices` guards it.

Related: build a `Toggle`'s `Binding` to read the store in its getter rather
than capturing a snapshot at view-build time.

## Observation: the selection lives in a second ObservableObject

`Preferences` is separate from `SensorModel`, so a view that observes only the
model does **not** re-render when the selection changes. `MenuBarLabel` therefore
takes both. Without that, choosing a new chip did nothing visible until the next
60-second poll happened to invalidate the model — which reads as "selecting it
did not work", while the settings checkbox (observing `Preferences` through
`@EnvironmentObject`) updated instantly.

Any new view outside the popover's environment that renders a preference must
observe `Preferences` explicitly.

## MenuBarExtra sizes to its content — so ScrollView collapses

A `ScrollView` is infinitely flexible, so its **ideal** height is zero, and a
`MenuBarExtra(style: .window)` sizes itself to its content's ideal size. The
popover therefore rendered as a header sitting directly on a footer, with the
entire device list missing. `.frame(maxHeight:)` does not help: it caps a height
nothing ever requested.

`PopoverLayout.contentHeight` estimates a real height from the row counts, and
`PopoverLayoutTests.testNeverCollapses` guards it. The estimate need not be
exact — the view scrolls — only close enough that a short list is not trailed by
empty space and a long one does not run off the screen.

The same applies to any greedy view (`Spacer`, `GeometryReader`, `List`) placed
in a menu-bar window: give it a definite height or it contributes nothing.
