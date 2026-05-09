# 用量监控 - sub2api Usage Monitor

## Project Overview

Native macOS menu bar app written in Swift/SwiftUI. The user-facing product name is `用量监控`; the technical package and executable are `UsageMonitor`.

The app connects to one sub2api instance and one account, stores secrets in Keychain, stores ordinary preferences in UserDefaults, and displays the selected subscription's daily usage in the menu bar.

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

No test should call a real sub2api service. Use the injectable `Sub2APIRequestLoading` protocol for API-client tests.

## Architecture

- `UsageMonitorApp` — SwiftUI `MenuBarExtra` entry point
- `Sub2APIModels` — login/subscription Codable DTOs and normalized catalog helpers
- `Sub2APIClient` — login/subscriptions requests, envelope decoding, HTTP/API error mapping
- `KeychainStore` — Security framework wrapper for password/token storage
- `SubscriptionMonitor` — `ObservableObject` owning config, auth, refresh, selected subscription, cached data, and timer state
- `UsageFormatters` — currency, daily usage, remaining quota, percentage, expiry, and quota health formatting
- `MenuBarView` — popover UI
- `SettingsView` — Base URL, email, password, subscription picker, refresh controls
- `SettingsWindowController` — separate settings window lifecycle

## Storage

UserDefaults:

- Base URL
- Email
- Selected menu-bar subscription ID
- Refresh interval

Keychain service `com.usagemonitor.app.sub2api`:

- Password
- Access token
- Refresh token
- Access-token expiry timestamp

## Removed Domain

Do not reintroduce network latency monitoring, GPS tracking, maps, quality databases, data browsers, predictive alerts, update checking, or multi-account mode unless a new spec explicitly asks for it.
