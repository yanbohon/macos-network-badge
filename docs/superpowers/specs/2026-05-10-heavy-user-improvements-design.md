# Heavy User Improvements Design

## Goal

Make `用量监控` trustworthy as a daily-use macOS menu bar utility.

The first improvement pass should solve the problems that most directly affect user trust:

- the menu bar must never present stale data as if it belongs to the current configuration
- refreshes must be single-flight and deterministic
- the app should preserve useful data across restarts while making stale state explicit
- users should be warned before daily usage, balance, or subscription state becomes urgent

## User Perspective

As a heavy user, I keep this app running all day and use the menu bar number as a quick spending signal. I do not open the popover every time.

The app feels reliable only if I can answer these questions at a glance:

- Which configuration produced this number?
- When was it last successfully refreshed?
- Is the number fresh or stale?
- Am I near a limit or out of balance?
- If refresh failed, was it a network problem, an auth problem, or a server/data problem?

## Scope

In scope for the first implementation plan:

- bind cached snapshots to the Base URL and API Key that produced them
- clear or mark snapshots stale when the configuration changes
- persist the last successful snapshot to local storage
- restore the persisted snapshot on launch when it matches the current configuration
- add explicit stale/fresh state to the monitor and popover
- prevent concurrent refreshes from racing or overwriting newer state
- avoid scheduling useful refresh work until configuration is complete
- add threshold notifications or in-app alert state for daily usage, low balance, and expiry
- improve empty and stale display text so `$0.00` is not shown as a fake balance
- add tests for state transitions, persistence, single-flight refresh, and stale display rules

Out of scope for the first implementation plan:

- multi-account support
- historical charts
- model-stat filtering and sorting
- changing the `GET /v1/usage` contract
- replacing the settings UI layout
- adding a full diagnostics export system
- changing API Key storage from UserDefaults to Keychain

## Recommended Approach

Use an incremental reliability-first pass.

This keeps the current single-instance product model, but strengthens the state layer underneath it. The monitor gains a small persisted cache model, a configuration fingerprint, and a refresh coordinator. Views then render explicit states instead of inferring everything from `snapshot`, `lastError`, and `authState`.

Alternative approaches considered:

- UI-first polish: improves perceived quality but leaves stale data and refresh races unresolved.
- Analytics-first expansion: adds charts and model insights, but depends on reliable snapshot identity and persistence first.
- Full settings/security redesign: useful later, but too large for the immediate trust problem.

The reliability-first pass is the right first step because it fixes correctness before adding new surfaces.

## Architecture

### Monitor State

`UsageSnapshotMonitor` remains the owner of runtime state, refresh behavior, and persistence coordination.

Add a normalized configuration identity:

- normalized Base URL
- non-empty API Key presence
- stable API Key fingerprint, not the raw key

The fingerprint should be used only for cache matching. It must not expose the raw key in logs, UI, or persisted diagnostic text.

Add a snapshot freshness model:

- `fresh`: latest successful refresh matches the current configuration
- `stale`: restored or retained snapshot exists, but refresh failed or it is older than the freshness window
- `configurationMismatch`: snapshot exists but was produced by a previous configuration
- `empty`: no usable snapshot exists

The menu bar and popover should use this explicit freshness value rather than assuming any non-nil snapshot is current.

### Persisted Cache

Add a small persisted snapshot container stored outside the raw preferences keys:

- configuration fingerprint
- saved-at date
- last-successful-refresh date
- encoded `UsageResponse`

The cache should be written only after a successful refresh.

On launch:

1. load Base URL, API Key, refresh interval, and display preference
2. compute the current configuration fingerprint if configuration is complete
3. load the persisted cache
4. restore the snapshot only if the cache fingerprint matches the current configuration
5. mark the restored snapshot as stale until a new refresh succeeds
6. trigger launch refresh once

If configuration is incomplete or mismatched, the app should not show the cached usage as current data.

### Refresh Coordination

Refresh should become single-flight.

If a refresh is already running:

- a second manual refresh should reuse or await the in-flight work
- timer-triggered refresh should skip or join the in-flight work
- UI should stay disabled or show a consistent busy state

Each refresh should capture the configuration fingerprint at start. A response should update `snapshot`, cache, and auth state only if the fingerprint still matches when the request completes. This prevents an old response from overwriting state after the user changes Base URL or API Key.

The monitor should also guard launch refresh with `hasStarted`, because the SwiftUI menu bar label can appear more than once.

### Timer Behavior

The timer should not perform refresh attempts when configuration is incomplete.

Acceptable implementation options:

- schedule the timer only when Base URL and API Key are present
- keep the timer scheduled but make the callback return before touching validation or network code

Prefer scheduling only when complete because it keeps test expectations and runtime behavior easier to reason about.

When configuration becomes complete, schedule the timer. When configuration becomes incomplete, invalidate it.

## User Experience

### Menu Bar

The menu bar should remain compact and cost-focused.

Display rules:

- fresh snapshot: show daily usage as today
- stale matching snapshot: show daily usage but use a stale indicator in the popover; menu bar color should not imply the refresh succeeded
- configuration mismatch: show `未验证` or `未配置`, not the old cost
- no snapshot with configured credentials: show `未刷新`
- unauthorized without usable cache: show `未授权`
- failed without usable cache: show `刷新失败`

The exact menu bar text should remain short enough for menu bar use.

### Popover

The popover should make state explicit.

Header changes:

- show `余额 --` when there is no current or matching cached snapshot
- show last successful refresh time
- show stale state text when the data is restored from disk or refresh failed
- show concise failure reason below the status line

Data sections should render only when the snapshot is usable for the current configuration. A stale matching snapshot is usable, but it must be labeled as stale.

### Settings

Settings should keep the current layout and draft-and-commit flow.

Behavior changes:

- changing Base URL or API Key clears validation success state
- committing a changed configuration marks existing snapshot as configuration-mismatched
- clearing API Key removes the saved key and stops refresh scheduling
- validating with a new configuration replaces the cache only after success

No new settings panel is required for this pass.

## Threshold Alerts

Add a lightweight alert model before adding full notification preferences.

Initial alert conditions:

- daily usage reaches 80 percent of daily limit
- daily usage reaches 95 percent of daily limit
- remaining balance is at or below a conservative low-balance threshold
- subscription is expired or expires soon

The monitor should track the last alert state so the same threshold is not repeatedly announced on every refresh.

For the first implementation, alerts can appear in the popover and optionally use macOS notifications if permission is already available or easy to request. If notification permission introduces too much UI or entitlement work, keep system notifications out of the first implementation and still expose alert state in the menu bar/popover.

## Error Handling

Keep the existing concise user messages, but preserve structured error type internally.

State rules:

- auth errors set unauthorized state
- network errors keep matching cached data and mark it stale
- decoding errors keep matching cached data and show response-format failure
- local validation errors do not touch cache
- configuration changes do not delete the previous cache immediately, but they must prevent mismatched cache from displaying as current

HTTP 401 and 403 can still show `API Key 无效，请检查后重试`, but the monitor should retain the underlying category so tests and UI can distinguish auth from network/server failures.

## File Boundaries

Likely files for the implementation plan:

- `Sources/UsageMonitor/Monitors/UsageSnapshotMonitor.swift`: configuration identity, freshness state, single-flight refresh, timer gating
- `Sources/UsageMonitor/Models/Sub2APIModels.swift`: add `Encodable` where needed for persisted cache
- `Sources/UsageMonitor/Views/MenuBarView.swift`: stale/empty display rendering
- `Sources/UsageMonitor/Views/SettingsView.swift`: validation status reset and changed-configuration behavior
- `Sources/UsageMonitor/Formatters/UsageFormatters.swift`: empty-state balance and stale/status text helpers if needed
- `Tests/UsageMonitorTests/UsageSnapshotMonitorTests.swift`: core state tests
- `Tests/UsageMonitorTests/UsageFormattersTests.swift`: display text tests

If the persisted cache logic grows beyond a few functions, extract a small cache store type instead of expanding the monitor further.

## Testing

Add unit tests for:

- changing API Key after a successful refresh stops showing the old menu bar value
- changing Base URL after a successful refresh stops showing the old menu bar value
- clearing API Key removes stored key and invalidates refresh scheduling
- successful refresh writes a persisted snapshot cache
- launch restores matching persisted cache as stale-but-usable
- launch ignores mismatched persisted cache
- refresh failure after cache keeps matching stale data visible
- concurrent manual and timer refreshes do not produce duplicate updates or stale overwrites
- a response from an old configuration is ignored if settings changed during the request
- no fake `$0.00` balance is shown without a usable snapshot
- threshold state changes only once per threshold crossing

Existing tests should continue to pass:

- request construction
- flexible response decoding
- menu-bar decimal formatting
- local validation messages
- settings rendering

## Acceptance Criteria

The work is complete when:

- the app never shows a previous configuration's usage as current data
- the app can restart offline and still show the last matching snapshot as stale data
- the popover clearly distinguishes fresh, stale, failed, unauthorized, and unconfigured states
- refreshes are single-flight and old responses cannot overwrite newer configuration state
- incomplete configuration does not keep producing timer refresh attempts
- threshold warning state exists and does not repeat noisily every refresh
- `swift test` passes

## Deferred Improvements

After the reliability pass, the next useful improvements are:

- Launch at Login setting with `SMAppService`
- optional Keychain storage for API Key
- model usage sorting and Top N display
- historical daily trend storage and a compact sparkline
- copyable diagnostics for support
- better parsing for common server error fields such as `msg`, `detail`, and nested `error.message`
- Base URL paste correction for values that already include `/v1/usage`
