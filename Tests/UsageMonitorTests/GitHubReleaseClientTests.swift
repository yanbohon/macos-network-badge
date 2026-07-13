import Foundation
import XCTest
@testable import UsageMonitor

final class GitHubReleaseClientTests: XCTestCase {
    func testFetchReleasesDecodesGitHubFieldsAndAssetURLs() async throws {
        let loader = GitHubReleaseRequestRecordingLoader()
        loader.responseBody = Self.sampleReleaseJSON
        let client = GitHubReleaseClient(requestLoader: loader)

        let releases = try await client.fetchReleases()

        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(releases[0].tagName, "v1.2.3-beta.1")
        XCTAssertEqual(releases[0].draft, false)
        XCTAssertEqual(releases[0].prerelease, true)
        XCTAssertEqual(releases[0].version, AppVersion.parse("v1.2.3-beta.1"))
        XCTAssertEqual(
            releases[0].downloadURL.absoluteString,
            "https://github.com/yanbohon/macos-network-badge/releases/download/v1.2.3-beta.1/UsageMonitor.dmg"
        )
        XCTAssertEqual(
            releases[0].checksumAsset?.browserDownloadURL.absoluteString,
            "https://github.com/yanbohon/macos-network-badge/releases/download/v1.2.3-beta.1/UsageMonitor.dmg.sha256"
        )
        XCTAssertEqual(loader.requests.count, 1)
        XCTAssertEqual(loader.requests[0].url?.absoluteString, "https://api.github.com/repos/yanbohon/macos-network-badge/releases")
    }

    func testRateLimitedAPIUsesPublicLatestReleaseFallback() async throws {
        let loader = GitHubReleaseRequestRecordingLoader()
        loader.stubbedResponses = [
            GitHubReleaseStubbedResponse(
                url: URL(string: "https://api.github.com/repos/yanbohon/macos-network-badge/releases")!,
                statusCode: 403,
                body: #"{"message":"API rate limit exceeded"}"#
            ),
            GitHubReleaseStubbedResponse(
                url: URL(string: "https://github.com/yanbohon/macos-network-badge/releases/tag/v1.2.3")!,
                statusCode: 200,
                body: ""
            ),
        ]
        let client = GitHubReleaseClient(requestLoader: loader)

        let releases = try await client.fetchReleases()

        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(releases[0].tagName, "v1.2.3")
        XCTAssertEqual(releases[0].draft, false)
        XCTAssertEqual(releases[0].prerelease, false)
        XCTAssertEqual(
            releases[0].htmlURL.absoluteString,
            "https://github.com/yanbohon/macos-network-badge/releases/tag/v1.2.3"
        )
        XCTAssertEqual(
            loader.requests.map { $0.url?.absoluteString },
            [
                "https://api.github.com/repos/yanbohon/macos-network-badge/releases",
                "https://github.com/yanbohon/macos-network-badge/releases/latest",
            ]
        )
        XCTAssertEqual(loader.requests.map(\.httpMethod), ["GET", "HEAD"])
    }

    func testNonRateLimitForbiddenResponseDoesNotUseFallback() async {
        let loader = GitHubReleaseRequestRecordingLoader()
        loader.stubbedResponses = [
            GitHubReleaseStubbedResponse(
                url: URL(string: "https://api.github.com/repos/yanbohon/macos-network-badge/releases")!,
                statusCode: 403,
                body: #"{"message":"Forbidden"}"#
            ),
        ]
        let client = GitHubReleaseClient(requestLoader: loader)

        do {
            _ = try await client.fetchReleases()
            XCTFail("Expected a non-rate-limit 403 response to fail")
        } catch let error as GitHubReleaseClientError {
            XCTAssertEqual(error, .httpStatus(403, "Forbidden"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(loader.requests.count, 1)
    }

    private static let sampleReleaseJSON = """
    [
      {
        "tag_name": "v1.2.3-beta.1",
        "draft": false,
        "prerelease": true,
        "published_at": "2025-05-09T12:34:56Z",
        "html_url": "https://github.com/yanbohon/macos-network-badge/releases/tag/v1.2.3-beta.1",
        "assets": [
          {
            "name": "UsageMonitor.dmg",
            "browser_download_url": "https://github.com/yanbohon/macos-network-badge/releases/download/v1.2.3-beta.1/UsageMonitor.dmg"
          },
          {
            "name": "UsageMonitor.dmg.sha256",
            "browser_download_url": "https://github.com/yanbohon/macos-network-badge/releases/download/v1.2.3-beta.1/UsageMonitor.dmg.sha256"
          }
        ]
      }
    ]
    """
}

private final class GitHubReleaseRequestRecordingLoader: GitHubReleaseRequestLoading {
    var requests: [URLRequest] = []
    var responseBody: String = "[]"
    var stubbedResponses: [GitHubReleaseStubbedResponse] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let stub = stubbedResponses.isEmpty
            ? GitHubReleaseStubbedResponse(url: request.url!, statusCode: 200, body: responseBody)
            : stubbedResponses.removeFirst()
        let response = HTTPURLResponse(
            url: stub.url,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(stub.body.utf8), response)
    }
}

private struct GitHubReleaseStubbedResponse {
    let url: URL
    let statusCode: Int
    let body: String
}
