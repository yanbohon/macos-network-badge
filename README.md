# 用量监控

`用量监控` is a native macOS menu bar app for monitoring one sub2api account. The technical executable name is `UsageMonitor`, with bundle identifier `com.usagemonitor.app`.

## What It Does

- Connects to one sub2api instance with Base URL, email, and password
- Calls `POST /api/v1/auth/login` and `GET /api/v1/subscriptions`
- Stores password and token data in macOS Keychain under `com.usagemonitor.app.sub2api`
- Stores Base URL, email, selected subscription, and refresh interval in UserDefaults
- Shows the selected active subscription's daily usage in the menu bar, for example `$84.04/$500.00`
- Shows account balance, refresh status, active subscription details, weekly/monthly usage, expiry, and inactive subscription count in the popover
- Preserves the last successful subscription list when refresh fails

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9+ / Xcode 15+
- A reachable sub2api instance

## Quick Start

```bash
swift build
swift run UsageMonitor
```

Open settings from the menu bar, enter the sub2api root URL, email, and password, then click `登录/验证`.

If the instance requires Cloudflare Turnstile, enter the Base URL and click `网页登录`. The app opens the real sub2api site in a `WKWebView`, lets the page complete Turnstile normally, captures the successful `/api/v1/auth/login` response when available, and stores the resulting token in Keychain.

## Configuration

The Base URL must start with `http://` or `https://` and should be the instance root only. The app removes trailing slashes before saving and always builds API paths as:

- `/api/v1/auth/login`
- `/api/v1/subscriptions`

Refresh intervals are limited to 1, 5, 15, 30, and 60 minutes. The default is 5 minutes.

## Build for Distribution

```bash
./scripts/build-app.sh
./scripts/create-dmg.sh
```

Outputs:

- `build/UsageMonitor.app`
- `build/UsageMonitor.dmg`

## Run Tests

```bash
swift test
```

No unit test calls a real sub2api service. API behavior is tested through an injectable request loader.

## Project Structure

```text
Sources/UsageMonitor/
├── UsageMonitorApp.swift
├── Models/Sub2APIModels.swift
├── Services/Sub2APIClient.swift
├── Services/KeychainStore.swift
├── Services/WebLoginTokenExtractor.swift
├── Monitors/SubscriptionMonitor.swift
├── Formatters/UsageFormatters.swift
└── Views/
    ├── MenuBarView.swift
    ├── SettingsView.swift
    ├── SettingsWindowController.swift
    └── WebLoginWindowController.swift

Tests/UsageMonitorTests/
├── Sub2APIClientTests.swift
├── Sub2APIModelsTests.swift
├── SubscriptionMonitorTests.swift
├── UsageFormattersTests.swift
└── WebLoginTokenExtractorTests.swift
```

## License

Apache 2.0 — see [LICENSE.txt](LICENSE.txt).
