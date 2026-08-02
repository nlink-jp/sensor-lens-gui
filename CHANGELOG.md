# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-02

First release.

### Added

- Menu-bar readout of up to three chosen readings, selected per *device ×
  metric*, so one sensor can contribute only its CO2 while another contributes
  only its temperature. Kept deliberately separate from what the CLI collects:
  collect a whole house, show two numbers. The order is yours to set — the
  leftmost is the one seen without looking.
- Clicking the bar opens those same readings with the last six hours behind
  each, a trend arrow, and the window's min and max named beneath.
- Collection while the app runs, by ticking the CLI's `now --if-stale`. It polls
  only when the stored readings have aged past the interval, so the app collects
  when it is open — roughly halving the API spend against a round-the-clock
  daemon — and costs nothing when a daemon is collecting too. No coordination
  between the two, and nothing to keep in sync.
- "Open SensorLens at login" and "Keep collecting when this app is closed",
  which together decide how much of the day is recorded. The login switch reads
  the system's own state rather than remembering its own, and says so when macOS
  is waiting for approval.
- History window: Swift Charts time series per device × metric, with gaps drawn
  as gaps rather than smoothed over, and the export→import route named as the
  only way to fill them.
- CO2 threshold tinting (elevated / high, configurable) and an optional
  notification, sent once per room per crossing rather than on every reading.
  The alert covers every collected sensor, not just the ones on the bar, and
  names the room — with several meters, "CO2 is high" is not actionable on its
  own. Which sensors may warn is a setting: a bedroom filling up matters, a
  server rack may not.
- Settings showing today's API usage against the budget and what the current
  schedule projects, since exceeding the account limit surfaces as an
  authentication failure rather than a quota error.
- The bundled, Developer ID signed CLI is the trust anchor for binary
  resolution; the environment override is DEBUG-only. Installing the app is
  enough — there is no separate CLI to install.

[0.1.0]: https://github.com/nlink-jp/sensor-lens-gui/releases/tag/v0.1.0
