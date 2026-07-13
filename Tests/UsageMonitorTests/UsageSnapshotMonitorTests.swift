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

        XCTAssertEqual(monitor.refreshIntervalSeconds, 300)
        XCTAssertNil(defaults.string(forKey: UsageSnapshotMonitor.DefaultsKey.email))
        XCTAssertNil(defaults.string(forKey: UsageSnapshotMonitor.DefaultsKey.selectedSubscriptionID))

        monitor.updateBaseURL("  https://sub.example.com/// ")
        XCTAssertEqual(monitor.baseURLText, "https://sub.example.com")
        XCTAssertEqual(defaults.string(forKey: UsageSnapshotMonitor.DefaultsKey.baseURL), "https://sub.example.com")

        monitor.refreshIntervalSeconds = 2
        XCTAssertEqual(monitor.refreshIntervalSeconds, 300)
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

    func testClearingAPIKeyStopsRefreshScheduling() {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let timers = ManualTimerFactory()
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: timers
        )

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateAPIKey("key")

        XCTAssertEqual(timers.scheduledIntervals, [300])
        XCTAssertEqual(defaults.string(forKey: UsageSnapshotMonitor.DefaultsKey.apiKey), "key")

        monitor.updateAPIKey("")

        XCTAssertNil(defaults.string(forKey: UsageSnapshotMonitor.DefaultsKey.apiKey))
        XCTAssertTrue(timers.timers.last?.isInvalidated ?? false)
        XCTAssertEqual(monitor.menuBarText, "未配置")
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

    func testRefreshStoresSnapshotWritesCacheAndMenuBarShowsDailyUsageOnly() async throws {
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
        XCTAssertEqual(monitor.snapshotFreshness, .fresh)
        XCTAssertEqual(monitor.menuBarText, "$84.04")
        XCTAssertEqual(monitor.balanceText, "$415.96")
        XCTAssertEqual(monitor.lastError, nil)
        XCTAssertNotNil(defaults.data(forKey: UsageSnapshotMonitor.DefaultsKey.snapshotCache))
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
        XCTAssertEqual(monitor.balanceText, "--")
        XCTAssertEqual(monitor.lastError, "API Key 无效，请检查后重试")

        monitor.updateAPIKey("key")
        await monitor.refreshNow()
        XCTAssertEqual(monitor.menuBarText, "刷新失败")
        XCTAssertEqual(monitor.balanceText, "--")
        XCTAssertEqual(monitor.statusLineText, "刷新失败")
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
        XCTAssertEqual(monitor.snapshotFreshness, .stale)
        XCTAssertEqual(monitor.statusLineText, "服务端失败，缓存已过期")
        XCTAssertEqual(monitor.lastError, "server down")
    }

    func testChangingAPIKeyAfterSuccessStopsShowingOldMenuBarValue() async throws {
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

        monitor.updateAPIKey("bad")
        XCTAssertEqual(monitor.menuBarText, "未验证")
        XCTAssertEqual(monitor.balanceText, "--")
        XCTAssertEqual(monitor.snapshotFreshness, .configurationMismatch)

        await monitor.refreshNow()

        XCTAssertEqual(monitor.menuBarText, "未授权")
        XCTAssertEqual(monitor.lastError, "API Key 无效，请检查后重试")
        XCTAssertEqual(monitor.authState, .unauthorized)
    }

    func testMenuBarDecimalPreferenceDefaultsToShowingDecimals() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        XCTAssertTrue(monitor.showMenuBarDecimals)
    }

    func testMenuBarSymbolVisibilityPreferenceDefaultsToShowingAndPersists() {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        XCTAssertFalse(monitor.hideMenuBarSymbols)

        monitor.hideMenuBarSymbols = true

        XCTAssertEqual(defaults.object(forKey: UsageSnapshotMonitor.DefaultsKey.hideMenuBarSymbols) as? Bool, true)
    }

    func testMenuBarSymbolVisibilityPreferenceReadsLegacySingleKeySetting() {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        defaults.set(true, forKey: UsageSnapshotMonitor.DefaultsKey.legacyHideSingleKeySymbol)

        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        XCTAssertTrue(monitor.hideMenuBarSymbols)
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
        XCTAssertEqual(defaults.object(forKey: "sub2api.showMenuBarDecimals") as? Bool, false)
    }

    func testRefreshIntervalPersistsAndReschedulesTimer() {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let timers = ManualTimerFactory()
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: timers
        )

        monitor.refreshIntervalSeconds = 900

        XCTAssertEqual(defaults.integer(forKey: UsageSnapshotMonitor.DefaultsKey.refreshIntervalSeconds), 900)
        XCTAssertEqual(timers.scheduledIntervals, [])

        monitor.updateBaseURL("https://sub.example.com")
        XCTAssertEqual(timers.scheduledIntervals, [])

        monitor.updateAPIKey("key")
        XCTAssertEqual(timers.scheduledIntervals, [900])
    }

    func testChangingBaseURLAfterSuccessStopsShowingOldMenuBarValue() async throws {
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

        monitor.updateBaseURL("https://other.example.com")

        XCTAssertEqual(monitor.menuBarText, "未验证")
        XCTAssertEqual(monitor.balanceText, "--")
        XCTAssertEqual(monitor.snapshotFreshness, .configurationMismatch)
        XCTAssertNil(monitor.snapshot)
    }

    func testLaunchRestoresMatchingPersistedCacheAsStale() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: Sub2APIModelsTests.sampleUsageJSON),
        ]
        let firstMonitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        firstMonitor.updateBaseURL("https://sub.example.com")
        firstMonitor.updateAPIKey("key")
        try await firstMonitor.validateAndRefresh()

        let restoredMonitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        XCTAssertEqual(restoredMonitor.snapshot?.planName, "Pro")
        XCTAssertEqual(restoredMonitor.snapshotFreshness, .stale)
        XCTAssertEqual(restoredMonitor.menuBarText, "$84.04")
        XCTAssertEqual(restoredMonitor.balanceText, "$415.96")
        XCTAssertEqual(restoredMonitor.statusLineText, "缓存数据（等待刷新）")
    }

    func testLaunchIgnoresMismatchedPersistedCache() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: Sub2APIModelsTests.sampleUsageJSON),
        ]
        let firstMonitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        firstMonitor.updateBaseURL("https://sub.example.com")
        firstMonitor.updateAPIKey("key")
        try await firstMonitor.validateAndRefresh()

        defaults.set("https://other.example.com", forKey: UsageSnapshotMonitor.DefaultsKey.baseURL)
        defaults.set("new_key", forKey: UsageSnapshotMonitor.DefaultsKey.apiKey)

        let mismatchedMonitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        XCTAssertNil(mismatchedMonitor.snapshot)
        XCTAssertEqual(mismatchedMonitor.snapshotFreshness, .configurationMismatch)
        XCTAssertEqual(mismatchedMonitor.menuBarText, "未验证")
        XCTAssertEqual(mismatchedMonitor.balanceText, "--")
    }

    func testStartTriggersLaunchRefreshOnlyOnce() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = BlockingRequestLoader()
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateAPIKey("key")

        monitor.start()
        monitor.start()

        while await loader.requestCount() == 0 {
            await Task.yield()
        }

        let launchRequestCount = await loader.requestCount()
        XCTAssertEqual(launchRequestCount, 1)
        await loader.resume(statusCode: 200, body: makeUsageJSON())
        while monitor.snapshot == nil {
            await Task.yield()
        }

        XCTAssertEqual(monitor.snapshot?.planName, "Pro")
    }

    func testNoFakeBalanceWithoutUsableSnapshot() {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateAPIKey("key")

        XCTAssertEqual(monitor.balanceText, "--")
        XCTAssertEqual(monitor.menuBarText, "未刷新")
        XCTAssertEqual(monitor.snapshotFreshness, .empty)
    }

    func testConcurrentManualAndTimerRefreshShareSingleRequest() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = BlockingRequestLoader()
        let timers = ManualTimerFactory()
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: timers
        )

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateAPIKey("key")
        XCTAssertEqual(timers.scheduledIntervals, [300])

        let manualRefresh = Task { await monitor.refreshNow() }

        while await loader.requestCount() == 0 {
            await Task.yield()
        }

        let manualRequestCount = await loader.requestCount()
        XCTAssertEqual(manualRequestCount, 1)
        timers.timers.last?.fire()
        await Task.yield()
        let timerRequestCount = await loader.requestCount()
        XCTAssertEqual(timerRequestCount, 1)

        await loader.resume(statusCode: 200, body: makeUsageJSON())
        await manualRefresh.value

        XCTAssertEqual(monitor.snapshot?.planName, "Pro")
        XCTAssertEqual(monitor.snapshotFreshness, .fresh)
        XCTAssertEqual(monitor.menuBarText, "$84.04")
    }

    func testTimerTicksDoNotAccumulateRefreshWaitersWhileRequestIsInFlight() async {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = BlockingRequestLoader()
        let timers = ManualTimerFactory()
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: timers
        )

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateAPIKey("key")

        timers.timers.last?.fire()
        while await loader.requestCount() == 0 {
            await Task.yield()
        }

        for _ in 0..<100 {
            timers.timers.last?.fire()
        }
        for _ in 0..<100 {
            await Task.yield()
        }

        XCTAssertEqual(monitor.peakTimerRefreshCount, 1)
        await loader.resume(statusCode: 200, body: makeUsageJSON())
        while monitor.activeTimerRefreshCount > 0 {
            await Task.yield()
        }
    }

    func testOldConfigurationResponseIsIgnoredAfterSettingsChange() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = BlockingRequestLoader()
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateAPIKey("key")

        let refreshTask = Task { await monitor.refreshNow() }

        while await loader.requestCount() == 0 {
            await Task.yield()
        }

        monitor.updateAPIKey("new-key")
        await loader.resume(statusCode: 200, body: makeUsageJSON())
        await refreshTask.value

        XCTAssertNil(monitor.snapshot)
        XCTAssertEqual(monitor.snapshotFreshness, .configurationMismatch)
        XCTAssertEqual(monitor.menuBarText, "未验证")
        XCTAssertEqual(monitor.balanceText, "--")
    }

    func testThresholdAlertStateChangesOnlyOncePerThresholdCrossing() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: makeUsageJSON(dailyUsage: 79, dailyLimit: 100, remaining: 50, expiresAt: nil)),
            .init(statusCode: 200, body: makeUsageJSON(dailyUsage: 81, dailyLimit: 100, remaining: 50, expiresAt: nil)),
            .init(statusCode: 200, body: makeUsageJSON(dailyUsage: 85, dailyLimit: 100, remaining: 50, expiresAt: nil)),
        ]
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateAPIKey("key")

        try await monitor.validateAndRefresh()
        XCTAssertNil(monitor.thresholdAlertState)

        await monitor.refreshNow()
        XCTAssertEqual(monitor.thresholdAlertState?.kinds, [.dailyUsage80])
        XCTAssertEqual(monitor.thresholdAlertState?.isNew, true)

        await monitor.refreshNow()
        XCTAssertEqual(monitor.thresholdAlertState?.kinds, [.dailyUsage80])
        XCTAssertEqual(monitor.thresholdAlertState?.isNew, false)
    }

    func testLowBalanceAndExpiryAlertsAreReported() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(
                statusCode: 200,
                body: makeUsageJSON(
                    dailyUsage: 20,
                    dailyLimit: 100,
                    remaining: 9,
                    expiresAt: "2026-05-09T12:00:00.000Z"
                )
            ),
        ]
        let monitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateAPIKey("key")

        try await monitor.validateAndRefresh()

        XCTAssertEqual(monitor.thresholdAlertState?.kinds, [.subscriptionExpired, .lowBalance])
        XCTAssertEqual(monitor.thresholdAlertState?.messages, ["订阅已过期", "剩余余额偏低"])
    }

}

func makeUsageJSON(
    dailyUsage: Double = 84.04,
    dailyLimit: Double = 500,
    remaining: Double = 415.96,
    expiresAt: String? = "2026-06-01T12:00:00.123Z"
) -> String {
    let expiresAtJSON = expiresAt.map { "\"\($0)\"" } ?? "null"
    return """
    {
      "isValid": true,
      "mode": "api-key",
      "model_stats": [],
      "planName": "Pro",
      "remaining": \(remaining),
      "subscription": {
        "daily_usage_usd": \(dailyUsage),
        "daily_limit_usd": \(dailyLimit),
        "weekly_usage_usd": 120.5,
        "weekly_limit_usd": 2500,
        "monthly_usage_usd": 300.25,
        "monthly_limit_usd": 10000,
        "expires_at": \(expiresAtJSON)
      },
      "unit": "usd",
      "usage": {
        "today": {
          "request_count": 12,
          "input_tokens": 1000,
          "output_tokens": 2000,
          "total_tokens": 3000,
          "input_cost_usd": 0.45,
          "output_cost_usd": 0.78,
          "total_cost_usd": 1.23
        },
        "total": {
          "request_count": 90,
          "input_tokens": 12000,
          "output_tokens": 13000,
          "total_tokens": 25000,
          "input_cost_usd": 8.25,
          "output_cost_usd": 11.50,
          "total_cost_usd": 19.75
        },
        "average_duration_ms": 842.7,
        "rpm": 0.7,
        "tpm": 85.3
      }
    }
    """
}
