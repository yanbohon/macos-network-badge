import XCTest
@testable import UsageMonitor

final class Sub2APIClientTests: XCTestCase {
    func testUsageSendsExpectedPathAndAuthorizationHeader() async throws {
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: Sub2APIModelsTests.sampleUsageJSON),
        ]
        let client = Sub2APIClient(requestLoader: loader)

        let response = try await client.usage(
            baseURL: URL(string: "https://sub.example.com/root/")!,
            apiKey: "key_123"
        )

        XCTAssertEqual(response.planName, "Pro")
        XCTAssertEqual(loader.requests.count, 1)
        XCTAssertEqual(loader.requests[0].url?.absoluteString, "https://sub.example.com/root/v1/usage")
        XCTAssertEqual(loader.requests[0].httpMethod, "GET")
        XCTAssertEqual(loader.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer key_123")
    }

    func testUsageTreatsIsValidFalseAsAuthorizationFailure() async throws {
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: Self.invalidUsageJSON),
        ]
        let client = Sub2APIClient(requestLoader: loader)

        do {
            _ = try await client.usage(
                baseURL: URL(string: "https://sub.example.com")!,
                apiKey: "bad"
            )
            XCTFail("Expected invalid key failure")
        } catch let error as Sub2APIClientError {
            XCTAssertTrue(error.isUnauthorized)
            XCTAssertEqual(error.userMessage, "API Key 无效，请检查后重试")
        }
    }

    func testHTTPAuthorizationStatusUsesInvalidAPIKeyMessage() async throws {
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 401, body: #"{"message":"unauthorized"}"#),
        ]
        let client = Sub2APIClient(requestLoader: loader)

        do {
            _ = try await client.usage(
                baseURL: URL(string: "https://sub.example.com")!,
                apiKey: "bad"
            )
            XCTFail("Expected authorization failure")
        } catch let error as Sub2APIClientError {
            XCTAssertTrue(error.isUnauthorized)
            XCTAssertEqual(error.userMessage, "API Key 无效，请检查后重试")
        }
    }

    func testNonAuthorizationHTTPStatusUsesReturnedMessage() async throws {
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 500, body: #"{"message":"server down"}"#),
        ]
        let client = Sub2APIClient(requestLoader: loader)

        do {
            _ = try await client.usage(
                baseURL: URL(string: "https://sub.example.com")!,
                apiKey: "key"
            )
            XCTFail("Expected server failure")
        } catch let error as Sub2APIClientError {
            XCTAssertEqual(error.userMessage, "server down")
        }
    }

    func testDecodingFailureUsesExpectedUserMessage() async throws {
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: #"{"isValid":true,"subscription":{}}"#),
        ]
        let client = Sub2APIClient(requestLoader: loader)

        do {
            _ = try await client.usage(
                baseURL: URL(string: "https://sub.example.com")!,
                apiKey: "key"
            )
            XCTFail("Expected decoding failure")
        } catch let error as Sub2APIClientError {
            XCTAssertEqual(error.userMessage, "响应格式不符合预期")
        }
    }

    static let invalidUsageJSON = """
    {
      "isValid": false,
      "mode": "api-key",
      "model_stats": [],
      "planName": "Free",
      "remaining": 0,
      "subscription": {
        "daily_usage_usd": 0,
        "daily_limit_usd": 0,
        "weekly_usage_usd": 0,
        "weekly_limit_usd": 0,
        "monthly_usage_usd": 0,
        "monthly_limit_usd": 0,
        "expires_at": null
      },
      "unit": "usd",
      "usage": {
        "today": 0,
        "total": 0,
        "average_duration_ms": 0,
        "rpm": 0,
        "tpm": 0
      }
    }
    """
}

final class RequestRecordingLoader: Sub2APIRequestLoading {
    struct Response {
        var statusCode: Int
        var body: String
    }

    var requests: [URLRequest] = []
    var responses: [Response] = []
    var thrownError: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if let thrownError {
            throw thrownError
        }
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

final class ManualTimerFactory: RefreshTimerFactory {
    private(set) var scheduledIntervals: [TimeInterval] = []

    func schedule(interval: TimeInterval, action: @escaping @Sendable () -> Void) -> RefreshTimer {
        scheduledIntervals.append(interval)
        return ManualRefreshTimer()
    }
}

final class ManualRefreshTimer: RefreshTimer {
    func invalidate() {}
}
