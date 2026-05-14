import Foundation
import XCTest
@testable import UsageMonitor

final class StatusAPIClientTests: XCTestCase {
    func testFetchStatusSendsFixedEndpointAndReturnsPrettyRawJSON() async throws {
        let loader = StatusRequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: ServiceStatusModelsTests.sampleStatusJSON),
        ]
        let client = StatusAPIClient(requestLoader: loader)

        let result = try await client.fetchStatus()

        XCTAssertEqual(result.response.service(model: "gpt-5.5")?.model, "gpt-5.5")
        XCTAssertEqual(loader.requests.count, 1)
        XCTAssertEqual(loader.requests[0].url?.absoluteString, "https://status.input.im/api/status")
        XCTAssertEqual(loader.requests[0].httpMethod, "GET")
        XCTAssertEqual(loader.requests[0].timeoutInterval, 20)
        XCTAssertTrue(result.prettyRawJSON.contains(#""model" : "gpt-5.5""#))
    }

    func testFetchStatusMapsHTTPFailureToUserMessage() async throws {
        let loader = StatusRequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 503, body: #"{"message":"status unavailable"}"#),
        ]
        let client = StatusAPIClient(requestLoader: loader)

        do {
            _ = try await client.fetchStatus()
            XCTFail("Expected HTTP failure")
        } catch let error as StatusAPIClientError {
            XCTAssertEqual(error.userMessage, "status unavailable")
        }
    }

    func testFetchStatusMapsDecodingFailureToUserMessage() async throws {
        let loader = StatusRequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: #"{"all_ok":true,"services":"bad"}"#),
        ]
        let client = StatusAPIClient(requestLoader: loader)

        do {
            _ = try await client.fetchStatus()
            XCTFail("Expected decoding failure")
        } catch let error as StatusAPIClientError {
            XCTAssertEqual(error.userMessage, "状态响应格式异常")
        }
    }
}

final class StatusRequestRecordingLoader: StatusAPIRequestLoading {
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
