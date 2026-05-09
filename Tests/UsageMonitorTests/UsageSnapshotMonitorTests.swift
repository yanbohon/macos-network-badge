import XCTest
@testable import UsageMonitor

@MainActor
final class UsageSnapshotMonitorTests: XCTestCase {
    func testDefaultRefreshIntervalBaseURLNormalizationAndMigration() {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        defaults.set("old@example.com", forKey: UsageSnapshotMonitor.DefaultsKey.email)
        defaults.set("sub-1", forKey: UsageSnapshotMonitor.DefaultsKey.selectedSubscriptionID)
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        XCTAssertEqual(monitor.refreshIntervalMinutes, 5)
        XCTAssertNil(defaults.string(forKey: UsageSnapshotMonitor.DefaultsKey.email))
        XCTAssertNil(defaults.string(forKey: UsageSnapshotMonitor.DefaultsKey.selectedSubscriptionID))

        monitor.updateBaseURL("  https://sub.example.com/// ")
        XCTAssertEqual(monitor.baseURLText, "https://sub.example.com")
        XCTAssertEqual(defaults.string(forKey: UsageSnapshotMonitor.DefaultsKey.baseURL), "https://sub.example.com")

        monitor.refreshIntervalMinutes = 2
        XCTAssertEqual(monitor.refreshIntervalMinutes, 5)
    }

    func testAPIKeyPersistsTrimmedAndClearingDeletesIt() {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateAPIKey("  key_123  ")
        XCTAssertEqual(monitor.apiKey, "key_123")
        XCTAssertEqual(defaults.string(forKey: UsageSnapshotMonitor.DefaultsKey.apiKey), "key_123")

        monitor.updateAPIKey("  ")
        XCTAssertEqual(monitor.apiKey, "")
        XCTAssertNil(defaults.string(forKey: UsageSnapshotMonitor.DefaultsKey.apiKey))
    }

    func testAPIKeyLoadsFromUserDefaultsWithoutSecretStore() {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        defaults.set("stored_key", forKey: UsageSnapshotMonitor.DefaultsKey.apiKey)

        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        XCTAssertEqual(monitor.apiKey, "stored_key")
    }

    func testRefreshStoresSnapshotAndMenuBarShowsDailyUsageOnly() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: Sub2APIModelsTests.sampleUsageJSON),
        ]
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateAPIKey("key_123")

        try await monitor.validateAndRefresh()

        XCTAssertEqual(monitor.snapshot?.planName, "Pro")
        XCTAssertEqual(monitor.menuBarText, "$84.04")
        XCTAssertEqual(monitor.balanceText, "$415.96")
        XCTAssertEqual(monitor.lastError, nil)
        XCTAssertEqual(loader.requests.map { $0.url?.path }, ["/v1/usage"])
        XCTAssertEqual(loader.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer key_123")
    }

    func testMenuBarTextForConfigurationInvalidAndFailureStates() async {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 401, body: #"{"message":"unauthorized"}"#),
            .init(statusCode: 500, body: #"{"message":"server down"}"#),
        ]
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        XCTAssertEqual(monitor.menuBarText, "未配置")

        monitor.updateBaseURL("https://sub.example.com")
        XCTAssertEqual(monitor.menuBarText, "未配置")

        monitor.updateAPIKey("bad")
        await monitor.refreshNow()
        XCTAssertEqual(monitor.menuBarText, "未授权")
        XCTAssertEqual(monitor.lastError, "API Key 无效，请检查后重试")

        monitor.updateAPIKey("key")
        await monitor.refreshNow()
        XCTAssertEqual(monitor.menuBarText, "刷新失败")
        XCTAssertEqual(monitor.lastError, "server down")
    }

    func testLocalValidationBlocksMissingAndInvalidConfigurationBeforeRequest() async {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateAPIKey("key")
        await monitor.refreshNow()
        XCTAssertEqual(monitor.lastError, "请输入 Base URL")

        monitor.updateBaseURL("ftp://sub.example.com")
        await monitor.refreshNow()
        XCTAssertEqual(monitor.lastError, "Base URL 必须以 http:// 或 https:// 开头")

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateAPIKey("")
        await monitor.refreshNow()
        XCTAssertEqual(monitor.lastError, "请输入 API Key")
        XCTAssertTrue(loader.requests.isEmpty)
    }

    func testRefreshFailureWithCacheKeepsMenuBarUsageAndSnapshot() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: Sub2APIModelsTests.sampleUsageJSON),
            .init(statusCode: 500, body: #"{"message":"server down"}"#),
        ]
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateAPIKey("key")
        try await monitor.validateAndRefresh()

        await monitor.refreshNow()

        XCTAssertEqual(monitor.snapshot?.planName, "Pro")
        XCTAssertEqual(monitor.menuBarText, "$84.04")
        XCTAssertEqual(monitor.lastError, "server down")
    }

    func testInvalidAPIKeyWithCacheKeepsCachedUsage() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: Sub2APIModelsTests.sampleUsageJSON),
            .init(statusCode: 200, body: Sub2APIClientTests.invalidUsageJSON),
        ]
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateAPIKey("key")
        try await monitor.validateAndRefresh()

        await monitor.refreshNow()

        XCTAssertEqual(monitor.menuBarText, "$84.04")
        XCTAssertEqual(monitor.lastError, "API Key 无效，请检查后重试")
        XCTAssertEqual(monitor.authState, .unauthorized)
    }

    func testMenuBarDecimalPreferenceTruncatesOnlyMenuBarValue() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: Sub2APIModelsTests.sampleUsageJSON),
        ]
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateAPIKey("key")
        try await monitor.validateAndRefresh()

        monitor.showMenuBarDecimals = false

        XCTAssertEqual(monitor.menuBarText, "$84")
        XCTAssertEqual(monitor.balanceText, "$415.96")
    }

    func testRefreshIntervalPersistsAndReschedulesTimer() {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let timers = ManualTimerFactory()
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: timers
        )

        monitor.refreshIntervalMinutes = 15

        XCTAssertEqual(defaults.integer(forKey: UsageSnapshotMonitor.DefaultsKey.refreshIntervalMinutes), 15)
        XCTAssertEqual(timers.scheduledIntervals, [300, 900])
    }

}
