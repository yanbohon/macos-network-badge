# GitHub Release Update Design

## Goal

Add a practical update check flow to `用量监控` from the settings window.

The first version should let users discover and download newer GitHub Release builds from inside the app, while keeping installation explicit through the existing DMG flow. It should also let users opt into prerelease builds through a `包含测试版更新` setting.

## Context

The app already shows its version in `设置 > 关于`, and the repository already has a GitHub Actions release workflow that stamps `Resources/Info.plist`, builds `UsageMonitor.app`, creates `UsageMonitor.dmg`, generates `UsageMonitor.dmg.sha256`, and publishes a GitHub Release.

The project does not currently have an Apple Developer ID signing and notarization setup. Because of that, the first update implementation should not attempt a Sparkle-style automatic replacement install. The design should keep the update logic isolated so the download/checking surface can later migrate to Sparkle when signing and notarization are ready.

## Scope

In scope:

- Add a manual update check in `设置 > 关于`.
- Add a persisted `包含测试版更新` toggle, defaulting to off.
- Check releases from `https://api.github.com/repos/yanbohon/UsageMonitor/releases`.
- Ignore draft releases.
- Include prerelease releases only when the testing toggle is enabled.
- Compare the current bundled app version against GitHub release tags.
- Show inline checking, success, no-update, and failure states.
- Offer a `下载更新` action when a newer release is available.
- Prefer opening the `UsageMonitor.dmg` asset download URL.
- Fall back to opening the GitHub Release page if the DMG asset is missing.
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
2. `包含测试版更新` toggle
3. `检查更新` button
4. Inline update status text
5. `下载更新` button when a newer release exists

Behavior:

- `检查更新` starts a manual network request and changes to `检查中...` while in flight.
- The check button is disabled while checking.
- If no newer matching release exists, show `已是最新版`.
- If a newer stable release exists, show `发现新版本 vX.Y.Z`.
- If the newer release is prerelease, show `发现测试版 vX.Y.Z`.
- If the check fails, show a short inline error and keep the current settings intact.
- Changing `包含测试版更新` clears the previous check result so the UI does not show stale results from the old channel.
- Download opens the release asset or release page in the browser. The user still installs from the DMG manually.

No modal alert is required for ordinary success, no-update, or network failure states.

## Architecture

Use small units with narrow responsibilities.

### `GitHubReleaseClient`

Responsibilities:

- Request the GitHub Releases API for `yanbohon/UsageMonitor`.
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
- Filter out prerelease releases unless the user enabled testing updates.
- Choose the highest release version that is newer than the current app version.
- Return a view-friendly result:
  - no update
  - update available
  - failure

This type owns update decision logic, not SwiftUI layout.

### `SettingsView`

Responsibilities:

- Render the about section controls.
- Persist the testing update toggle in `UserDefaults`.
- Start update checks from the button.
- Display inline status text.
- Open the DMG asset URL or Release page through `NSWorkspace`.

The view should not parse GitHub JSON or compare versions directly.

## GitHub Release Contract

The release workflow should continue publishing:

- `UsageMonitor.dmg`
- `UsageMonitor.dmg.sha256`

Tags should use:

- stable releases: `v2.1.0`
- testing releases: `v2.1.0-beta.1`

GitHub prerelease metadata is the source of truth for the testing channel. A `-beta` tag should also be marked as prerelease in the workflow run.

The current release workflow already supports the `prerelease` input during manual dispatch. The implementation plan should verify whether the branch release path needs a convention for prerelease branches or whether prereleases should be manual-dispatch only.

## Error Handling

Keep errors short and actionable:

- invalid response: `更新信息格式异常`
- no network or GitHub failure: `检查更新失败，请稍后重试`
- no usable release asset: keep update available, but make download open the GitHub Release page

The app should not crash or clear settings when update checks fail.

If multiple checks are triggered quickly, only one check should be active at a time. The UI button disabled state is enough for the first version.

## Testing

Add unit tests for:

- stable version comparison.
- prerelease version comparison.
- ignoring unparseable tags.
- filtering out draft releases.
- excluding prerelease releases when the testing toggle is off.
- including prerelease releases when the testing toggle is on.
- choosing the highest newer matching release.
- falling back to a release page when no DMG asset exists.

Add view or state tests only where practical. Manual verification should cover the settings UI states at the default and minimum window sizes.

## Future Sparkle Migration

When Developer ID signing and notarization are available, this feature can migrate to Sparkle.

The current design keeps that future migration clean by isolating:

- release fetching in `GitHubReleaseClient`
- update eligibility in `UpdateChecker`
- UI state in `SettingsView`

At that point, the UI can keep the same `检查更新` and `包含测试版更新` concepts while replacing download handling with Sparkle's updater flow.

## Acceptance Criteria

The work is complete when:

- `设置 > 关于` shows the current version, testing update toggle, and update check action.
- The testing update toggle persists across app launches.
- Stable channel checks ignore prereleases.
- Testing channel checks include prereleases.
- Newer releases are detected from GitHub Releases.
- The app opens the DMG download URL when the release asset exists.
- The app opens the GitHub Release page when the DMG asset is missing.
- Ordinary failures show inline status text and do not interrupt the user.
- The release workflow still publishes the assets the app expects.
- The implementation is covered by focused unit tests for version parsing, filtering, and update selection.
