import Foundation
import SwiftUI

enum ServiceStatusLayoutMode: String, CaseIterable, Equatable {
    case verticalTwo

    var displayName: String {
        switch self {
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
        static let hideMenuBarSymbols = "sub2api.hideMenuBarSymbols"
        static let legacyHideSingleKeySymbol = "sub2api.hideSingleKeySymbol"
        static let refreshIntervalSeconds = "sub2api.refreshIntervalSeconds"
        static let serviceStatusLayoutMode = "sub2api.serviceStatusLayoutMode"
        static let snapshotCache = "sub2api.snapshotCache"
        static let usageKeys = "sub2api.usageKeys"
    }

    static let allowedRefreshIntervalSeconds = [1, 5, 30, 60, 300, 900, 1_800, 3_600]
    static let defaultRefreshIntervalSeconds = 300
    static let lowBalanceAlertThresholdUSD = 10.0
    static let expiringSoonWindowDays = 7

    @Published private(set) var defaultBaseURLText: String
    @Published private(set) var usageKeys: [UsageKeyEntry]
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
    @Published var hideMenuBarSymbols: Bool {
        didSet {
            userDefaults.set(hideMenuBarSymbols, forKey: DefaultsKey.hideMenuBarSymbols)
        }
    }
    @Published var serviceStatusLayoutMode: ServiceStatusLayoutMode {
        didSet {
            userDefaults.set(ServiceStatusLayoutMode.verticalTwo.rawValue, forKey: DefaultsKey.serviceStatusLayoutMode)
            if serviceStatusLayoutMode != .verticalTwo {
                serviceStatusLayoutMode = .verticalTwo
            }
        }
    }

    private let userDefaults: UserDefaults
    private let client: Sub2APIClient
    private let timerFactory: RefreshTimerFactory
    private let cacheStore: UsageSnapshotCacheStore
    private let now: () -> Date
    private var refreshTimer: RefreshTimer?
    private var refreshTasks: [String: Task<UsageResponse, Error>] = [:]
    private var isTimerRefreshInFlight = false
    private(set) var activeTimerRefreshCount = 0
    private(set) var peakTimerRefreshCount = 0
    private var hasStarted = false
    private var lastAlertSignatures: [String: [UsageThresholdAlertKind]] = [:]

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

        defaultBaseURLText = UsageKeyConfiguration.normalizedBaseURL(
            userDefaults.string(forKey: DefaultsKey.baseURL) ?? ""
        )
        let savedInterval = Self.savedRefreshIntervalSeconds(from: userDefaults)
        refreshIntervalSeconds = Self.allowedRefreshIntervalSeconds.contains(savedInterval)
            ? savedInterval
            : Self.defaultRefreshIntervalSeconds
        showMenuBarDecimals = userDefaults.object(forKey: DefaultsKey.showMenuBarDecimals) as? Bool ?? true
        hideMenuBarSymbols =
            userDefaults.object(forKey: DefaultsKey.hideMenuBarSymbols) as? Bool
            ?? userDefaults.object(forKey: DefaultsKey.legacyHideSingleKeySymbol) as? Bool
            ?? false
        serviceStatusLayoutMode = .verticalTwo
        usageKeys = []

        migrateOldLoginStorage()
        migrateServiceStatusLayoutPreference()
        usageKeys = loadUsageKeys()
        restorePersistedSnapshotsIfNeeded()
        scheduleTimerIfNeeded()
    }

    var baseURLText: String {
        defaultBaseURLText
    }

    var apiKey: String {
        usageKeys.first?.configuration.apiKey ?? ""
    }

    var snapshot: UsageResponse? {
        usageKeys.first?.snapshot
    }

    var lastSuccessfulRefresh: Date? {
        usageKeys.first?.lastSuccessfulRefresh
    }

    var lastError: String? {
        usageKeys.first?.lastError
    }

    var lastFailureKind: UsageRefreshFailureKind? {
        usageKeys.first?.lastFailureKind
    }

    var isRefreshing: Bool {
        usageKeys.contains { $0.isRefreshing }
    }

    var authState: UsageAuthState {
        usageKeys.first?.authState ?? .notConfigured
    }

    var snapshotFreshness: UsageSnapshotFreshness {
        usageKeys.first?.snapshotFreshness ?? .empty
    }

    var thresholdAlertState: UsageThresholdAlertState? {
        usageKeys.first?.thresholdAlertState
    }

    var menuBarText: String {
        menuBarKeyRows.map(\.text).joined(separator: " ")
    }

    var menuBarKeyRows: [MenuBarKeyDisplayRow] {
        usageKeys.filter { $0.configuration.showsInMenuBar }.map { entry in
            MenuBarKeyDisplayRow(
                id: entry.id,
                name: entry.configuration.name,
                symbolName: entry.configuration.symbolName,
                symbolColorHex: entry.configuration.symbolColorHex,
                text: menuBarText(for: entry)
            )
        }
    }

    var balanceText: String {
        guard let entry = usageKeys.first, entry.canShowSnapshotData, let snapshot = entry.snapshot else {
            return "--"
        }
        return UsageFormatters.balanceText(snapshot.remaining)
    }

    var healthState: UsageHealthState {
        guard let entry = usageKeys.first, entry.canShowSnapshotData, let snapshot = entry.snapshot else {
            return .normal
        }
        return UsageFormatters.healthState(
            used: snapshot.subscription.dailyUsageUSD,
            limit: snapshot.subscription.dailyLimitUSD
        )
    }

    var statusLineText: String {
        guard let first = usageKeys.first else { return "未配置" }
        return statusLineText(for: first)
    }

    var statusDetailText: String? {
        usageKeys.first?.lastError
    }

    var alertMessages: [String] {
        usageKeys.first?.thresholdAlertState?.messages ?? []
    }

    var canShowSnapshotData: Bool {
        usageKeys.first?.canShowSnapshotData ?? false
    }

    func keyState(id: String) -> UsageKeyEntry? {
        usageKeys.first { $0.id == id }
    }

    func updateBaseURL(_ value: String) {
        let previousFingerprints = keyFingerprintsByID()
        let normalized = UsageKeyConfiguration.normalizedBaseURL(value)
        defaultBaseURLText = normalized
        userDefaults.set(normalized, forKey: DefaultsKey.baseURL)
        reconcileConfigurationChanges(previousFingerprints: previousFingerprints)
    }

    func updateAPIKey(_ value: String) {
        guard let first = usageKeys.first else { return }
        updateKeyConfiguration(
            id: first.id,
            name: first.configuration.name,
            symbolName: first.configuration.symbolName,
            symbolColorHex: first.configuration.symbolColorHex,
            showsInMenuBar: first.configuration.showsInMenuBar,
            apiKey: value,
            baseURLMode: first.configuration.baseURLMode,
            baseURLOverride: first.configuration.baseURLOverride
        )
    }

    @discardableResult
    func addKey() -> String {
        let keyID = UUID().uuidString
        let nextIndex = usageKeys.count
        let entry = UsageKeyEntry(
            configuration: UsageKeyConfiguration(
                id: keyID,
                name: "Key \(nextIndex + 1)",
                symbolName: UsageKeyConfiguration.defaultSymbolName,
                symbolColorHex: UsageKeyConfiguration.defaultSymbolColorHex,
                showsInMenuBar: true,
                apiKey: "",
                baseURLMode: .inherited,
                baseURLOverride: ""
            ),
            authState: .notConfigured,
            snapshotFreshness: .empty
        )
        usageKeys.append(entry)
        persistUsageKeys()
        scheduleTimerIfNeeded()
        return keyID
    }

    func deleteKey(id: String) {
        guard usageKeys.count > 1 else { return }
        refreshTasks[id]?.cancel()
        refreshTasks[id] = nil
        usageKeys.removeAll { $0.id == id }
        persistUsageKeys()
        scheduleTimerIfNeeded()
    }

    func updateKeyConfiguration(
        id: String,
        name: String,
        symbolName: String,
        apiKey: String,
        baseURLMode: UsageKeyBaseURLMode,
        baseURLOverride: String
    ) {
        guard let current = usageKeys.first(where: { $0.id == id })?.configuration else { return }
        updateKeyConfiguration(
            id: id,
            name: name,
            symbolName: symbolName,
            symbolColorHex: current.symbolColorHex,
            showsInMenuBar: current.showsInMenuBar,
            apiKey: apiKey,
            baseURLMode: baseURLMode,
            baseURLOverride: baseURLOverride
        )
    }

    func updateKeyConfiguration(
        id: String,
        name: String,
        symbolName: String,
        symbolColorHex: String,
        showsInMenuBar: Bool,
        apiKey: String,
        baseURLMode: UsageKeyBaseURLMode,
        baseURLOverride: String
    ) {
        guard let index = usageKeys.firstIndex(where: { $0.id == id }) else { return }
        let previousFingerprint = fingerprint(for: usageKeys[index].configuration)
        let nextConfiguration = UsageKeyConfiguration(
            id: id,
            name: name,
            symbolName: symbolName,
            symbolColorHex: symbolColorHex,
            showsInMenuBar: showsInMenuBar,
            apiKey: apiKey,
            baseURLMode: baseURLMode,
            baseURLOverride: baseURLOverride
        ).normalized(index: index)

        usageKeys[index].configuration = nextConfiguration
        if index == 0 {
            if nextConfiguration.apiKey.isEmpty {
                userDefaults.removeObject(forKey: DefaultsKey.apiKey)
            } else {
                userDefaults.set(nextConfiguration.apiKey, forKey: DefaultsKey.apiKey)
            }
        }
        reconcileConfigurationChange(for: index, previousFingerprint: previousFingerprint)
        persistUsageKeys()
        scheduleTimerIfNeeded()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        Task { [weak self] in
            await self?.refreshOnLaunch()
        }
    }

    func validateAndRefresh() async throws {
        guard let firstID = usageKeys.first?.id else { throw UsageValidationError.missingAPIKey }
        try await refreshKey(id: firstID, configurationRequired: true)
    }

    func validateAndRefreshKey(id: String) async throws {
        try await refreshKey(id: id, configurationRequired: true)
    }

    func refreshNow() async {
        guard let firstID = usageKeys.first?.id else { return }
        do {
            try await refreshKey(id: firstID, configurationRequired: true)
        } catch {
            // The monitor state already contains the user-facing failure.
        }
    }

    func refreshCurrentKey(id: String) async {
        do {
            try await refreshKey(id: id, configurationRequired: true)
        } catch {
            // The monitor state already contains the user-facing failure.
        }
    }

    func refreshAll(configurationRequired: Bool = true) async {
        for id in usageKeys.map(\.id) {
            do {
                try await refreshKey(id: id, configurationRequired: configurationRequired)
            } catch {
                // Per-key failures are recorded on the entry and must not stop other keys.
            }
        }
    }

    func resolvedBaseURLText(for configuration: UsageKeyConfiguration) -> String {
        configuration.resolvedBaseURLText(defaultBaseURL: defaultBaseURLText)
    }

    private func refreshOnLaunch() async {
        await refreshAll(configurationRequired: false)
    }

    private func refreshFromTimer() async {
        guard !isTimerRefreshInFlight else { return }
        isTimerRefreshInFlight = true
        activeTimerRefreshCount += 1
        peakTimerRefreshCount = max(peakTimerRefreshCount, activeTimerRefreshCount)
        defer {
            activeTimerRefreshCount -= 1
            isTimerRefreshInFlight = false
        }
        await refreshAll(configurationRequired: false)
    }

    private func refreshKey(id: String, configurationRequired: Bool) async throws {
        guard let index = usageKeys.firstIndex(where: { $0.id == id }) else { return }
        if let task = refreshTasks[id] {
            _ = try await task.value
            return
        }

        let configuration = usageKeys[index].configuration
        if let validationError = validationError(for: configuration) {
            if configurationRequired {
                applyValidationFailure(validationError, for: id)
                throw validationError
            }
            return
        }

        guard
            let baseURL = validatedBaseURL(for: configuration),
            let fingerprint = fingerprint(for: configuration)
        else {
            if configurationRequired {
                let error = validationError(for: configuration) ?? UsageValidationError.missingBaseURL
                applyValidationFailure(error, for: id)
                throw error
            }
            return
        }

        let apiKeySnapshot = configuration.apiKey
        let task: Task<UsageResponse, Error> = Task { [client] in
            try await client.usage(baseURL: baseURL, apiKey: apiKeySnapshot)
        }
        refreshTasks[id] = task
        usageKeys[index].isRefreshing = true

        defer {
            refreshTasks[id] = nil
            if let latestIndex = usageKeys.firstIndex(where: { $0.id == id }) {
                usageKeys[latestIndex].isRefreshing = false
            }
        }

        do {
            let response = try await task.value
            applySuccessfulRefresh(response, keyID: id, fingerprint: fingerprint)
        } catch {
            applyRefreshFailure(error, keyID: id, fingerprint: fingerprint)
            throw error
        }
    }

    private func validatedBaseURL(for configuration: UsageKeyConfiguration) -> URL? {
        let text = configuration.resolvedBaseURLText(defaultBaseURL: defaultBaseURLText)
        guard
            let url = URL(string: text),
            let scheme = url.scheme?.lowercased(),
            (scheme == "http" || scheme == "https"),
            url.host != nil
        else {
            return nil
        }
        return url
    }

    private func fingerprint(for configuration: UsageKeyConfiguration) -> UsageConfigurationFingerprint? {
        UsageConfigurationFingerprint.make(
            baseURLText: configuration.resolvedBaseURLText(defaultBaseURL: defaultBaseURLText),
            apiKey: configuration.apiKey
        )
    }

    private func validationError(for configuration: UsageKeyConfiguration) -> UsageValidationError? {
        let baseURLText = configuration.resolvedBaseURLText(defaultBaseURL: defaultBaseURLText)
        if baseURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .missingBaseURL
        }
        if validatedBaseURL(for: configuration) == nil {
            return .invalidBaseURL
        }
        if configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .missingAPIKey
        }
        return nil
    }

    private func applyValidationFailure(_ error: UsageValidationError, for keyID: String) {
        guard let index = usageKeys.firstIndex(where: { $0.id == keyID }) else { return }
        usageKeys[index].lastError = error.userMessage
        usageKeys[index].lastFailureKind = .validation
        usageKeys[index].authState = .notConfigured
    }

    private func applySuccessfulRefresh(
        _ response: UsageResponse,
        keyID: String,
        fingerprint: UsageConfigurationFingerprint
    ) {
        guard
            let index = usageKeys.firstIndex(where: { $0.id == keyID }),
            fingerprint == self.fingerprint(for: usageKeys[index].configuration)
        else {
            return
        }

        let completedAt = now()
        usageKeys[index].snapshot = response
        usageKeys[index].lastSuccessfulRefresh = completedAt
        usageKeys[index].lastError = nil
        usageKeys[index].lastFailureKind = nil
        usageKeys[index].snapshotFreshness = .fresh
        usageKeys[index].authState = .authenticated
        persistSnapshot(response, keyID: keyID, fingerprint: fingerprint, savedAt: completedAt)
        updateThresholdAlertState(for: response, keyID: keyID, isRestored: false)
    }

    private func applyRefreshFailure(
        _ error: Error,
        keyID: String,
        fingerprint: UsageConfigurationFingerprint
    ) {
        guard
            let index = usageKeys.firstIndex(where: { $0.id == keyID }),
            fingerprint == self.fingerprint(for: usageKeys[index].configuration)
        else {
            return
        }

        let failureKind = failureKind(for: error)
        usageKeys[index].lastError = userMessage(for: error)
        usageKeys[index].lastFailureKind = failureKind

        switch failureKind {
        case .unauthorized:
            usageKeys[index].authState = .unauthorized
        case .validation:
            usageKeys[index].authState = .notConfigured
        case .network, .server, .decoding, .invalidResponse, .unknown:
            usageKeys[index].authState = .error
        }

        if usageKeys[index].snapshot == nil {
            usageKeys[index].snapshotFreshness = .empty
            usageKeys[index].thresholdAlertState = nil
            lastAlertSignatures[keyID] = nil
            return
        }

        usageKeys[index].snapshotFreshness = .stale
        if usageKeys[index].thresholdAlertState == nil, let snapshot = usageKeys[index].snapshot {
            updateThresholdAlertState(for: snapshot, keyID: keyID, isRestored: true)
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

    private func keyFingerprintsByID() -> [String: UsageConfigurationFingerprint?] {
        Dictionary(uniqueKeysWithValues: usageKeys.map { ($0.id, fingerprint(for: $0.configuration)) })
    }

    private func reconcileConfigurationChanges(previousFingerprints: [String: UsageConfigurationFingerprint?]) {
        for index in usageKeys.indices {
            let configuration = usageKeys[index].configuration
            let previousFingerprint = previousFingerprints[configuration.id] ?? nil
            reconcileConfigurationChange(for: index, previousFingerprint: previousFingerprint)
        }
        scheduleTimerIfNeeded()
    }

    private func reconcileConfigurationChange(for index: Int, previousFingerprint: UsageConfigurationFingerprint?) {
        let nextFingerprint = fingerprint(for: usageKeys[index].configuration)
        let keyID = usageKeys[index].id

        if previousFingerprint == nextFingerprint {
            if nextFingerprint != nil, usageKeys[index].snapshot == nil {
                usageKeys[index].snapshotFreshness = .empty
                usageKeys[index].authState = .ready
            }
            return
        }

        usageKeys[index].lastError = nil
        usageKeys[index].lastFailureKind = nil
        usageKeys[index].thresholdAlertState = nil
        lastAlertSignatures[keyID] = nil

        guard let nextFingerprint else {
            usageKeys[index].snapshot = nil
            usageKeys[index].lastSuccessfulRefresh = nil
            usageKeys[index].snapshotFreshness = .empty
            usageKeys[index].authState = .notConfigured
            return
        }

        if previousFingerprint == nil {
            usageKeys[index].snapshotFreshness = usageKeys[index].snapshot == nil ? .empty : usageKeys[index].snapshotFreshness
            usageKeys[index].authState = usageKeys[index].snapshot == nil ? .ready : usageKeys[index].authState
        } else if previousFingerprint != nextFingerprint {
            usageKeys[index].snapshot = nil
            usageKeys[index].lastSuccessfulRefresh = nil
            usageKeys[index].snapshotFreshness = .configurationMismatch
            usageKeys[index].authState = .ready
        } else if usageKeys[index].snapshot == nil {
            usageKeys[index].snapshotFreshness = .empty
            usageKeys[index].authState = .ready
        }
    }

    private func restorePersistedSnapshotsIfNeeded() {
        var keyedEntries = cacheStore.loadKeyedEntries()
        let legacyEntry = cacheStore.loadLegacyEntry()

        for index in usageKeys.indices {
            let keyID = usageKeys[index].id
            guard let currentFingerprint = fingerprint(for: usageKeys[index].configuration) else {
                usageKeys[index].snapshotFreshness = .empty
                usageKeys[index].authState = .notConfigured
                continue
            }

            let cachedEntry: UsageSnapshotCacheEntry?
            let shouldMoveLegacyEntry: Bool
            if let keyed = keyedEntries[keyID] {
                cachedEntry = keyed
                shouldMoveLegacyEntry = false
            } else if index == 0, let legacyEntry {
                cachedEntry = legacyEntry
                keyedEntries[keyID] = legacyEntry
                shouldMoveLegacyEntry = true
            } else {
                cachedEntry = nil
                shouldMoveLegacyEntry = false
            }

            guard let cachedEntry else {
                usageKeys[index].snapshotFreshness = .empty
                usageKeys[index].authState = .ready
                continue
            }

            guard cachedEntry.configurationFingerprint == currentFingerprint else {
                usageKeys[index].snapshot = nil
                usageKeys[index].lastSuccessfulRefresh = nil
                usageKeys[index].snapshotFreshness = .configurationMismatch
                usageKeys[index].authState = .ready
                continue
            }

            usageKeys[index].snapshot = cachedEntry.snapshot
            usageKeys[index].lastSuccessfulRefresh = cachedEntry.lastSuccessfulRefreshAt
            usageKeys[index].snapshotFreshness = .stale
            usageKeys[index].authState = .authenticated
            usageKeys[index].lastError = nil
            usageKeys[index].lastFailureKind = nil
            updateThresholdAlertState(for: cachedEntry.snapshot, keyID: keyID, isRestored: true)
            if shouldMoveLegacyEntry {
                cacheStore.save(cachedEntry, for: keyID)
            }
        }
    }

    private func persistSnapshot(
        _ response: UsageResponse,
        keyID: String,
        fingerprint: UsageConfigurationFingerprint,
        savedAt: Date
    ) {
        let entry = UsageSnapshotCacheEntry(
            configurationFingerprint: fingerprint,
            savedAt: savedAt,
            lastSuccessfulRefreshAt: savedAt,
            snapshot: response
        )
        cacheStore.save(entry, for: keyID)
    }

    private func updateThresholdAlertState(for snapshot: UsageResponse, keyID: String, isRestored: Bool) {
        guard let index = usageKeys.firstIndex(where: { $0.id == keyID }) else { return }
        let kinds = thresholdAlertKinds(for: snapshot)
        guard !kinds.isEmpty else {
            usageKeys[index].thresholdAlertState = nil
            lastAlertSignatures[keyID] = nil
            return
        }

        let isNew = !isRestored && kinds != lastAlertSignatures[keyID]
        usageKeys[index].thresholdAlertState = UsageThresholdAlertState(kinds: kinds, isNew: isNew)
        lastAlertSignatures[keyID] = kinds
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
        guard usageKeys.contains(where: { fingerprint(for: $0.configuration) != nil }) else {
            refreshTimer = nil
            return
        }

        refreshTimer = timerFactory.schedule(interval: TimeInterval(refreshIntervalSeconds)) { [weak self] in
            guard let monitor = self else { return }
            Task { @MainActor in
                await monitor.refreshFromTimer()
            }
        }
    }

    private func migrateOldLoginStorage() {
        userDefaults.removeObject(forKey: DefaultsKey.email)
        userDefaults.removeObject(forKey: DefaultsKey.selectedSubscriptionID)
    }

    private func migrateServiceStatusLayoutPreference() {
        userDefaults.set(ServiceStatusLayoutMode.verticalTwo.rawValue, forKey: DefaultsKey.serviceStatusLayoutMode)
    }

    private func loadUsageKeys() -> [UsageKeyEntry] {
        let storedConfigurations: [UsageKeyConfiguration]
        if let data = userDefaults.data(forKey: DefaultsKey.usageKeys),
           let decoded = try? JSONDecoder.sub2api.decode([UsageKeyConfiguration].self, from: data),
           !decoded.isEmpty {
            storedConfigurations = decoded
        } else {
            let legacyKey = userDefaults.string(forKey: DefaultsKey.apiKey) ?? ""
            storedConfigurations = [
                UsageKeyConfiguration(
                    name: "Key 1",
                    symbolName: UsageKeyConfiguration.defaultSymbolName,
                    apiKey: legacyKey,
                    baseURLMode: .inherited,
                    baseURLOverride: ""
                ),
            ]
        }

        let normalized = storedConfigurations.enumerated().map { index, configuration in
            configuration.normalized(index: index)
        }
        persistUsageKeyConfigurations(normalized)
        if let firstKey = normalized.first?.apiKey {
            if firstKey.isEmpty {
                userDefaults.removeObject(forKey: DefaultsKey.apiKey)
            } else {
                userDefaults.set(firstKey, forKey: DefaultsKey.apiKey)
            }
        }
        return normalized.map { configuration in
            UsageKeyEntry(configuration: configuration)
        }
    }

    private func persistUsageKeys() {
        persistUsageKeyConfigurations(usageKeys.map(\.configuration))
    }

    private func persistUsageKeyConfigurations(_ configurations: [UsageKeyConfiguration]) {
        guard let data = try? JSONEncoder.sub2api.encode(configurations) else { return }
        userDefaults.set(data, forKey: DefaultsKey.usageKeys)
    }

    private func menuBarText(for entry: UsageKeyEntry) -> String {
        if let snapshot = entry.snapshot, entry.canShowSnapshotData {
            return UsageFormatters.menuBarDailyUsageText(
                snapshot.subscription.dailyUsageUSD,
                showDecimals: showMenuBarDecimals
            )
        }

        guard fingerprint(for: entry.configuration) != nil else {
            return "未配置"
        }

        if entry.snapshotFreshness == .configurationMismatch {
            return "未验证"
        }

        if let failureKind = entry.lastFailureKind, failureKind == .unauthorized {
            return "未授权"
        }

        if entry.lastError != nil {
            return entry.lastFailureKind?.stateTextWithoutCache ?? "刷新失败"
        }

        return "未刷新"
    }

    private func statusLineText(for entry: UsageKeyEntry) -> String {
        if entry.isRefreshing {
            return "正在刷新"
        }

        switch entry.snapshotFreshness {
        case .fresh:
            return "数据已刷新"
        case .stale:
            if let lastFailureKind = entry.lastFailureKind {
                return lastFailureKind.stateTextWhenCached
            }
            return "缓存数据（等待刷新）"
        case .configurationMismatch:
            return "配置已变更，未验证"
        case .empty:
            if fingerprint(for: entry.configuration) == nil {
                return "未配置"
            }
            if let lastFailureKind = entry.lastFailureKind {
                return lastFailureKind.stateTextWithoutCache
            }
            return "未刷新"
        }
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
