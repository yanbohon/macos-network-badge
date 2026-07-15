#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if [[ $# -eq 0 ]]; then
    DEBUG=1 ./scripts/build-app.sh >/dev/null
    app_path="$repo_root/build/UsageMonitor.app"
else
    app_path="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
fi

binary_path="$app_path/Contents/MacOS/UsageMonitor"
if [[ ! -x "$binary_path" ]]; then
    echo "ERROR: executable not found at $binary_path"
    exit 2
fi

"$binary_path" >/dev/null 2>&1 &
pid=$!

cleanup() {
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for _ in {1..30}; do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
        echo "ERROR: UsageMonitor exited during launch"
        exit 2
    fi
    sleep 0.1
done

swift - "$pid" <<'SWIFT'
import CoreGraphics
import Foundation

guard let pid = Int(CommandLine.arguments[1]) else {
    print("ERROR: invalid process identifier")
    exit(EXIT_FAILURE)
}

let windowInfo = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] ?? []

let appWindows = windowInfo.filter { info in
    guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
          ownerPID == pid,
          let layer = info[kCGWindowLayer as String] as? Int,
          layer == 0,
          let bounds = info[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double else {
        return false
    }

    return width > 100 && height > 100
}

if appWindows.isEmpty {
    print("PASS: app launch created no visible ordinary window")
    exit(EXIT_SUCCESS)
}

for info in appWindows {
    let title = info[kCGWindowName as String] as? String ?? "<untitled>"
    let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print("VISIBLE WINDOW: title=\(title) bounds=\(bounds)")
}
print("FAIL: app launch exposed a visible ordinary window")
exit(EXIT_FAILURE)
SWIFT
