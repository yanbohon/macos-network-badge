import Foundation
import XCTest
@testable import UsageMonitor

final class BarkNotificationClientTests: XCTestCase {
    func testSendPostsConfiguredJSONPayloadToPushEndpoint() async throws {
        let loader = BarkRequestRecordingLoader(
            responses: [
                .init(statusCode: 200, body: #"{"code":200,"message":"success"}"#),
            ]
        )
        let client = BarkNotificationClient(requestLoader: loader)
        let configuration = BarkNotificationConfiguration(
            serverURL: URL(string: "https://push.example.com/base")!,
            deviceKey: "device-key",
            level: .critical,
            volume: 7,
            group: "服务状态",
            iconURL: "https://example.com/icon.png"
        )

        try await client.send(
            BarkNotificationMessage(title: "gpt-5.6-sol 服务不可用", body: "最新状态：失败"),
            configuration: configuration
        )

        let request = try XCTUnwrap(loader.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://push.example.com/base/push")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 20)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json; charset=utf-8")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(json["device_key"] as? String, "device-key")
        XCTAssertEqual(json["title"] as? String, "gpt-5.6-sol 服务不可用")
        XCTAssertEqual(json["body"] as? String, "最新状态：失败")
        XCTAssertEqual(json["level"] as? String, "critical")
        XCTAssertEqual(json["volume"] as? Int, 7)
        XCTAssertEqual(json["group"] as? String, "服务状态")
        XCTAssertNil(json["sound"])
        XCTAssertEqual(json["icon"] as? String, "https://example.com/icon.png")
        XCTAssertNil(json["url"])
    }

    func testHTTPFailurePreservesResponseMessageWithoutBarkCode() async throws {
        let loader = BarkRequestRecordingLoader(
            responses: [
                .init(statusCode: 400, body: #"{"message":"device key is invalid"}"#),
            ]
        )
        let client = BarkNotificationClient(requestLoader: loader)

        do {
            try await client.send(
                BarkNotificationMessage(title: "test", body: "test"),
                configuration: Self.configuration
            )
            XCTFail("Expected HTTP failure")
        } catch let error as BarkNotificationClientError {
            XCTAssertEqual(error, .httpStatus(400, "device key is invalid"))
            XCTAssertEqual(error.userMessage, "device key is invalid")
        }
    }

    func testBarkAPIFailurePreservesResponseMessage() async throws {
        let loader = BarkRequestRecordingLoader(
            responses: [
                .init(statusCode: 200, body: #"{"code":400,"message":"device key is invalid"}"#),
            ]
        )
        let client = BarkNotificationClient(requestLoader: loader)

        do {
            try await client.send(
                BarkNotificationMessage(title: "test", body: "test"),
                configuration: Self.configuration
            )
            XCTFail("Expected Bark API failure")
        } catch let error as BarkNotificationClientError {
            XCTAssertEqual(error, .api(400, "device key is invalid"))
            XCTAssertEqual(error.userMessage, "device key is invalid")
        }
    }

    private static let configuration = BarkNotificationConfiguration(
        serverURL: URL(string: "https://api.day.app")!,
        deviceKey: "device-key",
        level: .active,
        volume: nil,
        group: nil,
        iconURL: nil
    )
}

final class BarkRequestRecordingLoader: BarkNotificationRequestLoading {
    struct Response {
        let statusCode: Int
        let body: String
    }

    private(set) var requests: [URLRequest] = []
    var responses: [Response]
    var thrownError: Error?

    init(responses: [Response] = []) {
        self.responses = responses
    }

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
