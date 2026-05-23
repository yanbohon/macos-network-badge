import XCTest
@testable import UsageMonitor

final class UsageDefaultsMigrationTests: XCTestCase {
    func testCopiesLegacyDefaultsIntoEmptyCurrentDomainWithoutOverwritingCurrentValues() {
        let legacySuite = "UsageMonitorTests.legacy.\(UUID().uuidString)"
        let currentSuite = "UsageMonitorTests.current.\(UUID().uuidString)"
        let legacyDefaults = UserDefaults(suiteName: legacySuite)!
        let currentDefaults = UserDefaults(suiteName: currentSuite)!
        defer {
            legacyDefaults.removePersistentDomain(forName: legacySuite)
            currentDefaults.removePersistentDomain(forName: currentSuite)
        }

        legacyDefaults.set("https://legacy.example.com", forKey: UsageSnapshotMonitor.DefaultsKey.baseURL)
        legacyDefaults.set("legacy_key", forKey: UsageSnapshotMonitor.DefaultsKey.apiKey)
        legacyDefaults.set(5, forKey: UsageSnapshotMonitor.DefaultsKey.refreshIntervalSeconds)
        legacyDefaults.set(true, forKey: UsageSnapshotMonitor.DefaultsKey.hideMenuBarSymbols)
        currentDefaults.set("current_key", forKey: UsageSnapshotMonitor.DefaultsKey.apiKey)

        UsageDefaultsMigration.migrateIfNeeded(from: legacyDefaults, to: currentDefaults)

        XCTAssertEqual(currentDefaults.string(forKey: UsageSnapshotMonitor.DefaultsKey.baseURL), "https://legacy.example.com")
        XCTAssertEqual(currentDefaults.string(forKey: UsageSnapshotMonitor.DefaultsKey.apiKey), "current_key")
        XCTAssertEqual(currentDefaults.integer(forKey: UsageSnapshotMonitor.DefaultsKey.refreshIntervalSeconds), 5)
        XCTAssertEqual(currentDefaults.bool(forKey: UsageSnapshotMonitor.DefaultsKey.hideMenuBarSymbols), true)
        XCTAssertEqual(currentDefaults.bool(forKey: UsageDefaultsMigration.migrationMarkerKey), true)
    }
}
