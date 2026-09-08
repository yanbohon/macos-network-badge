# Changelog

All notable changes to 用量监控 are documented here.

## [0.0.8] — 2026-09-08

### Added

- **Cursor 用量** — 设置里可添加 Cursor 账号，菜单栏和弹层显示 Auto、API 和 Grok 用量。
- **Cursor Team** — Team 账号只需填写 Card Session，后台走独立接口，展示与个人账号相同。
- **Bark 通知** — 服务状态变化可通过 Bark 推送，支持自定义标题、分组和图标。

### Fixed

- **安全输入框** — 粘贴 Card Session 或 Token 后立刻显示完整掩码，不再只出现两个圆点。

## [2.0.0] — 2026-05-09

### Changed

- Replaced the account-login subscription monitor with a Base URL + API Key usage monitor.
- Menu bar now shows `subscription.daily_usage_usd` from `GET /v1/usage`.
- Popover now shows remaining balance, plan, mode, subscription limits, usage summary, and model stats from the usage snapshot.
- Settings now contains only connection, display, and refresh controls for Base URL, API Key, decimal display, and refresh interval.
- API Key storage now uses UserDefaults instead of Keychain to avoid macOS password prompts during normal use.

### Added

- API-key usage client for `GET /v1/usage` with `Authorization: Bearer <apiKey>`.
- UserDefaults-backed storage for Base URL, API Key, refresh interval, and decimal preference.
- In-memory preservation of the last successful usage snapshot when refresh fails.
- Migration cleanup for old password, access token, refresh token, token expiry, email, and selected-subscription storage.
- Unit tests for request construction, response decoding, invalid key handling, formatting, refresh state preservation, and API Key persistence.

### Removed

- Email/password login.
- Web login and WebKit token extraction.
- Subscription picker and selected-subscription flow.
- Runtime Keychain access for API Key storage.

## [1.9.0] — 2026-05-09

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
