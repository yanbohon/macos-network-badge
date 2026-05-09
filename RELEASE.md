# Releasing 用量监控

Releases are handled by the GitHub Actions release workflow.

## Branch Release

```bash
git checkout main
git pull origin main
git checkout -b release/v2.0.0
git push -u origin release/v2.0.0
```

The workflow validates the version, stamps `Resources/Info.plist`, runs `swift test`, builds `UsageMonitor.app`, creates `UsageMonitor.dmg`, publishes a GitHub Release, and opens a merge-back PR.

## Manual Dispatch

Use **Actions > Release > Run workflow**, enter a semver version, and choose draft or prerelease flags if needed.

## Published Files

- `UsageMonitor.dmg`
- `UsageMonitor.dmg.sha256`

## Local Verification

```bash
swift test
swift build
./scripts/build-app.sh
./scripts/create-dmg.sh
```
