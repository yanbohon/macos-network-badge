import Foundation

protocol RefreshTimer {
    func invalidate()
}

protocol RefreshTimerFactory {
    func schedule(interval: TimeInterval, action: @escaping @Sendable () -> Void) -> RefreshTimer
}

final class FoundationRefreshTimer: RefreshTimer {
    private let timer: Timer

    init(timer: Timer) {
        self.timer = timer
    }

    func invalidate() {
        timer.invalidate()
    }
}

final class FoundationRefreshTimerFactory: RefreshTimerFactory {
    func schedule(interval: TimeInterval, action: @escaping @Sendable () -> Void) -> RefreshTimer {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            action()
        }
        return FoundationRefreshTimer(timer: timer)
    }
}

@MainActor
final class UsageSnapshotMonitor: ObservableObject {
    enum DefaultsKey {
        static let baseURL = "sub2api.baseURL"
        static let email = "sub2api.email"
        static let selectedSubscriptionID = "sub2api.selectedSubscriptionID"
        static let apiKey = "sub2api.apiKey"
        static let refreshIntervalMinutes = "sub2api.refreshIntervalMinutes"
        static let showMenuBarDecimals = "sub2api.showMenuBarDecimals"
    }

    static let allowedRefreshIntervals = [1, 5, 15, 30, 60]
    static let defaultRefreshInterval = 5

    @Published private(set) var baseURLText: String
    @Published private(set) var apiKey: String
    @Published var refreshIntervalMinutes: Int {
        didSet {
            guard Self.allowedRefreshIntervals.contains(refreshIntervalMinutes) else {
                refreshIntervalMinutes = Self.defaultRefreshInterval
                return
            }
            userDefaults.set(refreshIntervalMinutes, forKey: DefaultsKey.refreshIntervalMinutes)
            scheduleTimer()
        }
    }
    @Published var showMenuBarDecimals: Bool {
        didSet {
            userDefaults.set(showMenuBarDecimals, forKey: DefaultsKey.showMenuBarDecimals)
        }
    }
    @Published private(set) var snapshot: UsageResponse?
    @Published private(set) var lastSuccessfulRefresh: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var authState: UsageAuthState = .notConfigured

    private let userDefaults: UserDefaults
    private let client: Sub2APIClient
    private let timerFactory: RefreshTimerFactory
    private var refreshTimer: RefreshTimer?

    init(
        userDefaults: UserDefaults = .standard,
        client: Sub2APIClient = Sub2APIClient(),
        timerFactory: RefreshTimerFactory = FoundationRefreshTimerFactory()
    ) {
        self.userDefaults = userDefaults
        self.client = client
        self.timerFactory = timerFactory

        baseURLText = userDefaults.string(forKey: DefaultsKey.baseURL) ?? ""
        apiKey = userDefaults.string(forKey: DefaultsKey.apiKey) ?? ""
        let savedInterval = userDefaults.integer(forKey: DefaultsKey.refreshIntervalMinutes)
        refreshIntervalMinutes = Self.allowedRefreshIntervals.contains(savedInterval)
            ? savedInterval
            : Self.defaultRefreshInterval
        showMenuBarDecimals = userDefaults.object(forKey: DefaultsKey.showMenuBarDecimals) as? Bool ?? true

        migrateOldLoginStorage()
        updateAuthState()
        scheduleTimer()
    }

    var menuBarText: String {
        if let snapshot {
            return UsageFormatters.menuBarDailyUsageText(
                snapshot.subscription.dailyUsageUSD,
                showDecimals: showMenuBarDecimals
            )
        }
        guard !baseURLText.isEmpty, !apiKey.isEmpty else {
            return "未配置"
        }
        if authState == .unauthorized {
            return "未授权"
        }
        if lastError != nil {
            return "刷新失败"
        }
        return "未配置"
    }

    var balanceText: String {
        UsageFormatters.balanceText(snapshot?.remaining ?? 0)
    }

    var healthState: UsageHealthState {
        guard let snapshot else { return .normal }
        return UsageFormatters.healthState(
            used: snapshot.subscription.dailyUsageUSD,
            limit: snapshot.subscription.dailyLimitUSD
        )
    }

    func updateBaseURL(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        baseURLText = normalized
        userDefaults.set(normalized, forKey: DefaultsKey.baseURL)
        updateAuthState()
    }

    func updateAPIKey(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = normalized
        if normalized.isEmpty {
            userDefaults.removeObject(forKey: DefaultsKey.apiKey)
        } else {
            userDefaults.set(normalized, forKey: DefaultsKey.apiKey)
        }
        lastError = nil
        updateAuthState()
    }

    func start() {
        Task { [weak self] in
            await self?.refreshOnLaunch()
        }
    }

    func validateAndRefresh() async throws {
        try await refreshUsage()
    }

    func refreshNow() async {
        do {
            try await refreshUsage()
        } catch {
            lastError = userMessage(for: error)
            updateAuthState(after: error)
        }
    }

    private func refreshOnLaunch() async {
        guard hasLaunchConfiguration else {
            updateAuthState()
            return
        }
        await refreshNow()
    }

    private var hasLaunchConfiguration: Bool {
        !baseURLText.isEmpty && !apiKey.isEmpty
    }

    private func refreshUsage() async throws {
        guard !baseURLText.isEmpty else {
            throw UsageValidationError.missingBaseURL
        }
        guard let baseURL = validatedBaseURL() else {
            throw UsageValidationError.invalidBaseURL
        }

        let currentAPIKey = apiKey
        guard !currentAPIKey.isEmpty else {
            throw UsageValidationError.missingAPIKey
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let response = try await client.usage(baseURL: baseURL, apiKey: currentAPIKey)
            snapshot = response
            lastSuccessfulRefresh = Date()
            lastError = nil
            authState = .authenticated
        } catch {
            lastError = userMessage(for: error)
            updateAuthState(after: error)
            throw error
        }
    }

    private func validatedBaseURL() -> URL? {
        guard
            let url = URL(string: baseURLText),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else {
            return nil
        }
        return url
    }

    private func updateAuthState(after error: Error? = nil) {
        if baseURLText.isEmpty || apiKey.isEmpty {
            authState = .notConfigured
        } else if let error = error as? Sub2APIClientError, error.isUnauthorized {
            authState = .unauthorized
        } else if lastError != nil {
            authState = .error
        } else if snapshot != nil {
            authState = .authenticated
        } else {
            authState = .ready
        }
    }

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        refreshTimer = timerFactory.schedule(interval: TimeInterval(refreshIntervalMinutes * 60)) { [weak self] in
            Task { @MainActor in
                await self?.refreshNow()
            }
        }
    }

    private func migrateOldLoginStorage() {
        userDefaults.removeObject(forKey: DefaultsKey.email)
        userDefaults.removeObject(forKey: DefaultsKey.selectedSubscriptionID)
    }

    private func userMessage(for error: Error) -> String {
        if let error = error as? Sub2APIClientError {
            return error.userMessage
        }
        if let error = error as? UsageValidationError {
            return error.userMessage
        }
        return "网络请求失败"
    }
}

extension UsageSnapshotMonitor: SettingsValuesPersisting {}

enum UsageAuthState: Equatable {
    case notConfigured
    case ready
    case authenticated
    case unauthorized
    case error
}

enum UsageValidationError: Error {
    case missingBaseURL
    case invalidBaseURL
    case missingAPIKey

    var userMessage: String {
        switch self {
        case .missingBaseURL:
            return "请输入 Base URL"
        case .invalidBaseURL:
            return "Base URL 必须以 http:// 或 https:// 开头"
        case .missingAPIKey:
            return "请输入 API Key"
        }
    }
}
