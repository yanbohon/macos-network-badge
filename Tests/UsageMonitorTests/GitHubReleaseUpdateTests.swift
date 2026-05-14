import Foundation
import XCTest
@testable import UsageMonitor

final class GitHubReleaseUpdateTests: XCTestCase {
    func testStableVersionComparisonOrdersLaterPatchHigher() {
        let older = AppVersion.parse("v2.0.9")
        let newer = AppVersion.parse("2.1.0")

        XCTAssertNotNil(older)
        XCTAssertNotNil(newer)
        XCTAssertLessThan(older!, newer!)
    }

    func testPrereleaseComparisonTreatsFinalReleaseAsNewerThanBeta() {
        let prerelease = AppVersion.parse("2.1.0-beta.1")
        let final = AppVersion.parse("v2.1.0")

        XCTAssertNotNil(prerelease)
        XCTAssertNotNil(final)
        XCTAssertLessThan(prerelease!, final!)
    }

    func testUnparseableTagIsIgnoredByVersionParser() {
        XCTAssertNil(AppVersion.parse("banana"))
        XCTAssertNil(AppVersion.parse("v2"))
    }

    func testUpdateCheckerIgnoresDraftReleases() async {
        let checker = makeChecker(
            currentVersion: "v1.0.0",
            releases: [
                release(tag: "v1.2.0", draft: true),
                release(tag: "v1.0.1"),
            ]
        )

        let result = await checker.checkForUpdate(includePrereleases: false)

        XCTAssertEqual(result.statusText, "发现新版本 v1.0.1")
        XCTAssertEqual(result.downloadURL?.absoluteString, "https://github.com/yanbohon/UsageMonitor/releases/download/v1.0.1/UsageMonitor.dmg")
    }

    func testUpdateCheckerExcludesPrereleasesWhenTestingUpdatesAreOff() async {
        let checker = makeChecker(
            currentVersion: "v1.0.0",
            releases: [
                release(tag: "v1.1.0-beta.1", prerelease: true),
                release(tag: "v1.0.1"),
            ]
        )

        let result = await checker.checkForUpdate(includePrereleases: false)

        XCTAssertEqual(result.statusText, "发现新版本 v1.0.1")
        XCTAssertEqual(result.downloadURL?.absoluteString, "https://github.com/yanbohon/UsageMonitor/releases/download/v1.0.1/UsageMonitor.dmg")
    }

    func testUpdateCheckerIncludesPrereleasesWhenTestingUpdatesAreOn() async {
        let checker = makeChecker(
            currentVersion: "v1.0.0",
            releases: [
                release(tag: "v1.1.0-beta.1", prerelease: true),
                release(tag: "v1.0.1"),
            ]
        )

        let result = await checker.checkForUpdate(includePrereleases: true)

        XCTAssertEqual(result.statusText, "发现测试版 v1.1.0-beta.1")
        XCTAssertEqual(result.downloadURL?.absoluteString, "https://github.com/yanbohon/UsageMonitor/releases/download/v1.1.0-beta.1/UsageMonitor.dmg")
    }

    func testUpdateCheckerChoosesHighestNewerMatchingRelease() async {
        let checker = makeChecker(
            currentVersion: "v1.0.0",
            releases: [
                release(tag: "v1.2.0"),
                release(tag: "v1.3.0-beta.1", prerelease: true),
                release(tag: "v1.2.5"),
            ]
        )

        let result = await checker.checkForUpdate(includePrereleases: false)

        XCTAssertEqual(result.statusText, "发现新版本 v1.2.5")
        XCTAssertEqual(result.downloadURL?.absoluteString, "https://github.com/yanbohon/UsageMonitor/releases/download/v1.2.5/UsageMonitor.dmg")
    }

    func testUpdateCheckerFallsBackToReleasePageWhenDMGAssetMissing() async {
        let checker = makeChecker(
            currentVersion: "v1.0.0",
            releases: [
                release(tag: "v1.1.0", assets: [
                    asset(name: "UsageMonitor.dmg.sha256"),
                ]),
            ]
        )

        let result = await checker.checkForUpdate(includePrereleases: false)

        XCTAssertEqual(result.statusText, "发现新版本 v1.1.0")
        XCTAssertEqual(result.downloadURL?.absoluteString, "https://github.com/yanbohon/UsageMonitor/releases/tag/v1.1.0")
    }

    func testUpdateCheckerMapsInvalidResponseToFormatMessage() async {
        let checker = UpdateChecker(
            client: StubGitHubReleaseProvider(error: GitHubReleaseClientError.invalidResponse),
            currentVersion: AppVersion.parse("v1.0.0")!
        )

        let result = await checker.checkForUpdate(includePrereleases: false)

        XCTAssertEqual(result.statusText, "更新信息格式异常")
    }

    func testUpdateCheckerMapsNetworkFailureToRetryMessage() async {
        let checker = UpdateChecker(
            client: StubGitHubReleaseProvider(error: GitHubReleaseClientError.network("offline")),
            currentVersion: AppVersion.parse("v1.0.0")!
        )

        let result = await checker.checkForUpdate(includePrereleases: false)

        XCTAssertEqual(result.statusText, "检查更新失败，请稍后重试")
    }

    private func makeChecker(currentVersion: String, releases: [GitHubRelease]) -> UpdateChecker {
        UpdateChecker(
            client: StubGitHubReleaseProvider(releases: releases),
            currentVersion: AppVersion.parse(currentVersion)!
        )
    }

    private func release(
        tag: String,
        draft: Bool = false,
        prerelease: Bool = false,
        assets: [GitHubReleaseAsset] = []
    ) -> GitHubRelease {
        let resolvedAssets = assets.isEmpty ? [dmgAsset(tag: tag)] : assets
        return GitHubRelease(
            tagName: tag,
            draft: draft,
            prerelease: prerelease,
            publishedAt: Date(timeIntervalSince1970: 1_725_000_000),
            htmlURL: URL(string: "https://github.com/yanbohon/UsageMonitor/releases/tag/\(tag)")!,
            assets: resolvedAssets
        )
    }

    private func dmgAsset(tag: String) -> GitHubReleaseAsset {
        GitHubReleaseAsset(
            name: "UsageMonitor.dmg",
            browserDownloadURL: URL(string: "https://github.com/yanbohon/UsageMonitor/releases/download/\(tag)/UsageMonitor.dmg")!
        )
    }

    private func asset(name: String) -> GitHubReleaseAsset {
        GitHubReleaseAsset(
            name: name,
            browserDownloadURL: URL(string: "https://example.com/\(name)")!
        )
    }
}

private struct StubGitHubReleaseProvider: GitHubReleaseProviding {
    let releases: [GitHubRelease]
    let error: Error?

    init(releases: [GitHubRelease] = [], error: Error? = nil) {
        self.releases = releases
        self.error = error
    }

    func fetchReleases() async throws -> [GitHubRelease] {
        if let error {
            throw error
        }
        return releases
    }
}
