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
