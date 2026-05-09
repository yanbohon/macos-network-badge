# Installation & Setup

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (`xcode-select --install`)
- sub2api instance URL and account credentials

## Installation Methods

### Install Script

```bash
./scripts/install.sh
```

This builds a release binary, creates `UsageMonitor.app`, and copies it to `/Applications/`.

### DMG

```bash
./scripts/create-dmg.sh
```

Open `build/UsageMonitor.dmg` and drag `UsageMonitor.app` into Applications.

### Manual

```bash
swift build -c release
./scripts/build-app.sh
cp -R build/UsageMonitor.app /Applications/
```

## Launch

```bash
open /Applications/UsageMonitor.app
```

The app runs in the menu bar. Open settings, enter the sub2api Base URL, email, and password, then click `登录/验证`.

## Uninstall

```bash
rm -rf /Applications/UsageMonitor.app
```
