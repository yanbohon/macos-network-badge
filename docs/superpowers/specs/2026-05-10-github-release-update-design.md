# GitHub Release Update Design

## Goal

Add a practical update check flow to `用量监控` from the settings window.

The app lets users discover newer stable GitHub Release builds from settings, while keeping installation explicit through the existing DMG flow. There is one stable update channel.

## Context

The app already shows its version in `设置 > 关于`, and the repository already has a GitHub Actions release workflow that stamps `Resources/Info.plist`, builds `UsageMonitor.app`, creates `UsageMonitor.dmg`, generates `UsageMonitor.dmg.sha256`, and publishes a GitHub Release.

The project does not currently have an Apple Developer ID signing and notarization setup. Because of that, the first update implementation should not attempt a Sparkle-style automatic replacement install. The design should keep the update logic isolated so the download/checking surface can later migrate to Sparkle when signing and notarization are ready.

## Scope

In scope:

- Add a manual update check in `设置 > 关于`.
- Check releases from `https://api.github.com/repos/yanbohon/macos-network-badge/releases`.
- Ignore draft releases.
- Ignore prerelease releases and prerelease version tags.
- Compare the current bundled app version against GitHub release tags.
- Show inline checking, success, no-update, and failure states.
- Present an update alert when a newer release is available.
- Open the version's GitHub Release page after confirmation.
- Keep a `前往发布页面` action available after the alert is dismissed.
- Keep CI release output compatible with update checks.

Out of scope:

- Background automatic update checks.
- Silent install or automatic app replacement.
- Sparkle integration.
- Code signing, notarization, or Apple Developer certificate setup.
- A full update history screen.
- Release note rendering inside the app.

## User Experience

The about section remains compact.

Rows:

1. `版本 vX.Y.Z`
2. `检查更新` button
3. Inline update status text
4. `前往发布页面` button when a newer release exists

Behavior:

- `检查更新` starts a manual network request and changes to `检查中...` while in flight.
- The check button is disabled while checking.
- If no newer matching release exists, show `已是最新版`.
- If a newer stable release exists, show `发现新版本 vX.Y.Z` and present a confirmation alert.
- If the check fails, show a short inline error and keep the current settings intact.
- Confirming the alert opens the GitHub Release page in the browser. The user still installs from the DMG manually.

No modal alert is required for no-update or network failure states.

## Architecture

Use small units with narrow responsibilities.

### `GitHubReleaseClient`

Responsibilities:

- Request the GitHub Releases API for `yanbohon/macos-network-badge`.
- Decode only the fields needed by update checking:
  - tag name
  - draft flag
  - prerelease flag
  - published date
  - HTML release URL
  - release assets
- Find the `UsageMonitor.dmg` asset and its browser download URL.
- Optionally find the `UsageMonitor.dmg.sha256` asset for future verification display.

This type should not read app version state or UI settings.

### `AppVersion`

Responsibilities:

- Normalize versions from bundle strings and GitHub tags.
- Accept both `2.1.0` and `v2.1.0`.
- Support prerelease identifiers such as `2.1.0-beta.1`.
- Compare versions deterministically.

Version ordering should follow SemVer expectations:

- `2.1.0` is newer than `2.0.9`.
- `2.1.0` is newer than `2.1.0-beta.1`.
- prerelease ordering should be good enough for GitHub tags produced by this project.

If a release tag cannot be parsed, ignore that release instead of failing the whole check.

### `UpdateChecker`

Responsibilities:

- Read the current app version from `Bundle.main`.
- Ask `GitHubReleaseClient` for releases.
- Filter out draft releases.
- Filter out prerelease releases and prerelease version tags.
- Choose the highest release version that is newer than the current app version.
- Return a view-friendly result:
  - no update
  - update available
  - failure

This type owns update decision logic, not SwiftUI layout.

### `SettingsView`

Responsibilities:

- Render the about section controls.
- Start update checks from the button.
- Display inline status text.
- Present the update alert and open the Release page through `NSWorkspace`.

The view should not parse GitHub JSON or compare versions directly.

## GitHub Release Contract

The release workflow should continue publishing:

- `UsageMonitor.dmg`
- `UsageMonitor.dmg.sha256`

Tags use the stable `v2.1.0` form. The workflow rejects prerelease suffixes and always sets GitHub's `prerelease` flag to false. The bundled executable must be verified as arm64 before the DMG is published.

## Error Handling

Keep errors short and actionable:

- invalid response: `更新信息格式异常`
- no network or GitHub failure: `检查更新失败，请稍后重试`
- no usable release asset: keep update available because navigation targets the GitHub Release page

The app should not crash or clear settings when update checks fail.

If multiple checks are triggered quickly, only one check should be active at a time. The UI button disabled state is enough for the first version.

## Testing

Add unit tests for:

- stable version comparison.
- prerelease version comparison.
- ignoring unparseable tags.
- filtering out draft releases.
- excluding GitHub prereleases.
- excluding prerelease tags even if their GitHub metadata is incorrect.
- choosing the highest newer matching release.
- using the GitHub Release page for an available update.

Add view or state tests only where practical. Manual verification should cover the settings UI states at the default and minimum window sizes.

## Future Sparkle Migration

When Developer ID signing and notarization are available, this feature can migrate to Sparkle.

The current design keeps that future migration clean by isolating:

- release fetching in `GitHubReleaseClient`
- update eligibility in `UpdateChecker`
- UI state in `SettingsView`

At that point, the UI can keep the same `检查更新` action while replacing browser navigation with Sparkle's updater flow.

## Acceptance Criteria

The work is complete when:

- `设置 > 关于` shows the current version and update check action without a testing-channel toggle.
- Update checks ignore drafts, prereleases, and prerelease tags.
- Newer releases are detected from GitHub Releases.
- The app presents an alert and opens the GitHub Release page after confirmation.
- Ordinary failures show inline status text and do not interrupt the user.
- The release workflow publishes a verified arm64 DMG for stable versions only.
- The implementation is covered by focused unit tests for version parsing, filtering, and update selection.
