# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Menu-bar readout of up to three chosen readings, selected per *device ×
  metric*, so one sensor can contribute only its CO2 while another contributes
  only its temperature. Kept deliberately separate from what the CLI collects:
  collect a whole house, show two numbers.
- Popover listing every collected device with its current values, battery, and a
  badge when a device has gone quiet.
- Collection while the app runs, by ticking the CLI's `now --if-stale`. It polls
  only when the stored readings have aged past the interval, so the app collects
  when it is open — roughly halving the API spend against a round-the-clock
  daemon — and costs nothing when a daemon is collecting too. No coordination
  between the two, and nothing to keep in sync.
- "Keep collecting when this app is closed" toggle, which installs or removes the
  background daemon.
- History window: Swift Charts time series per device × metric, with gaps drawn
  as gaps rather than smoothed over, and the export→import route named as the
  only way to fill them.
- CO2 threshold tinting (elevated / high, configurable) and an optional
  notification, sent once per room per crossing rather than on every reading.
- Settings showing today's API usage against the budget and what the current
  schedule projects, since exceeding the account limit surfaces as an
  authentication failure rather than a quota error.
- The bundled, Developer ID signed CLI is the trust anchor for binary
  resolution; the environment override is DEBUG-only.
- Sparklines in the popover for the readings on the menu bar: the last six
  hours in ten-minute buckets, with a trend arrow, scaled to the data rather
  than to zero so a two-degree move looks like a move. Read from the local
  database, so they cost no API calls.

### Fixed

- The menu bar did not re-render when the selection changed, because the
  selection lives in a separate ObservableObject that the label did not observe.
  A newly chosen chip appeared only at the next poll, up to a minute later,
  while the settings checkbox had already ticked.
- The settings list identified rows by metric name, so every device's
  temperature row shared one identity and ticking one appeared to tick them all.
- The popover shows only the readings chosen for the menu bar, not every
  collected device. Collecting a whole house is what makes the history
  complete, but reading fifteen cards is not what anyone wants from a menu-bar
  click; every collected sensor stays available in the History window.
- "Open SensorLens at login" (SMAppService). Because the app collects while it
  runs, starting it at login is what keeps the history from having a hole after
  every restart. The switch reads the system's own state rather than
  remembering its own, and says so when macOS is waiting for approval.

### Fixed (continued)

- Readings froze while the popover was open. The refresh timer was registered
  only for the default run-loop mode, which the run loop leaves while a panel is
  being tracked — so the display stopped updating for exactly as long as the
  user held it open to watch it.
- Sparklines in an open popover kept the shape they had when it appeared while
  the current value above them moved on; they now reload while it is on screen.
- The popover header shows how long ago the last reading arrived, so "is this
  still live?" is answerable by looking rather than by trusting.
- The freshness label read "0s ago" permanently. It computed the age at render
  time, and SwiftUI only redraws when an observed value changes — so it showed a
  frozen clock, the exact impression it was added to dispel. A TimelineView now
  ticks it every second.
- The menu-bar readings can be dragged into order, and removed from the same
  list. Which one sits leftmost is the one seen without looking, so it should be
  a choice rather than an accident of the order they were ticked in.
- The CO2 alert now considers every collected sensor rather than only the ones
  chosen for the menu bar. With more meters than the bar has slots, a room
  filling up was silent unless that meter happened to be on display and
  notifications were switched on. The popover names the room when the warning
  comes from a sensor that is not shown.
