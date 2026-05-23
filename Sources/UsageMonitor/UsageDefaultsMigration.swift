import Foundation

enum UsageDefaultsMigration {
    static let legacyBundleIdentifier = "com.usagemonitor.app"
    static let migrationMarkerKey = "sub2api.migratedDefaultsFromComUsageMonitorApp"

    private static let migratedKeys = [
        UsageSnapshotMonitor.DefaultsKey.baseURL,
        UsageSnapshotMonitor.DefaultsKey.email,
        UsageSnapshotMonitor.DefaultsKey.selectedSubscriptionID,
        UsageSnapshotMonitor.DefaultsKey.apiKey,
        UsageSnapshotMonitor.DefaultsKey.showMenuBarDecimals,
        UsageSnapshotMonitor.DefaultsKey.hideMenuBarSymbols,
        UsageSnapshotMonitor.DefaultsKey.legacyHideSingleKeySymbol,
        UsageSnapshotMonitor.DefaultsKey.refreshIntervalSeconds,
        UsageSnapshotMonitor.DefaultsKey.serviceStatusLayoutMode,
        UsageSnapshotMonitor.DefaultsKey.snapshotCache,
        UsageSnapshotMonitor.DefaultsKey.usageKeys,
    ]

    static func migrateStandardDefaultsFromLegacyBundleIfNeeded() {
        guard Bundle.main.bundleIdentifier != legacyBundleIdentifier else { return }
        guard let legacyDefaults = UserDefaults(suiteName: legacyBundleIdentifier) else { return }

        migrateIfNeeded(from: legacyDefaults, to: .standard)
    }

    static func migrateIfNeeded(from legacyDefaults: UserDefaults, to currentDefaults: UserDefaults) {
        guard currentDefaults.object(forKey: migrationMarkerKey) == nil else { return }

        for key in migratedKeys where currentDefaults.object(forKey: key) == nil {
            if let value = legacyDefaults.object(forKey: key) {
                currentDefaults.set(value, forKey: key)
            }
        }

        currentDefaults.set(true, forKey: migrationMarkerKey)
    }
}
