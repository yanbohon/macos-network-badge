import Foundation
import XCTest
@testable import UsageMonitor

@MainActor
final class BackgroundUpdateCoordinatorTests: XCTestCase {
    func testDueCheckPresentsAvailableUpdateAndRecordsCheckAndPrompt() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let defaults = makeDefaults()
        let provider = RecordingReleaseProvider(releases: [release(tag: "v1.1.0")])
        let presenter = RecordingUpdateAlertPresenter()
        let coordinator = makeCoordinator(
            provider: provider,
            defaults: defaults,
            presenter: presenter,
            now: now
        )

        await coordinator.checkIfDue()

        XCTAssertEqual(provider.fetchCount, 1)
        XCTAssertEqual(presenter.presentedVersions, ["v1.1.0"])
        XCTAssertEqual(
            defaults.object(forKey: BackgroundUpdateCoordinator.DefaultsKey.lastCheckDate) as? Date,
            now
        )
        XCTAssertEqual(
            defaults.string(forKey: BackgroundUpdateCoordinator.DefaultsKey.lastPromptedVersion),
            "v1.1.0"
        )
        XCTAssertEqual(
            defaults.object(forKey: BackgroundUpdateCoordinator.DefaultsKey.lastPromptDate) as? Date,
            now
        )
    }

    func testCheckWithinOneDayDoesNotRequestReleases() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let defaults = makeDefaults()
        defaults.set(
            now.addingTimeInterval(-BackgroundUpdateCoordinator.checkInterval + 1),
            forKey: BackgroundUpdateCoordinator.DefaultsKey.lastCheckDate
        )
        let provider = RecordingReleaseProvider(releases: [release(tag: "v1.1.0")])
        let presenter = RecordingUpdateAlertPresenter()
        let coordinator = makeCoordinator(
            provider: provider,
            defaults: defaults,
            presenter: presenter,
            now: now
        )

        await coordinator.checkIfDue()

        XCTAssertEqual(provider.fetchCount, 0)
        XCTAssertTrue(presenter.presentedVersions.isEmpty)
    }

    func testSameVersionIsNotPresentedAgainWithinOneWeek() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let defaults = makeDefaults()
        defaults.set("v1.1.0", forKey: BackgroundUpdateCoordinator.DefaultsKey.lastPromptedVersion)
        defaults.set(
            now.addingTimeInterval(-BackgroundUpdateCoordinator.reminderInterval + 1),
            forKey: BackgroundUpdateCoordinator.DefaultsKey.lastPromptDate
        )
        let provider = RecordingReleaseProvider(releases: [release(tag: "v1.1.0")])
        let presenter = RecordingUpdateAlertPresenter()
        let coordinator = makeCoordinator(
            provider: provider,
            defaults: defaults,
            presenter: presenter,
            now: now
        )

        await coordinator.checkIfDue()

        XCTAssertEqual(provider.fetchCount, 1)
        XCTAssertTrue(presenter.presentedVersions.isEmpty)
    }

    func testNewVersionIsPresentedDuringExistingReminderWindow() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let defaults = makeDefaults()
        defaults.set("v1.1.0", forKey: BackgroundUpdateCoordinator.DefaultsKey.lastPromptedVersion)
        defaults.set(now, forKey: BackgroundUpdateCoordinator.DefaultsKey.lastPromptDate)
        let provider = RecordingReleaseProvider(releases: [release(tag: "v1.2.0")])
        let presenter = RecordingUpdateAlertPresenter()
        let coordinator = makeCoordinator(
            provider: provider,
            defaults: defaults,
            presenter: presenter,
            now: now
        )

        await coordinator.checkIfDue()

        XCTAssertEqual(presenter.presentedVersions, ["v1.2.0"])
    }

    func testBackgroundFailureIsSilentAndStillRateLimited() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let defaults = makeDefaults()
        let provider = RecordingReleaseProvider(error: GitHubReleaseClientError.network("offline"))
        let presenter = RecordingUpdateAlertPresenter()
        let coordinator = makeCoordinator(
            provider: provider,
            defaults: defaults,
            presenter: presenter,
            now: now
        )

        await coordinator.checkIfDue()
        await coordinator.checkIfDue()

        XCTAssertEqual(provider.fetchCount, 1)
        XCTAssertTrue(presenter.presentedVersions.isEmpty)
        XCTAssertEqual(
            defaults.object(forKey: BackgroundUpdateCoordinator.DefaultsKey.lastCheckDate) as? Date,
            now
        )
    }

    func testStartSchedulesHourlyDueChecksOnlyOnce() {
        let timers = ManualTimerFactory()
        let coordinator = BackgroundUpdateCoordinator(
            updateChecker: UpdateChecker(
                client: RecordingReleaseProvider(releases: []),
                currentVersion: AppVersion.parse("v1.0.0")!
            ),
            userDefaults: makeDefaults(),
            timerFactory: timers,
            alertPresenter: RecordingUpdateAlertPresenter()
        )

        coordinator.start()
        coordinator.start()

        XCTAssertEqual(timers.scheduledIntervals, [BackgroundUpdateCoordinator.dueCheckInterval])
    }

    func testBackgroundAndManualChecksShareRequestAndPresentResultOnce() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let defaults = makeDefaults()
        let provider = BlockingReleaseProvider(releases: [release(tag: "v1.1.0")])
        let presenter = RecordingUpdateAlertPresenter()
        let coordinator = makeCoordinator(
            provider: provider,
            defaults: defaults,
            presenter: presenter,
            now: now
        )

        let backgroundTask = Task {
            await coordinator.checkIfDue()
        }
        await provider.waitUntilFirstRequest()
        let manualTask = Task {
            await coordinator.checkManually()
        }
        for _ in 0..<10 {
            await Task.yield()
        }
        await provider.resumeFirstRequest()

        let manualOutcome = await manualTask.value
        await backgroundTask.value
        let requestCount = await provider.requestCount()
        let presentationCount = presenter.presentedVersions.count + (manualOutcome.alertInfo == nil ? 0 : 1)

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(manualOutcome.result.statusText, "发现新版本 v1.1.0")
        XCTAssertEqual(presentationCount, 1)
    }

    func testSystemAlertDownloadButtonOpensReleaseURL() {
        let info = releaseInfo(tag: "v1.1.0")
        var activated = false
        var openedURL: URL?
        let presenter = SystemUpdateAlertPresenter(
            openURL: { openedURL = $0 },
            activateApplication: { activated = true },
            runAlert: { alert in
                XCTAssertEqual(alert.buttons.map(\.title), ["下载更新", "稍后"])
                return .alertFirstButtonReturn
            }
        )

        presenter.presentUpdate(info)

        XCTAssertTrue(activated)
        XCTAssertEqual(openedURL, info.releaseURL)
    }

    func testSystemAlertLaterButtonDoesNotOpenReleaseURL() {
        let info = releaseInfo(tag: "v1.1.0")
        var openedURL: URL?
        let presenter = SystemUpdateAlertPresenter(
            openURL: { openedURL = $0 },
            activateApplication: {},
            runAlert: { _ in .alertSecondButtonReturn }
        )

        presenter.presentUpdate(info)

        XCTAssertNil(openedURL)
    }

    private func makeCoordinator(
        provider: GitHubReleaseProviding,
        defaults: UserDefaults,
        presenter: RecordingUpdateAlertPresenter,
        now: Date
    ) -> BackgroundUpdateCoordinator {
        BackgroundUpdateCoordinator(
            updateChecker: UpdateChecker(
                client: provider,
                currentVersion: AppVersion.parse("v1.0.0")!
            ),
            userDefaults: defaults,
            timerFactory: ManualTimerFactory(),
            alertPresenter: presenter,
            now: { now }
        )
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "BackgroundUpdateCoordinatorTests.\(UUID().uuidString)")!
    }

    private func release(tag: String) -> GitHubRelease {
        GitHubRelease(
            tagName: tag,
            draft: false,
            prerelease: false,
            publishedAt: Date(timeIntervalSince1970: 1_725_000_000),
            htmlURL: URL(
                string: "https://github.com/yanbohon/macos-network-badge/releases/tag/\(tag)"
            )!,
            assets: []
        )
    }

    private func releaseInfo(tag: String) -> UpdateReleaseInfo {
        UpdateReleaseInfo(
            version: AppVersion.parse(tag)!,
            publishedAt: Date(timeIntervalSince1970: 1_725_000_000),
            releaseURL: URL(
                string: "https://github.com/yanbohon/macos-network-badge/releases/tag/\(tag)"
            )!
        )
    }
}

private final class RecordingReleaseProvider: GitHubReleaseProviding {
    private let releases: [GitHubRelease]
    private let error: Error?
    private(set) var fetchCount = 0

    init(releases: [GitHubRelease] = [], error: Error? = nil) {
        self.releases = releases
        self.error = error
    }

    func fetchReleases() async throws -> [GitHubRelease] {
        fetchCount += 1
        if let error {
            throw error
        }
        return releases
    }
}

private actor BlockingReleaseProvider: GitHubReleaseProviding {
    private let releases: [GitHubRelease]
    private var fetchCount = 0
    private var firstRequestContinuation: CheckedContinuation<[GitHubRelease], Error>?

    init(releases: [GitHubRelease]) {
        self.releases = releases
    }

    func fetchReleases() async throws -> [GitHubRelease] {
        fetchCount += 1
        guard fetchCount == 1 else { return releases }
        return try await withCheckedThrowingContinuation { continuation in
            firstRequestContinuation = continuation
        }
    }

    func waitUntilFirstRequest() async {
        while fetchCount == 0 {
            await Task.yield()
        }
    }

    func resumeFirstRequest() {
        firstRequestContinuation?.resume(returning: releases)
        firstRequestContinuation = nil
    }

    func requestCount() -> Int {
        fetchCount
    }
}

@MainActor
private final class RecordingUpdateAlertPresenter: UpdateAlertPresenting {
    private(set) var presentedVersions: [String] = []

    func presentUpdate(_ info: UpdateReleaseInfo) {
        presentedVersions.append(info.versionText)
    }
}
