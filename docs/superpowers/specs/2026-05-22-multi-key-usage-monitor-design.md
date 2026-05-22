# Multi-Key Usage Monitor Design

## Goal

Add multi-key usage monitoring to `用量监控` while keeping the menu bar compact and making each key easy to identify.

The feature should:

- monitor multiple sub2api API keys in one app
- let keys inherit a global Base URL or use an independent Base URL
- show every key in the menu bar, arranged as two keys per column
- keep service health visible with the vertical service-status indicator as the default and only menu-bar service layout
- show per-key detailed usage in the popover through left/right paging
- let each key choose an SF Symbols icon for quick menu-bar identification

## User Perspective

As a heavy user with multiple API keys, I want to see all key usage at a glance without opening separate tools. I should be able to tell keys apart by icon, see the current daily usage for every key in the menu bar, and open the popover to inspect one key's detailed data without losing the global service-status view.

## Scope

In scope:

- replace the single-key usage state with a multi-key usage manager
- add per-key settings: name, SF Symbol name, API Key, Base URL mode, optional Base URL override
- keep global settings for default Base URL, refresh interval, decimal display, and app/update controls
- migrate old single-key settings into the first key
- migrate or preserve existing cached usage data for the first key when possible
- remove the horizontal 5-cell service-status menu-bar layout from user-facing settings
- make vertical service-status cells the default and only active menu-bar service-status layout
- render all keys in the menu bar as `icon + daily usage`, two keys per column
- add popover paging below the service-status section for per-key detail
- keep each key's refresh status, cache, alerts, and errors independent
- add focused tests for migration, per-key state, layout helpers, and paging selection

Out of scope:

- storing API keys in Keychain
- grouping keys into accounts or workspaces
- syncing settings between devices
- editable service-status API URL
- charts or long-term per-key analytics
- macOS notifications for per-key threshold alerts
- hiding some keys from the menu bar

## Decisions

Use one top-level multi-key monitor.

`UsageSnapshotMonitor` should become the owner of global usage settings plus a list of per-key usage entries. Each key entry owns its own configuration, snapshot, last success time, error state, freshness state, cache identity, and threshold alert state. The app should not create one independent `UsageSnapshotMonitor` object per key.

Alternatives considered:

- one monitor per key with a parent coordinator: stronger isolation, but too much object and refresh coordination for this menu-bar app
- duplicating single-key logic in the UI layer: smaller first diff, but it would spread refresh, cache, and error behavior across views

The top-level multi-key monitor keeps the state source clear and testable while preserving the current app shape.

## Data Model

Global usage settings:

- `defaultBaseURL`
- `refreshIntervalSeconds`
- `showMenuBarDecimals`
- service-status menu-bar layout, migrated to vertical

Per-key configuration:

- stable `id`
- user-facing `name`
- `symbolName`, using SF Symbols
- raw `apiKey`
- `baseURLMode`: inherit global Base URL or use independent Base URL
- optional `baseURLOverride`
- display order from the stored array order

Per-key runtime state:

- latest `UsageResponse`
- last successful refresh date
- last error text
- refresh failure kind
- freshness state
- auth state
- threshold alert state
- in-flight refresh task

The key `id` is the stable identity for cached snapshots, popover paging, and list editing. Names and icons may change without invalidating usage cache.

## Persistence And Migration

Store the new multi-key configuration as encoded structured data in UserDefaults. Keep existing UserDefaults keys readable during migration.

Migration rules:

- `sub2api.baseURL` becomes the global default Base URL.
- `sub2api.apiKey` becomes the first key's API Key.
- the first migrated key uses a generated stable id, a default name such as `Key 1`, and default symbol `key.fill`.
- the first migrated key inherits the global Base URL.
- old single-key snapshot cache is moved into the first key's cache when the migrated key fingerprint matches.
- if no old API Key exists, create one empty default key so the UI always has an editable key.
- old service-status layout values migrate to vertical.
- old horizontal layout values must not be re-saved as an active choice.

The app must keep at least one key configuration. Deleting the last key is disabled.

## Base URL Rules

Each key resolves its request Base URL from:

1. the key's independent Base URL override when `baseURLMode == independent`
2. the global default Base URL when `baseURLMode == inherited`

Validation is per key:

- inherited mode requires a valid global Base URL and a non-empty API Key
- independent mode requires a valid override Base URL and a non-empty API Key
- invalid configuration marks only that key as validation failed

When the global Base URL changes:

- inherited keys are marked `configurationMismatch`
- independent keys keep their current freshness and cache state

When a key's API Key or independent Base URL changes:

- only that key is marked `configurationMismatch`

Changing a key name or SF Symbol does not invalidate usage data.

## Refresh Behavior

The app keeps the current refresh interval as a global setting.

On app launch:

1. start usage monitoring
2. start service-status monitoring
3. refresh every configured key that has enough valid configuration
4. show cached per-key data where available until the refresh finishes

Manual actions:

- popover refresh button refreshes the current paged key
- a secondary `全部刷新` action refreshes all keys
- settings `验证并刷新` validates and refreshes the currently selected key
- settings `刷新全部` refreshes every key

Refresh all should issue independent requests for all configured keys and apply each result to the matching key only. One key failure must not block other keys, clear other snapshots, or change other alert states.

Overlapping requests for the same key should be coalesced. Requests for different keys may run concurrently.

## Menu Bar Layout

The menu bar shows a compact composition:

- left side: vertical service-status indicator
- right side: per-key usage grid

Service-status layout:

- vertical 2-cell layout is the default and only active menu-bar service-status layout
- horizontal 5-cell layout is removed from settings and rendering paths
- old horizontal preference values migrate to vertical

Per-key usage grid:

- every key is shown
- each key row shows `SF Symbol icon + daily usage text`
- key name is not shown in the menu bar row
- each column contains at most two keys
- columns are filled from top to bottom, then left to right
- 1-2 keys use one column, 3-4 keys use two columns, 5-6 keys use three columns, and so on
- daily usage text uses the global decimal display preference

Per-key row text:

- fresh or stale snapshot: formatted `subscription.daily_usage_usd`
- missing config: `未配置`
- configuration mismatch: `未验证`
- unauthorized: `未授权`
- other refresh failure with no cache: `刷新失败`
- no refresh yet: `未刷新`

Symbol handling:

- configured symbols use SF Symbols by name
- invalid or empty symbol names fall back to `key.fill`
- symbol rendering should use stable dimensions so changing a symbol does not shift unrelated rows

Accessibility title:

- include the latest service-status text
- include every key name and current display text
- include stale or failure state where practical

## Popover Layout

The popover keeps global service status separate from per-key detail.

Top-level order:

1. header with app name, global refresh summary, settings, refresh, and quit controls
2. fixed `服务状态` section
3. key pager
4. current key usage detail
5. alerts for the current key

The service-status section remains global and does not change when the user changes key pages.

The key pager sits below service status:

- left arrow moves to the previous key
- right arrow moves to the next key
- center label shows the current key name and icon
- secondary text shows `第 X / N 个`
- when a key is deleted and the selected index is out of range, selection clamps to the last available key

The current key detail page shows:

- key name and configured icon
- Base URL source: inherited global URL or independent URL
- current balance
- refresh status
- last successful refresh time
- error detail when present
- plan and validity
- subscription daily, weekly, and monthly usage
- expiry text
- request summary
- model stats

Changing the page does not trigger refresh. It only changes the displayed key state.

## Settings UI

The settings window remains a single-column native macOS settings view.

Connection section:

- global default Base URL at the top
- key list below it
- selected key detail editor below the list

Key list row:

- key name
- SF Symbol preview
- Base URL mode summary
- validation or refresh state summary

Selected key editor:

- name text field
- SF Symbol name text field with fallback behavior
- secure API Key input
- segmented or picker control for Base URL mode
- independent Base URL input shown only when independent mode is selected
- delete key button when more than one key exists

Actions:

- `新增 Key` creates a key named `Key N`, with symbol `key.fill`, inherited Base URL mode, and empty API Key
- `验证并刷新` validates and refreshes the selected key
- `刷新全部` refreshes all keys

Display, refresh, and about sections remain global:

- menu-bar decimal toggle
- refresh interval picker
- manual refresh actions
- app version and update controls

## Error Handling

Errors are scoped to a key unless they come from the independent service-status monitor.

Per-key validation failures:

- missing or invalid Base URL
- missing API Key

Per-key refresh failures:

- unauthorized
- network
- server
- decoding
- invalid response
- unknown

Failure behavior:

- failure before any successful cache shows that key's failure display text
- failure after a successful cache keeps that key's cached data and marks it stale
- failures do not affect other keys
- threshold alerts are computed per key
- alert messages in the popover apply to the current key page only

## File Boundaries

Expected implementation boundaries:

- `UsageSnapshotMonitor` owns global settings, key list, refresh orchestration, and per-key state mutation
- new small model types should represent key config, Base URL mode, per-key state, and display rows
- `UsageSnapshotPersistence` evolves from one cache entry to keyed cache entries
- `Sub2APIClient` remains a single-request client and should not know about multiple keys
- `UsageFormatters` remains responsible for currency and usage text formatting
- `StatusBarController` owns AppKit menu-bar measurement and drawing for the multi-key grid
- `MenuBarTitleView` or helper types expose layout/accessibility helpers used by tests
- `MenuBarView` owns popover composition and key paging UI
- `SettingsDraft` becomes the normalization boundary for global Base URL and per-key editable fields
- `SettingsView` owns the settings layout and selected-key editing flow

If a file grows too dense, split pure helper models or small view subcomponents instead of adding unrelated refactors.

## Testing

Add focused tests for:

- multi-key config encoding and decoding
- old single-key settings migration
- old horizontal service-status preference migration to vertical
- per-key Base URL inheritance and override resolution
- global Base URL change invalidating inherited keys only
- API Key or override URL change invalidating only that key
- key name or symbol change preserving snapshot freshness
- refresh-all success and partial failure behavior
- one key failure preserving other key snapshots
- per-key cache save and restore
- menu-bar grid column count for 1, 2, 3, 4, and 5 keys
- menu-bar fallback symbol behavior
- accessibility title including all key display texts
- popover selected key clamping after deletion
- current key detail selection
- settings draft normalization for per-key fields

Existing tests for sub2api decoding, request construction, service-status decoding, service-status monitor behavior, update checks, and settings window rendering should continue to pass.

## Acceptance Criteria

The work is complete when:

- the app can store and monitor multiple API keys
- each key can inherit the global Base URL or use an independent Base URL
- old single-key users keep their Base URL, API Key, and cached first-key data where possible
- the menu bar shows all keys, two keys per column
- each menu-bar key row shows an SF Symbol icon and that key's daily usage or state text
- vertical service-status cells are the only active menu-bar service-status layout
- the old horizontal 5-cell layout is not selectable
- the popover keeps service status fixed above key paging
- left/right paging shows different keys' detailed usage data
- refresh failures are isolated per key
- settings provide key name, icon, API Key, and Base URL mode controls
- focused unit tests cover migration, per-key state, layout, and paging behavior
