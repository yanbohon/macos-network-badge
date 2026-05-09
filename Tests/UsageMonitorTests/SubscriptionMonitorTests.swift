import XCTest
@testable import UsageMonitor

@MainActor
final class SubscriptionMonitorTests: XCTestCase {
    func testDefaultRefreshIntervalAndBaseURLNormalization() {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let monitor = SubscriptionMonitor(
            userDefaults: defaults,
            secretStore: InMemorySecretStore(),
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        XCTAssertEqual(monitor.refreshIntervalMinutes, 5)

        monitor.updateBaseURL("  https://sub.example.com/// ")
        XCTAssertEqual(monitor.baseURLText, "https://sub.example.com")
        XCTAssertEqual(defaults.string(forKey: SubscriptionMonitor.DefaultsKey.baseURL), "https://sub.example.com")

        monitor.refreshIntervalMinutes = 2
        XCTAssertEqual(monitor.refreshIntervalMinutes, 5)
    }

    func testMenuBarTextForConfigurationAndEmptySubscriptionStates() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: Sub2APIClientTests.loginBody(token: "token")),
            .init(statusCode: 200, body: #"{"code":0,"message":"success","data":[]}"#),
        ]
        let monitor = SubscriptionMonitor(
            userDefaults: defaults,
            secretStore: InMemorySecretStore(),
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        XCTAssertEqual(monitor.menuBarText, "未配置")

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateEmail("user@example.com")
        XCTAssertEqual(monitor.menuBarText, "未登录")

        monitor.updatePassword("secret")
        XCTAssertEqual(monitor.menuBarText, "未登录")

        try await monitor.loginAndRefresh()
        XCTAssertEqual(monitor.menuBarText, "无套餐")
    }

    func testRefreshFailureWithoutCacheShowsFailure() async {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: Sub2APIClientTests.loginBody(token: "token")),
            .init(statusCode: 500, body: #"{"code":500,"message":"server down","data":[]}"#),
        ]
        let monitor = SubscriptionMonitor(
            userDefaults: defaults,
            secretStore: InMemorySecretStore(),
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateEmail("user@example.com")
        monitor.updatePassword("secret")

        await monitor.refreshNow()

        XCTAssertEqual(monitor.menuBarText, "刷新失败")
        XCTAssertEqual(monitor.lastError, "server down")
    }

    func testInvalidCredentialsShowNotLoggedIn() async {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: #"{"code":1,"message":"bad credentials","data":null}"#),
        ]
        let monitor = SubscriptionMonitor(
            userDefaults: defaults,
            secretStore: InMemorySecretStore(),
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateEmail("user@example.com")
        monitor.updatePassword("wrong")

        do {
            try await monitor.loginAndRefresh()
            XCTFail("Expected login to fail")
        } catch {
            XCTAssertEqual(monitor.menuBarText, "未登录")
            XCTAssertEqual(monitor.lastError, "bad credentials")
        }
    }

    func testRefreshFailureWithCacheKeepsMenuBarUsage() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: Sub2APIClientTests.loginBody(token: "token")),
            .init(statusCode: 200, body: Sub2APIClientTests.oneSubscriptionBody(id: "cached", used: 84.04)),
            .init(statusCode: 500, body: #"{"code":500,"message":"server down","data":[]}"#),
        ]
        let monitor = SubscriptionMonitor(
            userDefaults: defaults,
            secretStore: InMemorySecretStore(),
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateEmail("user@example.com")
        monitor.updatePassword("secret")
        try await monitor.loginAndRefresh()

        await monitor.refreshNow()

        XCTAssertEqual(monitor.menuBarText, "$84.04/$100.00")
        XCTAssertEqual(monitor.lastError, "server down")
    }

    func testSuccessfulVerificationWithoutRefreshTokenDeletesOldRefreshToken() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let keychain = InMemorySecretStore()
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: Sub2APIClientTests.loginBody(token: "first")),
            .init(statusCode: 200, body: Sub2APIClientTests.oneSubscriptionBody(id: "first", used: 1)),
            .init(statusCode: 200, body: Self.loginBodyWithoutRefreshToken(token: "second")),
            .init(statusCode: 200, body: Sub2APIClientTests.oneSubscriptionBody(id: "second", used: 2)),
        ]
        let monitor = SubscriptionMonitor(
            userDefaults: defaults,
            secretStore: keychain,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        monitor.updateBaseURL("https://sub.example.com")
        monitor.updateEmail("user@example.com")
        monitor.updatePassword("secret")
        try await monitor.loginAndRefresh()
        XCTAssertEqual(keychain.values[.refreshToken], "rt")

        monitor.updateEmail("other@example.com")
        try await monitor.loginAndRefresh()

        XCTAssertNil(keychain.values[.refreshToken])
        XCTAssertEqual(keychain.values[.accessToken], "second")
    }

    static func loginBodyWithoutRefreshToken(token: String) -> String {
        """
        {"code":0,"message":"success","data":{"access_token":"\(token)","expires_in":3600,"token_type":"Bearer","user":{"id":2,"email":"other@example.com","balance":12,"status":"active"}}}
        """
    }
}
