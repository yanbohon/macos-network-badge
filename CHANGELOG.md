# Changelog

All notable changes to 用量监控 are documented here.

## [2.0.0] — 2026-05-09

### Changed

- Refactored the app from a network latency monitor into a dedicated sub2api subscription usage monitor.
- Renamed the Swift package, executable target, source tree, test target, app metadata, and build artifacts to `UsageMonitor`.
- Menu bar now shows selected subscription daily usage instead of network latency.
- Popover now shows account balance, refresh status, active subscriptions, weekly/monthly usage, expiry, and inactive subscription count.
- Settings now configures Base URL, email, password, selected subscription, and refresh interval.

### Added

- sub2api login and subscriptions API client with injectable request loader for tests.
- `WKWebView`网页登录 flow for Cloudflare Turnstile-protected instances.
- Keychain-backed storage for password, access token, refresh token, and token expiry.
- UserDefaults-backed storage for Base URL, email, selected subscription, and refresh interval.
- Refresh behavior that logs in when the token is absent or expired and retries once after 401/403.
- Unit tests for parsing, filtering, formatting, quota health thresholds, API request construction, and refresh retry preservation.

### Removed

- Network interface detection, latency measurement, sparkline, GPS tracking, map views, quality database, data browser, predictive alerts, notification features, and update checking.

## [1.1.0] — 2026-03-20

- Previous Network Badge release before the product refactor.
