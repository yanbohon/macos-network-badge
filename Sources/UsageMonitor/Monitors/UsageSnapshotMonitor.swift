import Foundation
import SwiftUI

enum ServiceStatusLayoutMode: String, CaseIterable, Equatable {
    case horizontalFive
    case verticalTwo

    var displayName: String {
        switch self {
        case .horizontalFive:
            return "横排 5 格"
        case .verticalTwo:
            return "竖排 2 格"
        }
    }
}

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
        static let showMenuBarDecimals = "sub2api.showMenuBarDecimals"
        static let refreshIntervalSeconds = "sub2api.refreshIntervalSeconds"
        static let serviceStatusLayoutMode = "sub2api.serviceStatusLayoutMode"
        static let snapshotCache = "sub2api.snapshotCache"
    }

    static let allowedRefreshIntervalSeconds = [1, 5, 30, 60, 300, 900, 1_800, 3_600]
    static let defaultRefreshIntervalSeconds = 300
    static let lowBalanceAlertThresholdUSD = 10.0
    static let expiringSoonWindowDays = 7

    @Published private(set) var baseURLText: String
    @Published private(set) var apiKey: String
    @Published var refreshIntervalSeconds: Int {
        didSet {
            guard Self.allowedRefreshIntervalSeconds.contains(refreshIntervalSeconds) else {
                refreshIntervalSeconds = Self.defaultRefreshIntervalSeconds
                return
            }
            userDefaults.set(refreshIntervalSeconds, forKey: DefaultsKey.refreshIntervalSeconds)
            scheduleTimerIfNeeded()
        }
    }
    @Published var showMenuBarDecimals: Bool {
        didSet {
            userDefaults.set(showMenuBarDecimals, forKey: DefaultsKey.showMenuBarDecimals)
        }
    }
    @Published var serviceStatusLayoutMode: ServiceStatusLayoutMode {
        didSet {
            userDefaults.set(serviceStatusLayoutMode.rawValue, forKey: DefaultsKey.serviceStatusLayoutMode)
        }
    }
    @Published private(set) var snapshot: UsageResponse?
    @Published private(set) var lastSuccessfulRefresh: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var lastFailureKind: UsageRefreshFailureKind?
    @Published private(set) var isRefreshing = false
    @Published private(set) var authState: UsageAuthState = .notConfigured
    @Published private(set) var snapshotFreshness: UsageSnapshotFreshness = .empty
    @Published private(set) var thresholdAlertState: UsageThresholdAlertState?

    private let userDefaults: UserDefaults
    private let client: Sub2APIClient
    private let timerFactory: RefreshTimerFactory
    private let cacheStore: UsageSnapshotCacheStore
    private let now: () -> Date
    private var refreshTimer: RefreshTimer?
    private var refreshTask: Task<UsageResponse, Error>?
    private var hasStarted = false
    private var lastAlertSignature: [UsageThresholdAlertKind]?

    init(
        userDefaults: UserDefaults = .standard,
        client: Sub2APIClient = Sub2APIClient(),
        timerFactory: RefreshTimerFactory = FoundationRefreshTimerFactory(),
        now: @escaping () -> Date = Date.init
    ) {
        self.userDefaults = userDefaults
        self.client = client
        self.timerFactory = timerFactory
        self.now = now
        cacheStore = UsageSnapshotCacheStore(userDefaults: userDefaults, key: DefaultsKey.snapshotCache)

        baseURLText = userDefaults.string(forKey: DefaultsKey.baseURL) ?? ""
        apiKey = userDefaults.string(forKey: DefaultsKey.apiKey) ?? ""
        let savedInterval = Self.savedRefreshIntervalSeconds(from: userDefaults)
        refreshIntervalSeconds = Self.allowedRefreshIntervalSeconds.contains(savedInterval)
            ? savedInterval
            : Self.defaultRefreshIntervalSeconds
        showMenuBarDecimals = userDefaults.object(forKey: DefaultsKey.showMenuBarDecimals) as? Bool ?? true
        serviceStatusLayoutMode = ServiceStatusLayoutMode(
            rawValue: userDefaults.string(forKey: DefaultsKey.serviceStatusLayoutMode) ?? ""
        ) ?? .horizontalFive

        migrateOldLoginStorage()
        restorePersistedSnapshotIfNeeded()
        scheduleTimerIfNeeded()
    }

    var menuBarText: String {
        if let snapshot, canShowSnapshotData {
            return UsageFormatters.menuBarDailyUsageText(
                snapshot.subscription.dailyUsageUSD,
                showDecimals: showMenuBarDecimals
            )
        }

        guard currentConfigurationFingerprint != nil else {
            return "未配置"
        }

        if snapshotFreshness == .configurationMismatch {
            return "未验证"
        }

        if let lastFailureKind, lastFailureKind == .unauthorized {
            return "未授权"
        }

        if lastError != nil {
            return lastFailureKind?.stateTextWithoutCache ?? "刷新失败"
        }

        return "未刷新"
    }

    var balanceText: String {
        if canShowSnapshotData, let snapshot {
            return UsageFormatters.balanceText(snapshot.remaining)
        }
        return "--"
    }

    var healthState: UsageHealthState {
        guard canShowSnapshotData, let snapshot else { return .normal }
        return UsageFormatters.healthState(
            used: snapshot.subscription.dailyUsageUSD,
            limit: snapshot.subscription.dailyLimitUSD
        )
    }

    var statusLineText: String {
        if isRefreshing {
            return "正在刷新"
        }

        switch snapshotFreshness {
        case .fresh:
            return "数据已刷新"
        case .stale:
            if let lastFailureKind {
                return lastFailureKind.stateTextWhenCached
            }
            return "缓存数据（等待刷新）"
        case .configurationMismatch:
            return "配置已变更，未验证"
        case .empty:
            if currentConfigurationFingerprint == nil {
                return "未配置"
            }
            if let lastFailureKind {
                return lastFailureKind.stateTextWithoutCache
            }
            return "未刷新"
        }
    }

    var statusDetailText: String? {
        lastError
    }

    var alertMessages: [String] {
        thresholdAlertState?.messages ?? []
    }

    var canShowSnapshotData: Bool {
        snapshot != nil && snapshotFreshness != .configurationMismatch
    }

    func updateBaseURL(_ value: String) {
        let previousFingerprint = currentConfigurationFingerprint
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        baseURLText = normalized
        userDefaults.set(normalized, forKey: DefaultsKey.baseURL)
        reconcileConfigurationChange(previousFingerprint: previousFingerprint)
    }

    func updateAPIKey(_ value: String) {
        let previousFingerprint = currentConfigurationFingerprint
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = normalized
        if normalized.isEmpty {
            userDefaults.removeObject(forKey: DefaultsKey.apiKey)
        } else {
            userDefaults.set(normalized, forKey: DefaultsKey.apiKey)
        }
        reconcileConfigurationChange(previousFingerprint: previousFingerprint)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        Task { [weak self] in
            await self?.refreshOnLaunch()
        }
    }

    func validateAndRefresh() async throws {
        try await performRefresh(configurationRequired: true)
    }

    func refreshNow() async {
        do {
            try await performRefresh(configurationRequired: true)
        } catch {
            // The monitor state already contains the user-facing failure.
        }
    }

    private func refreshOnLaunch() async {
        guard currentConfigurationFingerprint != nil else {
            return
        }
        do {
            try await performRefresh(configurationRequired: false)
        } catch {
            // Launch refresh failures are reflected in published state.
        }
    }

    private func refreshFromTimer() async {
        guard currentConfigurationFingerprint != nil else {
            return
        }
        do {
            try await performRefresh(configurationRequired: false)
        } catch {
            // Timer refresh failures are reflected in published state.
        }
    }

    private func performRefresh(configurationRequired: Bool) async throws {
        if let refreshTask {
            _ = try await refreshTask.value
            return
        }

        if let validationError = validationErrorForCurrentConfiguration() {
            if configurationRequired {
                applyValidationFailure(validationError)
                throw validationError
            }
            return
        }

        guard
            let baseURL = validatedBaseURL(),
            let fingerprint = currentConfigurationFingerprint
        else {
            if configurationRequired {
                let error = validationErrorForCurrentConfiguration() ?? UsageValidationError.missingBaseURL
                applyValidationFailure(error)
                throw error
            }
            return
        }

        let apiKeySnapshot = apiKey
        let task: Task<UsageResponse, Error> = Task { [client] in
            try await client.usage(baseURL: baseURL, apiKey: apiKeySnapshot)
        }
        refreshTask = task
        isRefreshing = true

        defer {
            refreshTask = nil
            isRefreshing = false
        }

        do {
            let response = try await task.value
            applySuccessfulRefresh(response, fingerprint: fingerprint)
        } catch {
            applyRefreshFailure(error, fingerprint: fingerprint)
            throw error
        }
    }

    private func validatedBaseURL() -> URL? {
        guard
            let url = URL(string: baseURLText),
            let scheme = url.scheme?.lowercased(),
            (scheme == "http" || scheme == "https"),
            url.host != nil
        else {
            return nil
        }
        return url
    }

    private var currentConfigurationFingerprint: UsageConfigurationFingerprint? {
        UsageConfigurationFingerprint.make(baseURLText: baseURLText, apiKey: apiKey)
    }

    private func validationErrorForCurrentConfiguration() -> UsageValidationError? {
        if baseURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .missingBaseURL
        }
        if validatedBaseURL() == nil {
            return .invalidBaseURL
        }
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .missingAPIKey
        }
        return nil
    }

    private func applyValidationFailure(_ error: UsageValidationError) {
        lastError = error.userMessage
        lastFailureKind = .validation
        authState = .notConfigured
    }

    private func applySuccessfulRefresh(
        _ response: UsageResponse,
        fingerprint: UsageConfigurationFingerprint
    ) {
        guard fingerprint == currentConfigurationFingerprint else {
            return
        }

        let completedAt = now()
        snapshot = response
        lastSuccessfulRefresh = completedAt
        lastError = nil
        lastFailureKind = nil
        snapshotFreshness = .fresh
        authState = .authenticated
        persistSnapshot(response, fingerprint: fingerprint, savedAt: completedAt)
        updateThresholdAlertState(for: response, isRestored: false)
    }

    private func applyRefreshFailure(_ error: Error, fingerprint: UsageConfigurationFingerprint) {
        guard fingerprint == currentConfigurationFingerprint else {
            return
        }

        let failureKind = failureKind(for: error)
        lastError = userMessage(for: error)
        lastFailureKind = failureKind

        switch failureKind {
        case .unauthorized:
            authState = .unauthorized
        case .validation:
            authState = .notConfigured
        case .network, .server, .decoding, .invalidResponse, .unknown:
            authState = snapshot == nil ? .error : .error
        }

        if snapshot == nil {
            snapshotFreshness = .empty
            thresholdAlertState = nil
            lastAlertSignature = nil
            return
        }

        snapshotFreshness = .stale
        if thresholdAlertState == nil, let snapshot {
            updateThresholdAlertState(for: snapshot, isRestored: true)
        }
    }

    private func failureKind(for error: Error) -> UsageRefreshFailureKind {
        if error is UsageValidationError {
            return .validation
        }
        if let clientError = error as? Sub2APIClientError {
            switch clientError {
            case .authorizationFailure:
                return .unauthorized
            case .network:
                return .network
            case .decoding:
                return .decoding
            case .invalidResponse:
                return .invalidResponse
            case let .httpStatus(status, _):
                if status == 401 || status == 403 {
                    return .unauthorized
                }
                return .server
            }
        }
        return .unknown
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

    private func reconcileConfigurationChange(previousFingerprint: UsageConfigurationFingerprint?) {
        let nextFingerprint = currentConfigurationFingerprint

        lastError = nil
        lastFailureKind = nil
        thresholdAlertState = nil
        lastAlertSignature = nil

        guard let nextFingerprint else {
            snapshot = nil
            lastSuccessfulRefresh = nil
            snapshotFreshness = .empty
            authState = .notConfigured
            scheduleTimerIfNeeded()
            return
        }

        if previousFingerprint == nil {
            snapshotFreshness = .empty
            authState = .ready
        } else if previousFingerprint != nextFingerprint {
            snapshot = nil
            lastSuccessfulRefresh = nil
            snapshotFreshness = .configurationMismatch
            authState = .ready
        } else if snapshot == nil {
            snapshotFreshness = .empty
            authState = .ready
        }

        scheduleTimerIfNeeded()
    }

    private func restorePersistedSnapshotIfNeeded() {
        guard let currentFingerprint = currentConfigurationFingerprint else {
            snapshotFreshness = .empty
            authState = .notConfigured
            return
        }

        guard let cachedEntry = cacheStore.load() else {
            snapshotFreshness = .empty
            authState = .ready
            return
        }

        guard cachedEntry.configurationFingerprint == currentFingerprint else {
            snapshot = nil
            lastSuccessfulRefresh = nil
            snapshotFreshness = .configurationMismatch
            authState = .ready
            return
        }

        snapshot = cachedEntry.snapshot
        lastSuccessfulRefresh = cachedEntry.lastSuccessfulRefreshAt
        snapshotFreshness = .stale
        authState = .authenticated
        lastError = nil
        lastFailureKind = nil
        updateThresholdAlertState(for: cachedEntry.snapshot, isRestored: true)
    }

    private func persistSnapshot(
        _ response: UsageResponse,
        fingerprint: UsageConfigurationFingerprint,
        savedAt: Date
    ) {
        let entry = UsageSnapshotCacheEntry(
            configurationFingerprint: fingerprint,
            savedAt: savedAt,
            lastSuccessfulRefreshAt: savedAt,
            snapshot: response
        )
        cacheStore.save(entry)
    }

    private func updateThresholdAlertState(for snapshot: UsageResponse, isRestored: Bool) {
        let kinds = thresholdAlertKinds(for: snapshot)
        guard !kinds.isEmpty else {
            thresholdAlertState = nil
            lastAlertSignature = nil
            return
        }

        let isNew = !isRestored && kinds != lastAlertSignature
        thresholdAlertState = UsageThresholdAlertState(kinds: kinds, isNew: isNew)
        lastAlertSignature = kinds
    }

    private func thresholdAlertKinds(for snapshot: UsageResponse) -> [UsageThresholdAlertKind] {
        var kinds: [UsageThresholdAlertKind] = []

        if let percentage = UsageFormatters.percentage(
            used: snapshot.subscription.dailyUsageUSD,
            limit: snapshot.subscription.dailyLimitUSD
        ) {
            if percentage >= 0.95 {
                kinds.append(.dailyUsage95)
            } else if percentage >= 0.80 {
                kinds.append(.dailyUsage80)
            }
        }

        if snapshot.remaining <= Self.lowBalanceAlertThresholdUSD {
            kinds.append(.lowBalance)
        }

        if let expiresAt = snapshot.subscription.expiresAt {
            let now = now()
            if expiresAt <= now {
                kinds.append(.subscriptionExpired)
            } else if let soonThreshold = Calendar.current.date(byAdding: .day, value: Self.expiringSoonWindowDays, to: now),
                      expiresAt <= soonThreshold {
                kinds.append(.subscriptionExpiringSoon)
            }
        }

        return kinds.sorted()
    }

    private func scheduleTimerIfNeeded() {
        refreshTimer?.invalidate()
        guard currentConfigurationFingerprint != nil else {
            refreshTimer = nil
            return
        }

        refreshTimer = timerFactory.schedule(interval: TimeInterval(refreshIntervalSeconds)) { [weak self] in
            Task { @MainActor in
                await self?.refreshFromTimer()
            }
        }
    }

    private func migrateOldLoginStorage() {
        userDefaults.removeObject(forKey: DefaultsKey.email)
        userDefaults.removeObject(forKey: DefaultsKey.selectedSubscriptionID)
    }
}

private extension UsageSnapshotMonitor {
    static let legacyRefreshIntervalMinutesKey = "sub2api.refreshIntervalMinutes"

    static func savedRefreshIntervalSeconds(from userDefaults: UserDefaults) -> Int {
        if let savedSeconds = userDefaults.object(forKey: DefaultsKey.refreshIntervalSeconds) as? Int {
            return savedSeconds
        }

        let legacyMinutes = userDefaults.integer(forKey: Self.legacyRefreshIntervalMinutesKey)
        guard legacyMinutes > 0 else {
            return Self.defaultRefreshIntervalSeconds
        }

        let legacySeconds = legacyMinutes * 60
        if Self.allowedRefreshIntervalSeconds.contains(legacySeconds) {
            userDefaults.set(legacySeconds, forKey: DefaultsKey.refreshIntervalSeconds)
        }
        userDefaults.removeObject(forKey: Self.legacyRefreshIntervalMinutesKey)
        return legacySeconds
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
