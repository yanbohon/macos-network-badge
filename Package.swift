// swift-tools-version: 5.9
// ---------------------------------------------------------
// Package.swift — Swift Package Manager manifest
//
// This defines our macOS app as an executable Swift package.
// Open this file in Xcode to build and run the app, or use
// `swift build` from the command line.
// ---------------------------------------------------------

import PackageDescription

let package = Package(
    name: "UsageMonitor",

    // Requires macOS 13+ for SwiftUI's MenuBarExtra
    platforms: [
        .macOS(.v13)
    ],

    targets: [
        // ── Main App ──────────────────────────────────────
        .executableTarget(
            name: "UsageMonitor",
            path: "Sources/UsageMonitor"
        ),

        // ── Unit Tests ───────────────────────────────────
        .testTarget(
            name: "UsageMonitorTests",
            dependencies: ["UsageMonitor"],
            path: "Tests/UsageMonitorTests"
        ),
    ]
)
