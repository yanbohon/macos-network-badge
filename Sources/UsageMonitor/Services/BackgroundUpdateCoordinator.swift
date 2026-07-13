import AppKit
import Foundation

@MainActor
protocol UpdateAlertPresenting {
    func presentUpdate(_ info: UpdateReleaseInfo)
}

@MainActor
struct SystemUpdateAlertPresenter: UpdateAlertPresenting {
    private let openURL: (URL) -> Void
    private let activateApplication: () -> Void
    private let runAlert: (NSAlert) -> NSApplication.ModalResponse

    init(
        openURL: ((URL) -> Void)? = nil,
        activateApplication: (() -> Void)? = nil,
        runAlert: ((NSAlert) -> NSApplication.ModalResponse)? = nil
    ) {
        self.openURL = openURL ?? { url in
            NSWorkspace.shared.open(url)
        }
        self.activateApplication = activateApplication ?? {
            NSApp.activate(ignoringOtherApps: true)
        }
        self.runAlert = runAlert ?? { alert in
            alert.runModal()
        }
    }

    func presentUpdate(_ info: UpdateReleaseInfo) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "发现新版本 \(info.versionText)"
        alert.informativeText = "新版本已发布。是否前往 GitHub 发布页面下载更新？"
        alert.addButton(withTitle: "下载更新")
        alert.addButton(withTitle: "稍后")

        activateApplication()
        guard runAlert(alert) == .alertFirstButtonReturn else { return }
        openURL(info.releaseURL)
    }
}

struct ManualUpdateCheckOutcome: Equatable {
    let result: UpdateCheckResult
    let alertInfo: UpdateReleaseInfo?
}

@MainActor
final class BackgroundUpdateCoordinator {
    private struct ActiveUpdateCheck {
        let id: UUID
        let task: Task<UpdateCheckResult, Never>
    }

    private struct SharedUpdateCheckOutcome {
        let id: UUID
        let result: UpdateCheckResult
    }

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
    private var activeUpdateCheck: ActiveUpdateCheck?
    private var presentedCheckID: UUID?

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
        let checkDate = now()
        guard isCheckDue(at: checkDate) else { return }

        userDefaults.set(checkDate, forKey: DefaultsKey.lastCheckDate)
        let outcome = await performUpdateCheck()
        guard case let .updateAvailable(info) = outcome.result else { return }
        guard claimPresentation(for: info, from: outcome.id, at: checkDate, respectReminder: true) else {
            return
        }
        alertPresenter.presentUpdate(info)
    }

    func checkManually() async -> ManualUpdateCheckOutcome {
        let checkDate = now()
        userDefaults.set(checkDate, forKey: DefaultsKey.lastCheckDate)

        let outcome = await performUpdateCheck()
        guard case let .updateAvailable(info) = outcome.result else {
            return ManualUpdateCheckOutcome(result: outcome.result, alertInfo: nil)
        }

        let alertInfo = claimPresentation(
            for: info,
            from: outcome.id,
            at: checkDate,
            respectReminder: false
        ) ? info : nil
        return ManualUpdateCheckOutcome(result: outcome.result, alertInfo: alertInfo)
    }

    private func performUpdateCheck() async -> SharedUpdateCheckOutcome {
        if let activeUpdateCheck {
            return SharedUpdateCheckOutcome(
                id: activeUpdateCheck.id,
                result: await activeUpdateCheck.task.value
            )
        }

        let id = UUID()
        let task = Task { [updateChecker] in
            await updateChecker.checkForUpdate()
        }
        activeUpdateCheck = ActiveUpdateCheck(id: id, task: task)
        let result = await task.value
        if activeUpdateCheck?.id == id {
            activeUpdateCheck = nil
        }
        return SharedUpdateCheckOutcome(id: id, result: result)
    }

    private func claimPresentation(
        for info: UpdateReleaseInfo,
        from checkID: UUID,
        at date: Date,
        respectReminder: Bool
    ) -> Bool {
        guard presentedCheckID != checkID else { return false }
        if respectReminder, !shouldPresent(info, at: date) {
            return false
        }

        presentedCheckID = checkID
        userDefaults.set(info.versionText, forKey: DefaultsKey.lastPromptedVersion)
        userDefaults.set(date, forKey: DefaultsKey.lastPromptDate)
        return true
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
