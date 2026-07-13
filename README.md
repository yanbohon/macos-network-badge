# 用量监控

`用量监控` is a native macOS menu bar app for monitoring one API-key based sub2api usage endpoint. The technical executable name is `UsageMonitor`, with bundle identifier `com.usagemonitor.app`.

## What It Does

- Connects to one sub2api instance with Base URL and API Key
- Calls `GET /v1/usage` with `Authorization: Bearer <apiKey>`
- Stores Base URL, API Key, refresh interval, and menu-bar decimal preference in UserDefaults
- Shows `subscription.daily_usage_usd` in the menu bar, with an option to hide decimal places
- Shows remaining balance, plan, mode, subscription limits, usage summary, and model stats in the popover
- Preserves the last successful usage snapshot in memory when refresh fails
- Checks stable GitHub Releases daily in the background and from settings, then opens the release page when an update is available

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+ / Xcode 15+
- A reachable sub2api-compatible `GET /v1/usage` endpoint

## Quick Start

```bash
swift build
swift run UsageMonitor
```

Open settings from the menu bar, enter the sub2api root URL and API Key, then click `验证并刷新`. The display section lets you choose whether the menu bar shows decimal places.

## Configuration

The Base URL must start with `http://` or `https://` and should be the instance root only. The app removes trailing slashes before saving and always builds the usage path as:

- `/v1/usage`

Refresh intervals are limited to 1, 5, 15, 30, and 60 minutes. The default is 5 minutes.

## Build for Distribution

```bash
BUILD_ARCH=arm64 ./scripts/build-app.sh
./scripts/create-dmg.sh
```

Outputs:

- `build/UsageMonitor.app`
- `build/UsageMonitor.dmg`

GitHub Actions publishes an arm64 DMG for stable `X.Y.Z` releases. The release repository must be public for the app's unauthenticated update check to work.

## Run Tests

```bash
swift test
```

No unit test calls a real service. API behavior is tested through an injectable request loader.

## Project Structure

```text
Sources/UsageMonitor/
├── UsageMonitorApp.swift
├── Models/Sub2APIModels.swift
├── Services/Sub2APIClient.swift
├── Monitors/UsageSnapshotMonitor.swift
├── Formatters/UsageFormatters.swift
└── Views/
    ├── MenuBarView.swift
    ├── SettingsView.swift
    └── SettingsWindowController.swift

Tests/UsageMonitorTests/
├── Sub2APIClientTests.swift
├── Sub2APIModelsTests.swift
├── UsageSnapshotMonitorTests.swift
└── UsageFormattersTests.swift
```

## License

Apache 2.0 — see [LICENSE.txt](LICENSE.txt).
