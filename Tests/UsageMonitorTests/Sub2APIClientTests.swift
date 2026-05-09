import XCTest
@testable import UsageMonitor

final class Sub2APIClientTests: XCTestCase {
    func testLoginSendsExpectedPathAndJSONBody() async throws {
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(
                statusCode: 200,
                body: """
                {"code":0,"message":"success","data":{"access_token":"token","refresh_token":"rt","expires_in":3600,"token_type":"Bearer","user":{"id":1,"email":"user@example.com","balance":336,"status":"active"}}}
                """
            ),
        ]
        let client = Sub2APIClient(requestLoader: loader)

        let login = try await client.login(
            baseURL: URL(string: "https://sub.example.com")!,
            email: "user@example.com",
            password: "secret"
        )

        XCTAssertEqual(login.accessToken, "token")
        XCTAssertEqual(loader.requests.count, 1)
        XCTAssertEqual(loader.requests[0].url?.absoluteString, "https://sub.example.com/api/v1/auth/login")
        XCTAssertEqual(loader.requests[0].httpMethod, "POST")
        XCTAssertEqual(loader.requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(loader.requests[0].httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
        XCTAssertEqual(json?["email"], "user@example.com")
        XCTAssertEqual(json?["password"], "secret")
    }

    func testSubscriptionsSendsExpectedPathAndAuthorizationHeader() async throws {
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: #"{"code":0,"message":"success","data":[]}"#),
        ]
        let client = Sub2APIClient(requestLoader: loader)

        _ = try await client.subscriptions(
            baseURL: URL(string: "https://sub.example.com/root/")!,
            accessToken: "abc123"
        )

        XCTAssertEqual(loader.requests[0].url?.absoluteString, "https://sub.example.com/root/api/v1/subscriptions")
        XCTAssertEqual(loader.requests[0].httpMethod, "GET")
        XCTAssertEqual(loader.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer abc123")
    }

    func testLoginRequiresSuccessfulEnvelopeWithAccessToken() async throws {
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: #"{"code":42,"message":"bad credentials","data":null}"#),
        ]
        let client = Sub2APIClient(requestLoader: loader)

        do {
            _ = try await client.login(
                baseURL: URL(string: "https://sub.example.com")!,
                email: "user@example.com",
                password: "wrong"
            )
            XCTFail("Expected login failure")
        } catch let error as Sub2APIClientError {
            XCTAssertEqual(error.userMessage, "bad credentials")
        }
    }

    func testSubscriptionsDecodingFailureUsesExpectedUserMessage() async throws {
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: #"{"code":0,"message":"success","data":{}}"#),
        ]
        let client = Sub2APIClient(requestLoader: loader)

        do {
            _ = try await client.subscriptions(
                baseURL: URL(string: "https://sub.example.com")!,
                accessToken: "token"
            )
            XCTFail("Expected subscriptions decoding to fail")
        } catch let error as Sub2APIClientError {
            XCTAssertEqual(error.userMessage, "响应格式不符合预期")
        }
    }

    func testSubscriptionMonitorRelogsOnceAfterUnauthorizedAndPreservesCachedDataOnRetryFailure() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let keychain = InMemorySecretStore()
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: Self.loginBody(token: "first-token")),
            .init(statusCode: 200, body: Self.oneSubscriptionBody(id: "cached", used: 10)),
            .init(statusCode: 401, body: #"{"code":401,"message":"unauthorized","data":[]}"#),
            .init(statusCode: 200, body: Self.loginBody(token: "second-token")),
            .init(statusCode: 500, body: #"{"code":500,"message":"server down","data":[]}"#),
        ]
        let monitor = await SubscriptionMonitor(
            userDefaults: defaults,
            secretStore: keychain,
            client: Sub2APIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )

        await monitor.updateBaseURL("https://sub.example.com")
        await monitor.updateEmail("user@example.com")
        await monitor.updatePassword("secret")
        try await monitor.loginAndRefresh()
        let initialSelectedID = await MainActor.run { monitor.selectedSubscription?.id }
        XCTAssertEqual(initialSelectedID, "cached")

        await monitor.refreshNow()

        let selectedIDAfterFailure = await MainActor.run { monitor.selectedSubscription?.id }
        let lastError = await MainActor.run { monitor.lastError }
        XCTAssertEqual(selectedIDAfterFailure, "cached")
        XCTAssertEqual(lastError, "登录已失效，请重新验证")
        XCTAssertEqual(loader.requests.map { $0.url?.path }, [
            "/api/v1/auth/login",
            "/api/v1/subscriptions",
            "/api/v1/subscriptions",
            "/api/v1/auth/login",
            "/api/v1/subscriptions",
        ])
        XCTAssertEqual(loader.requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer first-token")
        XCTAssertEqual(loader.requests[4].value(forHTTPHeaderField: "Authorization"), "Bearer second-token")
    }

    static func loginBody(token: String) -> String {
        """
        {"code":0,"message":"success","data":{"access_token":"\(token)","refresh_token":"rt","expires_in":3600,"token_type":"Bearer","user":{"id":1,"email":"user@example.com","balance":336,"status":"active"}}}
        """
    }

    static func oneSubscriptionBody(id: String, used: Double) -> String {
        """
        {"code":0,"message":"success","data":[{"id":"\(id)","status":"active","used_today_usd":\(used),"used_week_usd":25,"used_month_usd":50,"expires_at":null,"group":{"name":"Pro","platform":"openai","daily_limit_usd":100,"weekly_limit_usd":700,"monthly_limit_usd":3000}}]}
        """
    }
}

final class RequestRecordingLoader: Sub2APIRequestLoading {
    struct Response {
        var statusCode: Int
        var body: String
    }

    var requests: [URLRequest] = []
    var responses: [Response] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(response.body.utf8), httpResponse)
    }
}

final class InMemorySecretStore: SecretStoring {
    var values: [SecretKey: String] = [:]

    func read(_ key: SecretKey) throws -> String? {
        values[key]
    }

    func write(_ value: String, for key: SecretKey) throws {
        values[key] = value
    }

    func delete(_ key: SecretKey) throws {
        values.removeValue(forKey: key)
    }
}

final class CountingSecretStore: SecretStoring {
    private var readCounts: [SecretKey: Int] = [:]

    func read(_ key: SecretKey) throws -> String? {
        readCounts[key, default: 0] += 1
        return nil
    }

    func write(_ value: String, for key: SecretKey) throws {}

    func delete(_ key: SecretKey) throws {}

    func readCount(for key: SecretKey) -> Int {
        readCounts[key, default: 0]
    }
}

final class ThrowingSecretStore: SecretStoring {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func read(_ key: SecretKey) throws -> String? {
        throw error
    }

    func write(_ value: String, for key: SecretKey) throws {
        throw error
    }

    func delete(_ key: SecretKey) throws {
        throw error
    }
}

final class ManualTimerFactory: RefreshTimerFactory {
    func schedule(interval: TimeInterval, action: @escaping @Sendable () -> Void) -> RefreshTimer {
        ManualRefreshTimer()
    }
}

final class ManualRefreshTimer: RefreshTimer {
    func invalidate() {}
}
