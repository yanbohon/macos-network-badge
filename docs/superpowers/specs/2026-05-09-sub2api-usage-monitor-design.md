# sub2api Usage Monitor Design

## Goal

Turn the existing macOS menu bar network monitor into a dedicated sub2api subscription usage monitor.

The product name shown to users is `用量监控`. The technical app name is `UsageMonitor`, and the bundle identifier is `com.usagemonitor.app`.

## Scope

This is a product-level refactor, not an additive mode. The app will become a pure sub2api usage monitor.

In scope:

- Rename the Swift package, executable target, source tree, tests, app bundle metadata, and build scripts to `UsageMonitor`.
- Show `用量监控` as the app display name, settings title, and primary UI title.
- Connect to one sub2api instance and one user account.
- Let the user configure Base URL, email, password, refresh interval, and the subscription shown in the menu bar.
- Store sensitive values in macOS Keychain and ordinary preferences in UserDefaults.
- Show selected subscription daily usage in the menu bar.
- Show account balance and active subscription details in the popover.
- Preserve last successful subscription data when refresh fails.
- Add tests for parsing, filtering, formatting, threshold state, and API-client behavior.

Out of scope:

- Keeping network latency, GPS tracking, maps, data browser, predictive alerts, or update-checker features.
- Mode switching between network monitoring and usage monitoring.
- Multi-account or multi-instance support.
- Guessing or using a refresh-token endpoint.
- System notifications for quota thresholds in the first version.

## User Flow

1. User opens settings.
2. User enters a sub2api instance root URL, email, and password.
3. User clicks `登录/验证`.
4. App validates the Base URL locally, then calls `POST /api/v1/auth/login`.
5. On success, the app stores credentials and token data, then calls `GET /api/v1/subscriptions`.
6. Settings shows active subscriptions and lets the user choose the one displayed in the menu bar.
7. The menu bar shows only the selected subscription's daily usage.
8. The popover shows account balance, refresh status, active subscriptions, weekly/monthly usage, expiry, and a gray inactive-subscription summary.

## Configuration

Base URL:

- Must start with `http://` or `https://`.
- Represents the instance root only.
- Trailing slashes are removed before saving.
- API paths are always built as `/api/v1/auth/login` and `/api/v1/subscriptions`.

Stored in UserDefaults:

- Base URL.
- Email.
- Selected menu-bar subscription ID.
- Refresh interval.

Stored in macOS Keychain under service `com.usagemonitor.app.sub2api`:

- Password.
- Access token.
- Refresh token, if present.
- Access-token expiry timestamp, derived from `expires_in`.

Refresh interval:

- Default: 5 minutes.
- Allowed values: 1, 5, 15, 30, and 60 minutes.

## API Contract

Login request:

```http
POST {baseURL}/api/v1/auth/login
Content-Type: application/json
```

```json
{
  "email": "user@example.com",
  "password": "password"
}
```

Login response:

```json
{
  "code": 0,
  "message": "success",
  "data": {
    "access_token": "jwt",
    "refresh_token": "rt_xxx",
    "expires_in": 86400,
    "token_type": "Bearer",
    "user": {
      "id": 2964,
      "email": "user@example.com",
      "balance": 336,
      "status": "active"
    }
  }
}
```

Login succeeds only when `code == 0` and `data.access_token` is present. The first implementation reads and stores `refresh_token`, but does not call a refresh-token endpoint.

Subscriptions request:

```http
GET {baseURL}/api/v1/subscriptions
Authorization: Bearer {accessToken}
```

Subscriptions response:

- Root object has `code`, `message`, and `data`.
- `data` is an array of subscriptions.
- Active subscriptions are records where `status == "active"`.
- Group metadata is read from `group`, including name, platform, and daily/weekly/monthly limits.

## Architecture

The new code structure will use the existing app's proven SwiftUI menu-bar pattern, but replace the domain.

Proposed files:

- `Sources/UsageMonitor/UsageMonitorApp.swift`
- `Sources/UsageMonitor/Models/Sub2APIModels.swift`
- `Sources/UsageMonitor/Services/Sub2APIClient.swift`
- `Sources/UsageMonitor/Services/KeychainStore.swift`
- `Sources/UsageMonitor/Monitors/SubscriptionMonitor.swift`
- `Sources/UsageMonitor/Formatters/UsageFormatters.swift`
- `Sources/UsageMonitor/Views/MenuBarView.swift`
- `Sources/UsageMonitor/Views/SettingsView.swift`
- `Sources/UsageMonitor/Views/SettingsWindowController.swift`
- `Tests/UsageMonitorTests/...`

Responsibilities:

- `Sub2APIClient`: Builds requests, sends login/subscriptions calls, decodes response envelopes, and maps HTTP/API errors.
- `Sub2APIModels`: Codable DTOs and normalized subscription/user types.
- `KeychainStore`: Small wrapper around Security framework read/write/delete calls.
- `SubscriptionMonitor`: `ObservableObject` that owns current config, auth state, subscriptions, selected subscription, last successful refresh, last error, and timer scheduling.
- `UsageFormatters`: Formats currency, usage ratios, remaining quota, expiry text, and quota health state.
- Views: Render state and call monitor actions. Views do not build requests directly.

## Authentication and Refresh

On launch:

- Load UserDefaults config.
- Load Keychain password/token if available.
- If config is complete and token is valid, refresh subscriptions.
- If config is complete but token is absent or expired, log in with saved email/password, then refresh.

On manual login:

- Validate Base URL, email, and password.
- Call login.
- Store password and token data in Keychain.
- Refresh subscriptions.
- Update account balance from the login response.

On subscriptions refresh:

- Use the current access token.
- If token is locally expired, log in first.
- If the request returns 401 or 403, log in once and retry the subscriptions request once.
- If the retry fails, keep the last successful data and set an error state.

Refresh-token handling:

- Save `refresh_token` when provided.
- Do not call any refresh endpoint in the first version.
- Token recovery uses saved email/password because that flow is confirmed by the provided API contract.

## Display Rules

Menu bar:

- Shows only the selected subscription.
- Format: `$84.04/$500.00`.
- If `daily_limit_usd == 0`, show `$84.04/∞`.
- If no configuration exists, show `未配置`.
- If credentials are missing or invalid, show `未登录`.
- If there are no active subscriptions, show `无套餐`.
- If refresh failed and there is no cached successful data, show `刷新失败`.
- If refresh failed but cached data exists, keep showing cached data and color/status reflect the cached usage plus an error indicator in the popover.

Quota health colors:

- Normal: usage below 80%.
- Warning: usage from 80% through 94.99%.
- Danger: usage at or above 95%.
- Unlimited daily limit: normal state, no percentage.

Popover:

- Header: user email, account balance, refresh state, last successful refresh time, manual refresh button, settings button, quit button.
- Body: active subscription rows with group name, platform, daily usage/limit, remaining amount, percentage, weekly usage, monthly usage, and expiration.
- Selection: the menu-bar subscription is marked selected; selecting another active row updates UserDefaults.
- Footer: gray inactive-summary text, for example `另有 2 个非 active 套餐未显示`.
- Errors: display concise failure text without replacing the last successful subscription list.

Settings:

- Account section: Base URL, email, password, security note, `登录/验证` button, validation status.
- Display section: active subscription picker for the menu-bar subscription.
- Refresh section: interval picker and manual refresh.

## Error Handling

Local validation:

- Empty Base URL, email, or password blocks login.
- Invalid Base URL scheme blocks login.

Network/API errors:

- Login failure shows API `message` when present, otherwise HTTP status or network error.
- Subscriptions decoding failure shows `响应格式不符合预期`.
- Timeout/offline failures show `网络请求失败`.
- 401/403 triggers one automatic re-login and retry before surfacing `登录已失效，请重新验证`.

State preservation:

- Failed refreshes never clear last successful subscription data.
- Manual login failure does not delete existing valid cached data.
- Changing Base URL or email and successfully verifying replaces stored token data.

## Migration and Deletion

Remove old product code and tests for:

- Network interface detection.
- Latency measurement and sparkline.
- Location tracking and GPS2IP.
- Quality database and map views.
- Data browser.
- Prediction and notification features.
- Update checking.

Rename or update:

- `Package.swift` package name and target names.
- `Sources/NetworkBadge` to `Sources/UsageMonitor`.
- `Tests/NetworkBadgeTests` to `Tests/UsageMonitorTests`.
- Info.plist bundle identifier and display name.
- Build/install/DMG scripts.
- README, INSTALL, RELEASE, CHANGELOG, and CLAUDE docs to describe the new app.

Implementation must avoid accidentally mixing unrelated existing worktree changes into the design commit. The implementation plan should begin by inspecting current git status and deciding how to handle the already-dirty working tree.

## Testing

Unit tests:

- Login response parses `data.access_token`, `refresh_token`, `expires_in`, token type, user email, and balance.
- Subscriptions response parses active and non-active records.
- Active filtering keeps only `status == "active"` in the main list and counts inactive records for the footer.
- Selected subscription lookup handles missing or inactive IDs.
- Currency formatting always keeps two decimals.
- Daily limit `0` formats as infinity and does not produce a percentage.
- Health thresholds map to normal/warning/danger at 80% and 95%.
- API client sends the expected paths and `Authorization: Bearer ...` header using an injectable request loader.
- 401/403 refresh path retries after one login and preserves previous data on failure.

Verification commands:

```bash
swift test
swift build
```

No unit test should call a real sub2api service.

## Open Decisions Resolved

- Main implementation path: conservative product refactor into a pure `UsageMonitor`.
- Menu bar shows usage only, not latency.
- Popover fully replaces old network UI.
- Settings uses explicit `登录/验证`.
- Sensitive storage uses Keychain.
- Refresh interval defaults to 5 minutes.
- Thresholds are 80% and 95%.
- Threshold feedback is UI color only, no system notification.
- Token expiry recovery uses email/password login, not refresh-token guessing.
- Account balance is shown in the popover header.
