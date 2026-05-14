# GPT-5.5 Service Status Monitor Design

## Goal

Add a compact service-status monitor to `用量监控` so the menu bar shows both the current daily spend and a quick health signal for `gpt-5.5`.

The first version should make service health visible at a glance while preserving the existing usage-monitor contract:

- the menu bar daily spend remains the primary text signal
- eight compact status cells show recent `gpt-5.5` health
- the popover shows structured `gpt-5.5` status details
- the popover also exposes the raw status API response for debugging

## User Perspective

As a daily user, I want to know whether `gpt-5.5` is currently healthy without opening a status page. If the service is slow or failing, I should see that in the menu bar before I spend time debugging my own app or API key.

When I open the popover, I want both a readable summary and enough raw API data to diagnose the latest service-status response.

## Scope

In scope for the first implementation plan:

- request `GET https://status.input.im/api/status`
- monitor only the service object where `model == "gpt-5.5"`
- refresh service status independently every 1 minute
- render the latest eight `gpt-5.5` history entries in the menu bar
- classify each status cell as green, yellow, red, or gray
- preserve the current menu bar daily-spend display
- add a `服务状态` section to the popover
- show structured `gpt-5.5` status data in the popover
- show a collapsible pretty-printed raw JSON response in the popover
- keep the status API URL fixed for this version, but centralize it behind a client/config boundary
- add unit tests for decoding, classification, refresh state, and view-facing data

Out of scope for the first implementation plan:

- making the status API URL editable in settings
- monitoring models other than `gpt-5.5`
- sending macOS notifications for status failures
- writing service-status history to persistent storage
- changing the existing `GET /v1/usage` usage-monitor contract
- changing API key storage or usage settings behavior
- adding charts or long-term uptime analytics

## Decisions

Use an independent service-status monitor.

This keeps usage data and service-status data separate:

- `UsageSnapshotMonitor` remains responsible for sub2api usage, balance, auth state, and usage refreshes.
- `ServiceStatusMonitor` owns status refreshes, current status state, raw response text, and the eight menu-bar cells.
- `StatusAPIClient` owns the fixed status endpoint and HTTP loading behavior.
- `ServiceStatusModels` owns decoding and tolerant data modeling for the status response.

Alternative approaches considered:

- Merge status logic into `UsageSnapshotMonitor`: fewer objects, but it mixes unrelated APIs and makes refresh/error state harder to reason about.
- Only show status in the popover: simpler, but it does not meet the quick-monitoring requirement for topbar status cells.
- Make the status URL configurable immediately: more flexible, but it adds settings UI and validation scope before there is a proven need.

The independent monitor is the right first version because it preserves existing usage behavior while adding a clear, testable service-status boundary.

## API Contract

The app requests:

```text
GET https://status.input.im/api/status
```

The observed response shape is:

```json
{
  "all_ok": true,
  "generated_at": 1778762578,
  "services": [
    {
      "model": "gpt-5.5",
      "uptime_pct": 81.67,
      "last": {
        "ts": 1778762557,
        "ok": true,
        "latency_ms": 1111,
        "error": null
      },
      "history": [
        {
          "ts": 1778762497,
          "ok": true,
          "latency_ms": 1103,
          "error": null
        }
      ]
    }
  ]
}
```

The decoder should support the current shape directly. It should treat optional fields defensively:

- `latency_ms` may be null on failures.
- `error` may be null on successes.
- `history` may be empty or shorter than eight entries.
- other service models may be present but are ignored by view state.

If no `gpt-5.5` service exists, the monitor should enter a failed state with a user-facing message that the model was not found.

## Architecture

### Status API Client

Add `StatusAPIClient`.

Responsibilities:

- hold the fixed endpoint in one place
- perform a `GET` request with a 20 second timeout
- decode `ServiceStatusResponse`
- return raw response data or pretty JSON text for the popover
- map HTTP, decoding, and network failures to concise user-facing errors

The status API does not use the sub2api Base URL or API Key. It should not be blocked by usage-monitor configuration.

### Service Status Monitor

Add `ServiceStatusMonitor` as a `@MainActor ObservableObject`.

Responsibilities:

- start once when the menu bar label appears
- refresh on launch and every 1 minute
- avoid overlapping status refreshes
- keep the last successful decoded response
- keep the last successful raw JSON string
- keep the last status-refresh error
- expose the selected `gpt-5.5` service
- expose the latest eight display cells
- expose last successful status refresh time

The monitor should preserve the last successful status cells after later refresh failures. It should surface that the status data is stale or failed in the popover.

### Menu Bar Integration

`UsageMonitorApp` should own both monitors:

- `UsageSnapshotMonitor` for usage data
- `ServiceStatusMonitor` for service status

`MenuBarTitleView` should continue rendering the daily-spend text, then render the eight status cells as a compact horizontal cluster to the right of the text.

The usage text remains the primary label. Status cells are secondary visual information.

### Popover Integration

`MenuBarView` should accept both monitors and add a service-status section directly after the header and before the detailed usage sections.

The section should include:

- model name: `gpt-5.5`
- current status: success, high latency, failure, missing data, or refresh failed
- uptime percentage
- latest probe time
- latest latency
- latest error text when present
- status API generated time
- last successful status refresh time
- a recent history list
- a collapsible raw JSON block

The raw JSON block can use a monospaced text view inside a bounded scroll area so large responses do not resize the popover uncontrollably.

## Status Cell Rules

The menu bar shows eight cells from the last eight `gpt-5.5.history` entries, ordered old to new.

Classification:

- green: `ok == true` and `latency_ms < 3000`
- yellow: `ok == true` and `latency_ms >= 3000`
- red: `ok == false`
- gray: missing entry or unparseable status

If the status API has never loaded, show eight gray cells.

If a later refresh fails after a successful response, keep the last eight cells but render them with reduced opacity and show the refresh error in the popover.

The first implementation should avoid text inside the cells. Tooltip/help text may describe each cell if the native SwiftUI menu-bar label supports it cleanly.

## Refresh And Error Behavior

Status refresh is independent from usage refresh.

On app launch:

1. `UsageSnapshotMonitor.start()` begins the usage refresh flow.
2. `ServiceStatusMonitor.start()` begins the status refresh flow.
3. The menu bar immediately shows usage state from the usage monitor and gray status cells until status data arrives.

On status success:

- update decoded response
- update `gpt-5.5` selected service
- update the eight cells
- update raw JSON text
- clear status-refresh error
- set last successful status refresh time

On status failure before any success:

- keep eight gray cells
- set status-refresh error
- show a failed state in the popover

On status failure after prior success:

- keep the previous response and cells
- keep previous raw JSON text
- set status-refresh error
- mark the popover state as stale or refresh failed
- do not affect usage data, balance, API key validation, or daily spend display

## User Experience

### Menu Bar

The menu bar remains compact.

Display behavior:

- primary text: existing daily usage text from `UsageSnapshotMonitor.menuBarText`
- secondary cluster: eight status cells to the right of the usage text
- color meaning: green healthy, yellow slow, red failing, gray unknown

The existing daily usage color should continue to come from usage health. Status colors should not override the daily-spend text color.

### Popover

The popover should remain utilitarian and readable.

The service-status section should be scan-friendly:

- a small title row
- a concise current-state row
- a compact eight-cell recent-history row
- key-value status metadata
- a bounded recent-history list
- a collapsed raw JSON disclosure by default

The raw JSON exists for debugging, not daily reading. It should not dominate the initial popover view.

## Testing

Add focused tests:

- `ServiceStatusModelsTests`: decode the observed response shape, null failure fields, and short history.
- `StatusAPIClientTests`: sends the fixed endpoint, handles HTTP errors, handles decoding errors, and preserves pretty raw JSON.
- `ServiceStatusMonitorTests`: start behavior, one-minute timer scheduling, no overlapping refreshes, last-eight selection, stale preservation after failure, and missing-model failure.
- `ServiceStatusCellTests` or formatter tests: green/yellow/red/gray classification including the 3000 ms threshold.
- View-facing tests where practical: `MenuBarTitleView` receives usage text plus cells without changing the usage text contract.

Existing usage-monitor tests should continue to pass without requiring status API fixtures unless they render the app-level composition.

## Acceptance Criteria

- The app still shows the current daily usage value in the menu bar.
- The menu bar also shows eight compact status cells for `gpt-5.5`.
- The eight cells use the last eight `gpt-5.5.history` entries, old to new.
- Success under 3000 ms is green.
- Success at or above 3000 ms is yellow.
- Failure is red.
- Missing data is gray.
- The status API refreshes every 1 minute independently from usage refresh.
- Opening the popover shows structured `gpt-5.5` status data.
- Opening the popover provides a collapsible pretty-printed raw JSON response.
- Status API failures do not break or alter existing usage refresh behavior.
- The status URL is fixed for this version and centralized in the status client.
