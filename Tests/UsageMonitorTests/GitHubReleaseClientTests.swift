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

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(responseBody.utf8), response)
    }
}
