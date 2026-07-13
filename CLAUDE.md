# 用量监控 - sub2api Usage Monitor

## Project Overview

Native macOS menu bar app written in Swift/SwiftUI. The user-facing product name is `用量监控`; the technical package and executable are `UsageMonitor`.

The app connects to one sub2api-compatible usage endpoint, stores Base URL, API Key, and ordinary preferences in UserDefaults, and displays `subscription.daily_usage_usd` from `GET /v1/usage` in the menu bar.

## Build Commands

```bash
swift build
swift build -c release
swift run UsageMonitor
./scripts/build-app.sh
./scripts/create-dmg.sh
```

## Test Commands

```bash
swift test
swift test --filter UsageMonitorTests.Sub2APIClientTests
```

No test should call a real service. Use the injectable `Sub2APIRequestLoading` protocol for API-client tests.

## Architecture

- `UsageMonitorApp` — SwiftUI `MenuBarExtra` entry point
- `Sub2APIModels` — usage response DTOs for `UsageResponse`, `UsageSubscription`, usage buckets, and model stats
- `Sub2APIClient` — `GET /v1/usage` request construction, response decoding, HTTP/network/API error mapping
- `UsageSnapshotMonitor` — `ObservableObject` in `Monitors/UsageSnapshotMonitor.swift` owning config, validation, refresh, cached snapshot, error state, and timer state
- `ServiceStatusMonitor` — independent status refresh state plus the persisted model used by the menu-bar status cells
- `BackgroundUpdateCoordinator` — daily GitHub Release checks, reminder throttling, and native update alerts
- `UsageFormatters` — currency, menu-bar daily usage, balance, usage limits, bucket text, expiry, and quota health formatting
- `MenuBarView` — popover UI for service status, per-key balance and configuration, plan, subscription limits, and alerts
- `SettingsView` — connection, display, menu-bar status model, refresh, validation, and update controls
- `SettingsWindowController` — separate settings window lifecycle

## Storage

UserDefaults:

- Base URL
- API Key
- Refresh interval
- Menu-bar decimal display toggle
- Menu-bar service-status model
- Last background update check and update reminder state

Old email and selected-subscription UserDefaults keys are removed during migration and should not be used by new behavior. Do not read or write Keychain in normal app runtime.

## Removed Domain

Do not reintroduce account login, web login, subscription selection, network latency monitoring, GPS tracking, maps, quality databases, data browsers, predictive alerts, or multi-account mode unless a new spec explicitly asks for it.
