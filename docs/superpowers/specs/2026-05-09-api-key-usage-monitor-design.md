# API Key Usage Monitor Design

## Goal

Replace the current account-login flow with a single API-key based usage monitor for the `UsageMonitor` macOS menu bar app.

The app keeps the same overall shell:

- one menu bar extra
- one settings window
- one refresh timer
- one instance at a time

The product-facing name remains `用量监控`.

## Scope

In scope:

- Remove email/password login.
- Remove web login and token extraction.
- Add `Base URL + API Key -> GET /v1/usage`.
- Show `remaining` in the menu bar.
- Show `planName`, `mode`, `subscription`, `usage`, and `model_stats` in the popover.
- Store the API key in Keychain.
- Store Base URL, refresh interval, and menu-bar decimal preference in UserDefaults.
- Keep the last successful usage snapshot in memory when refresh fails.
- Add tests for request building, response decoding, state transitions, formatting, and persistence.

Out of scope:

- Multi-account support.
- Multi-instance support.
- Login with email/password.
- Refresh-token flows.
- Notifications for thresholds.
- Graphs or historical charts.

## API Contract

The app calls:

```http
GET {baseURL}/v1/usage
Authorization: Bearer {apiKey}
```

The response is a single JSON object with the shape shown below:

- `isValid`: boolean
- `mode`: string
- `model_stats`: array
- `planName`: string
- `remaining`: number
- `subscription`: nested object with daily, weekly, monthly limits and usage plus `expires_at`
- `unit`: string
- `usage`: nested object with `today`, `total`, `average_duration_ms`, `rpm`, and `tpm`

The parser should accept the sample response exactly as provided by the user, ignore unknown fields, and decode timestamp fields with fractional seconds when present.

If `isValid` is `false`, the API key is treated as invalid even if the HTTP response was otherwise successful.

## Architecture

### Client

`Sub2APIClient` becomes a usage client with one job:

- build the `GET /v1/usage` request
- attach `Authorization: Bearer <apiKey>`
- decode the usage response
- map HTTP, network, and decoding failures into user-facing errors

### Models

`Sub2APIModels` should be replaced or narrowed to a usage-oriented model set:

- `UsageResponse`
- `UsageModelStat`
- `UsageSubscription`
- `UsageUsageSummary`
- `UsageUsageBucket`

These models should stay separate from view state so the response shape can evolve without forcing UI code to know the raw JSON keys.

### Monitor

`SubscriptionMonitor` should be renamed or refactored into a usage snapshot monitor.

Its responsibilities:

- own Base URL, API key, refresh interval, and decimal-display preference
- load and save persistent settings
- trigger periodic refreshes
- keep the last successful snapshot in memory
- expose a simple menu-bar label and popover state
- expose the current validation and refresh status

It should not contain any login-specific code after the refactor.

### Views

- `MenuBarView` shows the `remaining` value and the current status color.
- `SettingsView` contains only Base URL, API Key, refresh interval, decimal preference, validation, and manual refresh.
- `WebLoginWindowController` and `WebLoginTokenExtractor` are removed.

## Data Flow

1. On launch, load Base URL, API key, refresh interval, and decimal preference.
2. If Base URL and API key are present, try an immediate refresh.
3. On refresh, call `GET /v1/usage`.
4. If the response succeeds and `isValid == true`, store the decoded snapshot, clear the last error, and update the menu bar and popover.
5. If the response succeeds but `isValid == false`, treat the key as invalid and surface an authorization error.
6. If refresh fails after a previous success, keep showing the cached snapshot and add an error message in the popover.
7. If refresh fails before any success, show an error state instead of stale data.
8. When the refresh interval changes, reschedule the timer.

The menu bar label is a single value:

- default: `remaining`
- decimal preference off: truncate `remaining` to an integer
- if no config exists: `未配置`
- if the key is invalid and there is no cache: `未授权`
- if refresh fails and there is no cache: `刷新失败`

## Display Rules

### Menu Bar

The menu bar should focus on the account's remaining balance:

- show `remaining` as the primary value
- use the decimal preference only for the menu bar label
- do not show subscription selection, because there is only one account view now
- use the daily usage ratio from `subscription.daily_usage_usd / subscription.daily_limit_usd` only for color state

Health colors:

- normal: below 80%
- warning: 80% through 94.99%
- danger: 95% or above
- unlimited daily limit: normal

### Popover

The popover should show:

- `planName`
- `mode`
- `isValid`
- last successful refresh time
- refresh status
- `remaining`
- `subscription.daily_usage_usd`, `subscription.daily_limit_usd`
- weekly and monthly usage and limits
- `subscription.expires_at`
- `usage.today`
- `usage.total`
- `model_stats`

`model_stats` should render as a compact list in API order. Each row should surface the model name, request count, token totals, and both cost figures.

### Settings

The settings window should have three sections:

- `连接`: Base URL, API Key, validation status, and a validate/refresh button
- `显示`: menu-bar decimal toggle
- `刷新`: refresh interval and manual refresh button

The API key field should replace the current password field. No email field and no web-login button remain.

The Base URL and API key fields should persist live as the user edits:

- trim surrounding whitespace before save
- trim trailing slashes from Base URL before save
- delete the stored API key if the field is cleared

The validate button should be labeled `验证并刷新` and should exercise only the API-key flow.

## Error Handling

Local validation:

- empty Base URL blocks refresh
- invalid URL scheme blocks refresh
- empty API key blocks refresh

Network and API errors:

- non-2xx HTTP responses map to the returned message when present
- 401 and 403 surface as authorization failure
- `isValid == false` surfaces as authorization failure
- invalid or unexpected JSON surfaces as `响应格式不符合预期`
- timeouts, offline errors, and DNS failures surface as `网络请求失败`

State preservation:

- never clear the cached successful snapshot on refresh failure
- do not automatically delete the API key on a transient refresh failure
- overwrite the stored API key when the user enters a new one
- remove old password, access token, refresh token, and expiry entries during migration

## Persistence

UserDefaults:

- Base URL
- refresh interval
- menu-bar decimal preference

Keychain:

- API key

The app should stop using the old password and token storage keys after migration.

## Testing

Unit tests should cover:

- request path and `Authorization: Bearer` header
- response decoding for the sample JSON
- `isValid == false` handling
- menu-bar formatting for `remaining`
- decimal truncation behavior
- health-state thresholds
- refresh failure with and without cached data
- invalid API key messaging
- Keychain read/write/delete behavior for the API key

The tests do not need to hit a live service.

## Migration

Update or remove the current login-specific code paths:

- rename or refactor `SubscriptionMonitor` into a usage snapshot monitor
- replace login and subscription client methods with a single usage fetch method
- replace login and subscription DTOs with usage DTOs
- remove `WebLoginWindowController.swift`
- remove `WebLoginTokenExtractor.swift`
- remove email/password fields from `SettingsView.swift`
- remove subscription picker logic from the settings UI
- update `MenuBarView.swift` to show the remaining balance and usage summary
- update README, INSTALL, RELEASE, and CHANGELOG to describe the API-key flow

## Acceptance Criteria

The change is done when:

- the app can be configured with Base URL and API key only
- the app refreshes `GET /v1/usage` successfully
- the menu bar shows `remaining`
- the popover shows the usage snapshot and model stats
- the app preserves the last successful snapshot across failed refreshes during the same run
- no login or web-login UI remains
