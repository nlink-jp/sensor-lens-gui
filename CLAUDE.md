# CLAUDE.md — SensorLens (GUI)

Organization rules: https://github.com/nlink-jp/.github/blob/main/CONVENTIONS.md
Workspace rules also apply (see the parent `nlink-jp/CLAUDE.md`).

## What this is

macOS menu-bar SwiftUI app showing SwitchBot temperature / humidity / CO2. Thin
front end over the bundled [`sensor-lens`](../sensor-lens) Go CLI, and the
collector while it runs. Sibling of `active-lens-gui`. macOS 14+, Apple Silicon.

## Build & test

- **`make build-app`** → signed `dist/SensorLens.app` (bundles the CLI). Never
  ship an unsigned bundle.
- `make test` / `swift test` — must pass before committing.
- Build the CLI first (`make build` in `../sensor-lens`).

## Rules of thumb

- The CLI owns credentials, API calls, storage and aggregation. This app
  decodes `--json`, formats and charts. Don't duplicate engine logic.
- Keep the **bundled** signed CLI as the trust anchor in
  `CLIRunner.resolveBinary` (env override is DEBUG-only). The token it carries
  can control every device on the account.
- Collect with `now --if-stale`, never by checking whether the daemon is loaded.
- Keep the App Nap opt-out in `SensorModel.start`; without it the timer freezes
  and collection stops.
- `Format` stays in lockstep with the CLI's `cmd/format.go` (a test enforces it).
- Docs: README.md + README.ja.md kept in sync; `docs/{en,ja}` mirror.
