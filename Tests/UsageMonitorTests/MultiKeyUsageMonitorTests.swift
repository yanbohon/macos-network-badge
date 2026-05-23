import XCTest
import Combine
@testable import UsageMonitor

@MainActor
final class MultiKeyUsageMonitorTests: XCTestCase {
    func testMultiKeyConfigurationEncodesAndDecodes() throws {
        let original = [
            UsageKeyConfiguration(
                id: "a",
                name: "Work",
                symbolName: "bolt.fill",
                symbolColorHex: "#38BDF8",
                showsInMenuBar: true,
                apiKey: "key-a",
                baseURLMode: .inherited,
                baseURLOverride: ""
            ),
            UsageKeyConfiguration(
                id: "b",
                name: "Home",
                symbolName: "house.fill",
                symbolColorHex: "#F97316",
                showsInMenuBar: false,
                apiKey: "key-b",
                baseURLMode: .independent,
                baseURLOverride: "https://home.example.com"
            ),
        ]

        let data = try JSONEncoder.sub2api.encode(original)
        let decoded = try JSONDecoder.sub2api.decode([UsageKeyConfiguration].self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testOldKeyConfigurationJSONDefaultsTopbarDisplayAndSymbolColor() throws {
        let json = """
        [
          {
            "id": "a",
            "name": "Work",
            "symbolName": "bolt.fill",
            "apiKey": "key-a",
            "baseURLMode": "inherited",
            "baseURLOverride": ""
          }
        ]
        """

        let decoded = try JSONDecoder.sub2api.decode([UsageKeyConfiguration].self, from: Data(json.utf8))

        XCTAssertEqual(decoded[0].symbolColorHex, UsageKeyConfiguration.defaultSymbolColorHex)
        XCTAssertTrue(decoded[0].showsInMenuBar)
    }

    func testMenuBarRowsOnlyIncludeVisibleKeysAndCarrySymbolColor() {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://global.example.com")
        let firstID = monitor.usageKeys[0].id
        monitor.updateKeyConfiguration(
            id: firstID,
            name: "Visible",
            symbolName: "bolt.fill",
            symbolColorHex: "#38bdf8",
            showsInMenuBar: true,
            apiKey: "key-a",
            baseURLMode: .inherited,
            baseURLOverride: ""
        )
        let hiddenID = monitor.addKey()
        monitor.updateKeyConfiguration(
            id: hiddenID,
            name: "Hidden",
            symbolName: "moon.fill",
            symbolColorHex: "#f97316",
            showsInMenuBar: false,
            apiKey: "key-b",
            baseURLMode: .inherited,
            baseURLOverride: ""
        )

        XCTAssertEqual(monitor.usageKeys.count, 2)
        XCTAssertEqual(monitor.keyState(id: hiddenID)?.configuration.showsInMenuBar, false)
        XCTAssertEqual(monitor.menuBarKeyRows.map(\.id), [firstID])
        XCTAssertEqual(monitor.menuBarKeyRows.first?.symbolColorHex, "#38BDF8")
    }

    func testMigratesOldSingleKeySettingsIntoFirstUsageKeyAndVerticalStatusLayout() {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        defaults.set(" https://sub.example.com/// ", forKey: UsageSnapshotMonitor.DefaultsKey.baseURL)
        defaults.set(" old_key ", forKey: UsageSnapshotMonitor.DefaultsKey.apiKey)
        defaults.set("horizontalFive", forKey: UsageSnapshotMonitor.DefaultsKey.serviceStatusLayoutMode)

        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        XCTAssertEqual(monitor.defaultBaseURLText, "https://sub.example.com")
        XCTAssertEqual(monitor.usageKeys.count, 1)
        XCTAssertEqual(monitor.usageKeys[0].configuration.name, "Key 1")
        XCTAssertEqual(monitor.usageKeys[0].configuration.symbolName, "key.fill")
        XCTAssertEqual(monitor.usageKeys[0].configuration.symbolColorHex, UsageKeyConfiguration.defaultSymbolColorHex)
        XCTAssertTrue(monitor.usageKeys[0].configuration.showsInMenuBar)
        XCTAssertEqual(monitor.usageKeys[0].configuration.apiKey, "old_key")
        XCTAssertEqual(monitor.usageKeys[0].configuration.baseURLMode, .inherited)
        XCTAssertEqual(monitor.serviceStatusLayoutMode, .verticalTwo)
        XCTAssertEqual(ServiceStatusLayoutMode.allCases, [.verticalTwo])
        XCTAssertEqual(defaults.string(forKey: UsageSnapshotMonitor.DefaultsKey.serviceStatusLayoutMode), "verticalTwo")
    }

    func testPerKeyBaseURLResolutionAndConfigurationInvalidationAreScoped() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: makeUsageJSON(dailyUsage: 1, remaining: 99)),
            .init(statusCode: 200, body: makeUsageJSON(dailyUsage: 2, remaining: 98)),
        ]
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://global.example.com")
        let inheritedID = monitor.usageKeys[0].id
        monitor.updateKeyConfiguration(
            id: inheritedID,
            name: "Global",
            symbolName: "globe",
            apiKey: "key-global",
            baseURLMode: .inherited,
            baseURLOverride: ""
        )
        let independentID = monitor.addKey()
        monitor.updateKeyConfiguration(
            id: independentID,
            name: "Indie",
            symbolName: "bolt.fill",
            apiKey: "key-independent",
            baseURLMode: .independent,
            baseURLOverride: "https://independent.example.com///"
        )

        await monitor.refreshAll()

        XCTAssertEqual(loader.requests.map { $0.url?.host }, ["global.example.com", "independent.example.com"])
        XCTAssertEqual(loader.requests.map { $0.value(forHTTPHeaderField: "Authorization") }, ["Bearer key-global", "Bearer key-independent"])
        XCTAssertEqual(monitor.keyState(id: inheritedID)?.snapshotFreshness, .fresh)
        XCTAssertEqual(monitor.keyState(id: independentID)?.snapshotFreshness, .fresh)

        monitor.updateBaseURL("https://new-global.example.com")

        XCTAssertEqual(monitor.keyState(id: inheritedID)?.snapshotFreshness, .configurationMismatch)
        XCTAssertEqual(monitor.keyState(id: independentID)?.snapshotFreshness, .fresh)

        monitor.updateKeyConfiguration(
            id: independentID,
            name: "Renamed",
            symbolName: "star.fill",
            apiKey: "key-independent",
            baseURLMode: .independent,
            baseURLOverride: "https://independent.example.com"
        )

        XCTAssertEqual(monitor.keyState(id: independentID)?.snapshotFreshness, .fresh)

        monitor.updateKeyConfiguration(
            id: independentID,
            name: "Renamed",
            symbolName: "star.fill",
            apiKey: "key-independent",
            baseURLMode: .independent,
            baseURLOverride: "https://other-independent.example.com"
        )

        XCTAssertEqual(monitor.keyState(id: inheritedID)?.snapshotFreshness, .configurationMismatch)
        XCTAssertEqual(monitor.keyState(id: independentID)?.snapshotFreshness, .configurationMismatch)
    }

    func testRefreshAllPartialFailurePreservesOtherKeySnapshots() async {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: makeUsageJSON(dailyUsage: 10, remaining: 90)),
            .init(statusCode: 200, body: makeUsageJSON(dailyUsage: 20, remaining: 80)),
            .init(statusCode: 500, body: #"{"message":"server down"}"#),
            .init(statusCode: 200, body: makeUsageJSON(dailyUsage: 30, remaining: 70)),
        ]
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://global.example.com")
        let firstID = monitor.usageKeys[0].id
        monitor.updateKeyConfiguration(id: firstID, name: "A", symbolName: "a.circle", apiKey: "key-a", baseURLMode: .inherited, baseURLOverride: "")
        let secondID = monitor.addKey()
        monitor.updateKeyConfiguration(id: secondID, name: "B", symbolName: "b.circle", apiKey: "key-b", baseURLMode: .inherited, baseURLOverride: "")

        await monitor.refreshAll()
        await monitor.refreshAll()

        XCTAssertEqual(monitor.keyState(id: firstID)?.snapshot?.subscription.dailyUsageUSD, 10)
        XCTAssertEqual(monitor.keyState(id: firstID)?.snapshotFreshness, .stale)
        XCTAssertEqual(monitor.keyState(id: firstID)?.lastError, "server down")
        XCTAssertEqual(monitor.keyState(id: secondID)?.snapshot?.subscription.dailyUsageUSD, 30)
        XCTAssertEqual(monitor.keyState(id: secondID)?.snapshotFreshness, .fresh)
        XCTAssertNil(monitor.keyState(id: secondID)?.lastError)
    }

    func testPerKeyCacheSaveAndRestore() async {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: makeUsageJSON(dailyUsage: 11, remaining: 89)),
            .init(statusCode: 200, body: makeUsageJSON(dailyUsage: 22, remaining: 78)),
        ]
        let firstMonitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        firstMonitor.updateBaseURL("https://global.example.com")
        let firstID = firstMonitor.usageKeys[0].id
        firstMonitor.updateKeyConfiguration(id: firstID, name: "A", symbolName: "a.circle", apiKey: "key-a", baseURLMode: .inherited, baseURLOverride: "")
        let secondID = firstMonitor.addKey()
        firstMonitor.updateKeyConfiguration(id: secondID, name: "B", symbolName: "b.circle", apiKey: "key-b", baseURLMode: .independent, baseURLOverride: "https://b.example.com")

        await firstMonitor.refreshAll()

        let restoredMonitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        XCTAssertEqual(restoredMonitor.keyState(id: firstID)?.snapshot?.subscription.dailyUsageUSD, 11)
        XCTAssertEqual(restoredMonitor.keyState(id: firstID)?.snapshotFreshness, .stale)
        XCTAssertEqual(restoredMonitor.keyState(id: secondID)?.snapshot?.subscription.dailyUsageUSD, 22)
        XCTAssertEqual(restoredMonitor.keyState(id: secondID)?.snapshotFreshness, .stale)
    }

    func testOldSingleKeyCacheMigratesIntoFirstKeyCache() throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        defaults.set("https://sub.example.com", forKey: UsageSnapshotMonitor.DefaultsKey.baseURL)
        defaults.set("old_key", forKey: UsageSnapshotMonitor.DefaultsKey.apiKey)
        let snapshot = try JSONDecoder.sub2api.decode(UsageResponse.self, from: Data(makeUsageJSON(dailyUsage: 55, remaining: 45).utf8))
        let fingerprint = try XCTUnwrap(UsageConfigurationFingerprint.make(baseURLText: "https://sub.example.com", apiKey: "old_key"))
        let entry = UsageSnapshotCacheEntry(
            configurationFingerprint: fingerprint,
            savedAt: Date(timeIntervalSince1970: 1_800),
            lastSuccessfulRefreshAt: Date(timeIntervalSince1970: 1_800),
            snapshot: snapshot
        )
        defaults.set(try JSONEncoder.sub2api.encode(entry), forKey: UsageSnapshotMonitor.DefaultsKey.snapshotCache)

        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        let firstID = try XCTUnwrap(monitor.usageKeys.first?.id)
        let store = UsageSnapshotCacheStore(userDefaults: defaults, key: UsageSnapshotMonitor.DefaultsKey.snapshotCache)
        XCTAssertEqual(monitor.keyState(id: firstID)?.snapshot?.subscription.dailyUsageUSD, 55)
        XCTAssertEqual(store.loadKeyedEntries()[firstID]?.snapshot.subscription.dailyUsageUSD, 55)
    }

    func testManualRefreshAllMarksInvalidKeyOnly() async {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: makeUsageJSON(dailyUsage: 9, remaining: 91)),
        ]
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://global.example.com")
        let firstID = monitor.usageKeys[0].id
        monitor.updateKeyConfiguration(id: firstID, name: "A", symbolName: "a.circle", apiKey: "key-a", baseURLMode: .inherited, baseURLOverride: "")
        let invalidID = monitor.addKey()

        await monitor.refreshAll()

        XCTAssertEqual(monitor.keyState(id: firstID)?.snapshotFreshness, .fresh)
        XCTAssertNil(monitor.keyState(id: firstID)?.lastError)
        XCTAssertEqual(monitor.keyState(id: invalidID)?.lastError, "请输入 API Key")
        XCTAssertEqual(monitor.keyState(id: invalidID)?.lastFailureKind, .validation)
        XCTAssertEqual(loader.requests.count, 1)
    }

    func testKeyNameAndSymbolChangePreservesSnapshotAndAlerts() async {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: makeUsageJSON(dailyUsage: 96, dailyLimit: 100, remaining: 9)),
        ]
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://global.example.com")
        let keyID = monitor.usageKeys[0].id
        monitor.updateKeyConfiguration(id: keyID, name: "A", symbolName: "a.circle", apiKey: "key-a", baseURLMode: .inherited, baseURLOverride: "")
        await monitor.refreshAll()

        let initialAlerts = monitor.keyState(id: keyID)?.thresholdAlertState
        monitor.updateKeyConfiguration(id: keyID, name: "Renamed", symbolName: "star.fill", apiKey: "key-a", baseURLMode: .inherited, baseURLOverride: "")

        XCTAssertEqual(monitor.keyState(id: keyID)?.snapshotFreshness, .fresh)
        XCTAssertEqual(monitor.keyState(id: keyID)?.snapshot?.subscription.dailyUsageUSD, 96)
        XCTAssertEqual(monitor.keyState(id: keyID)?.thresholdAlertState, initialAlerts)
    }

    func testUpdatingKeyConfigurationPublishesChangeForObservers() {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        let expectation = expectation(description: "usage monitor publishes configuration changes")
        let cancellable = monitor.objectWillChange.sink { expectation.fulfill() }
        let keyID = monitor.usageKeys[0].id

        monitor.updateKeyConfiguration(
            id: keyID,
            name: "Work",
            symbolName: "star.fill",
            apiKey: "key-a",
            baseURLMode: .inherited,
            baseURLOverride: ""
        )

        wait(for: [expectation], timeout: 1)
        _ = cancellable
    }
}
