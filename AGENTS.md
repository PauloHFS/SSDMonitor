# SSDMonitor Agent Guidelines

macOS menu bar status item application for monitoring external SSD health, volume status, S.M.A.R.T. telemetry, active open file processes, and performing safe ejections.

## Architecture

- **`SSDMonitorApp` / `AppDelegate`**: Entry point (`@main`), sets activation policy to `.accessory` (no Dock icon).
- **`StatusBarController`** (`@MainActor`): Manages the native AppKit `NSStatusItem` in the menu bar and toggles the SwiftUI `NSPopover` containing `MenuView`.
- **`DiskWatcher`** (`@MainActor`, `ObservableObject`): Central state manager for mount status, polling timer (5s default), temperature, S.M.A.R.T. health, storage capacity, and active processes.
- **`TelemetryService`** (`actor`): Asynchronous background executor for external CLI subprocesses (`smartctl`, `lsof`, `diskutil`).
- **`MenuView`** (SwiftUI View): Card-based user interface displaying Temperature & S.M.A.R.T. status, Storage breakdown, Active Blocking Processes, and Safe Eject controls.

## Development & Verification

### Build & Test Commands

Requires macOS with Xcode. Ensure active developer directory points to Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

- **Build**:
  ```bash
  xcodebuild -project SSDMonitor.xcodeproj -scheme SSDMonitor -destination 'platform=macOS' build
  ```

- **Run Unit Tests**:
  ```bash
  xcodebuild -project SSDMonitor.xcodeproj -scheme SSDMonitor -destination 'platform=macOS' test
  ```

## Coding Conventions

- **Concurrency**: Respect Swift Concurrency model — UI and state binding in `@MainActor`, background process execution inside `TelemetryService` (`actor`).
- **Logging**: Use native logging helpers `logWatcher(_:isError:)` and `logTelemetry(_:isError:)` for structured stdout diagnostics.
- **Domain Alignment**: Align symbols, parameters, and comments with terms defined in `CONTEXT.md` (*Target Volume*, *Telemetry*, *Blocking Process*, *Safe Ejection*).

## Agent skills

### Issue tracker

Issues and specs for this repo live as GitHub issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Triage roles are mapped 1:1 to canonical label strings (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout (`CONTEXT.md` + `docs/adr/` at repo root). See `docs/agents/domain.md`.
