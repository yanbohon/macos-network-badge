import AppKit
import Foundation

@MainActor
protocol UpdateAlertPresenting {
    func presentUpdate(_ info: UpdateReleaseInfo)
}

@MainActor
struct SystemUpdateAlertPresenter: UpdateAlertPresenting {
    private let openURL: (URL) -> Void

    init(openURL: @escaping (URL) -> Void = { url in
        NSWorkspace.shared.open(url)
    }) {
        self.openURL = openURL
    }

    func presentUpdate(_ info: UpdateReleaseInfo) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "发现新版本 \(info.versionText)"
        alert.informativeText = "新版本已发布。是否前往 GitHub 发布页面下载更新？"
        alert.addButton(withTitle: "下载更新")
        alert.addButton(withTitle: "稍后")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        openURL(info.releaseURL)
    }
}

@MainActor
final class BackgroundUpdateCoordinator {
    enum DefaultsKey {
        static let lastCheckDate = "updates.lastBackgroundCheckDate"
        static let lastPromptedVersion = "updates.lastPromptedVersion"
        static let lastPromptDate = "updates.lastPromptDate"
    }

    static let checkInterval: TimeInterval = 24 * 60 * 60
    static let reminderInterval: TimeInterval = 7 * 24 * 60 * 60
    static let dueCheckInterval: TimeInterval = 60 * 60

    private let updateChecker: UpdateChecker
    private let userDefaults: UserDefaults
    private let timerFactory: RefreshTimerFactory
    private let alertPresenter: UpdateAlertPresenting
    private let now: () -> Date

    private var dueCheckTimer: RefreshTimer?
    private var hasStarted = false
    private var isChecking = false

    init(
        updateChecker: UpdateChecker = UpdateChecker(),
        userDefaults: UserDefaults = .standard,
        timerFactory: RefreshTimerFactory = FoundationRefreshTimerFactory(),
        alertPresenter: UpdateAlertPresenting? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.updateChecker = updateChecker
        self.userDefaults = userDefaults
        self.timerFactory = timerFactory
        self.alertPresenter = alertPresenter ?? SystemUpdateAlertPresenter()
        self.now = now
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        dueCheckTimer = timerFactory.schedule(interval: Self.dueCheckInterval) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.checkIfDue()
            }
        }

        Task { [weak self] in
            await self?.checkIfDue()
        }
    }

    func checkIfDue() async {
        guard !isChecking else { return }

        let checkDate = now()
        guard isCheckDue(at: checkDate) else { return }

        isChecking = true
        userDefaults.set(checkDate, forKey: DefaultsKey.lastCheckDate)
        defer { isChecking = false }

        let result = await updateChecker.checkForUpdate()
        guard case let .updateAvailable(info) = result else { return }
        guard shouldPresent(info, at: checkDate) else { return }

        userDefaults.set(info.versionText, forKey: DefaultsKey.lastPromptedVersion)
        userDefaults.set(checkDate, forKey: DefaultsKey.lastPromptDate)
        alertPresenter.presentUpdate(info)
    }

    private func isCheckDue(at date: Date) -> Bool {
        guard let lastCheckDate = userDefaults.object(forKey: DefaultsKey.lastCheckDate) as? Date else {
            return true
        }
        return date.timeIntervalSince(lastCheckDate) >= Self.checkInterval
    }

    private func shouldPresent(_ info: UpdateReleaseInfo, at date: Date) -> Bool {
        guard userDefaults.string(forKey: DefaultsKey.lastPromptedVersion) == info.versionText else {
            return true
        }
        guard let lastPromptDate = userDefaults.object(forKey: DefaultsKey.lastPromptDate) as? Date else {
            return true
        }
        return date.timeIntervalSince(lastPromptDate) >= Self.reminderInterval
    }
}
