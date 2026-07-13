# Releasing 用量监控

Releases are handled by the GitHub Actions release workflow.

Current releases package the API-key usage monitor flow: users configure Base URL and API Key only, and the app refreshes `GET /v1/usage`.

## Branch Release

```bash
git checkout main
git pull origin main
git checkout -b release/v2.0.0
git push -u origin release/v2.0.0
```

The workflow accepts stable `X.Y.Z` versions only. It stamps `Resources/Info.plist`, runs `swift test`, builds and verifies an arm64 `UsageMonitor.app`, creates `UsageMonitor.dmg`, publishes a GitHub Release, and opens a merge-back PR.

Prerelease suffixes such as `-beta.1` are rejected. The app has one update channel and ignores every draft or prerelease GitHub Release.

## Manual Dispatch

Use **Actions > Release > Run workflow**, enter a stable semver version, and optionally create the release as a draft.

## Update Check Requirement

The app checks `yanbohon/macos-network-badge` without asking users for GitHub credentials. This repository must be public before distributing the app; GitHub does not expose private repository releases to unauthenticated clients. When an update is available, the app opens that version's GitHub Release page.

## Published Files

- `UsageMonitor.dmg`
- `UsageMonitor.dmg.sha256`

The app inside `UsageMonitor.dmg` contains an arm64 executable for Apple silicon Macs.

## Local Verification

```bash
swift test
swift build
BUILD_ARCH=arm64 ./scripts/build-app.sh
./scripts/create-dmg.sh
```
