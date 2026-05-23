import Foundation
import CryptoKit

enum UsageKeyBaseURLMode: String, Codable, CaseIterable, Equatable {
    case inherited
    case independent

    var displayName: String {
        switch self {
        case .inherited:
            return "继承全局 Base URL"
        case .independent:
            return "独立 Base URL"
        }
    }
}

struct UsageKeyConfiguration: Codable, Equatable, Identifiable {
    static let defaultSymbolName = "key.fill"
    static let defaultSymbolColorHex = "#FFFFFF"

    let id: String
    var name: String
    var symbolName: String
    var symbolColorHex: String
    var showsInMenuBar: Bool
    var apiKey: String
    var baseURLMode: UsageKeyBaseURLMode
    var baseURLOverride: String

    init(
        id: String = UUID().uuidString,
        name: String,
        symbolName: String = Self.defaultSymbolName,
        symbolColorHex: String = Self.defaultSymbolColorHex,
        showsInMenuBar: Bool = true,
        apiKey: String = "",
        baseURLMode: UsageKeyBaseURLMode = .inherited,
        baseURLOverride: String = ""
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.symbolColorHex = Self.normalizedSymbolColorHex(symbolColorHex)
        self.showsInMenuBar = showsInMenuBar
        self.apiKey = apiKey
        self.baseURLMode = baseURLMode
        self.baseURLOverride = baseURLOverride
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case symbolName
        case symbolColorHex
        case showsInMenuBar
        case apiKey
        case baseURLMode
        case baseURLOverride
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        symbolName = try container.decodeIfPresent(String.self, forKey: .symbolName) ?? Self.defaultSymbolName
        let decodedSymbolColorHex = try container.decodeIfPresent(String.self, forKey: .symbolColorHex)
            ?? Self.defaultSymbolColorHex
        symbolColorHex = Self.normalizedSymbolColorHex(decodedSymbolColorHex)
        showsInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showsInMenuBar) ?? true
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        baseURLMode = try container.decodeIfPresent(UsageKeyBaseURLMode.self, forKey: .baseURLMode) ?? .inherited
        baseURLOverride = try container.decodeIfPresent(String.self, forKey: .baseURLOverride) ?? ""
    }

    func normalized(index: Int) -> UsageKeyConfiguration {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSymbol = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOverride = baseURLMode == .independent
            ? Self.normalizedBaseURL(baseURLOverride)
            : ""
        return UsageKeyConfiguration(
            id: id,
            name: trimmedName.isEmpty ? "Key \(index + 1)" : trimmedName,
            symbolName: trimmedSymbol.isEmpty ? Self.defaultSymbolName : trimmedSymbol,
            symbolColorHex: Self.normalizedSymbolColorHex(symbolColorHex),
            showsInMenuBar: showsInMenuBar,
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURLMode: baseURLMode,
            baseURLOverride: normalizedOverride
        )
    }

    func resolvedBaseURLText(defaultBaseURL: String) -> String {
        switch baseURLMode {
        case .inherited:
            return Self.normalizedBaseURL(defaultBaseURL)
        case .independent:
            return Self.normalizedBaseURL(baseURLOverride)
        }
    }

    static func normalizedBaseURL(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    static func normalizedSymbolColorHex(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard hex.count == 6, hex.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return defaultSymbolColorHex
        }
        return "#\(hex)"
    }
}

struct UsageKeyEntry: Equatable, Identifiable {
    var configuration: UsageKeyConfiguration
    var snapshot: UsageResponse?
    var lastSuccessfulRefresh: Date?
    var lastError: String?
    var lastFailureKind: UsageRefreshFailureKind?
    var isRefreshing: Bool
    var authState: UsageAuthState
    var snapshotFreshness: UsageSnapshotFreshness
    var thresholdAlertState: UsageThresholdAlertState?

    init(
        configuration: UsageKeyConfiguration,
        snapshot: UsageResponse? = nil,
        lastSuccessfulRefresh: Date? = nil,
        lastError: String? = nil,
        lastFailureKind: UsageRefreshFailureKind? = nil,
        isRefreshing: Bool = false,
        authState: UsageAuthState = .notConfigured,
        snapshotFreshness: UsageSnapshotFreshness = .empty,
        thresholdAlertState: UsageThresholdAlertState? = nil
    ) {
        self.configuration = configuration
        self.snapshot = snapshot
        self.lastSuccessfulRefresh = lastSuccessfulRefresh
        self.lastError = lastError
        self.lastFailureKind = lastFailureKind
        self.isRefreshing = isRefreshing
        self.authState = authState
        self.snapshotFreshness = snapshotFreshness
        self.thresholdAlertState = thresholdAlertState
    }

    var id: String {
        configuration.id
    }

    var canShowSnapshotData: Bool {
        snapshot != nil && snapshotFreshness != .configurationMismatch
    }
}

struct UsageConfigurationFingerprint: Codable, Equatable {
    let normalizedBaseURL: String
    let apiKeyFingerprint: String

    init(normalizedBaseURL: String, apiKeyFingerprint: String) {
        self.normalizedBaseURL = normalizedBaseURL
        self.apiKeyFingerprint = apiKeyFingerprint
    }

    static func make(baseURLText: String, apiKey: String) -> UsageConfigurationFingerprint? {
        let normalizedBaseURL = UsageKeyConfiguration.normalizedBaseURL(baseURLText)
        guard
            !normalizedBaseURL.isEmpty,
            isValidBaseURL(normalizedBaseURL),
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return UsageConfigurationFingerprint(
            normalizedBaseURL: normalizedBaseURL,
            apiKeyFingerprint: fingerprint(for: apiKey)
        )
    }

    static func isValidBaseURL(_ value: String) -> Bool {
        guard
            let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            (scheme == "http" || scheme == "https"),
            url.host != nil
        else {
            return false
        }
        return true
    }

    private static func fingerprint(for apiKey: String) -> String {
        let digest = SHA256.hash(data: Data(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum UsageSnapshotFreshness: Equatable {
    case fresh
    case stale
    case configurationMismatch
    case empty
}

enum UsageRefreshFailureKind: Equatable {
    case unauthorized
    case network
    case server
    case decoding
    case invalidResponse
    case validation
    case unknown

    var preservesMatchingCache: Bool {
        switch self {
        case .validation:
            return false
        case .unauthorized, .network, .server, .decoding, .invalidResponse, .unknown:
            return true
        }
    }

    var stateTextWhenCached: String {
        switch self {
        case .unauthorized:
            return "认证失败，缓存已过期"
        case .network:
            return "网络失败，缓存已过期"
        case .server:
            return "服务端失败，缓存已过期"
        case .decoding:
            return "响应异常，缓存已过期"
        case .invalidResponse:
            return "无效响应，缓存已过期"
        case .validation, .unknown:
            return "缓存已过期"
        }
    }

    var stateTextWithoutCache: String {
        switch self {
        case .unauthorized:
            return "未授权"
        case .network, .server, .decoding, .invalidResponse, .unknown:
            return "刷新失败"
        case .validation:
            return "未配置"
        }
    }
}

enum UsageThresholdAlertKind: String, Codable, CaseIterable, Comparable {
    case dailyUsage80
    case dailyUsage95
    case lowBalance
    case subscriptionExpired
    case subscriptionExpiringSoon

    var sortOrder: Int {
        switch self {
        case .dailyUsage95:
            return 0
        case .dailyUsage80:
            return 1
        case .subscriptionExpired:
            return 2
        case .subscriptionExpiringSoon:
            return 3
        case .lowBalance:
            return 4
        }
    }

    var message: String {
        switch self {
        case .dailyUsage80:
            return "今日用量已达 80%"
        case .dailyUsage95:
            return "今日用量已达 95%"
        case .lowBalance:
            return "剩余余额偏低"
        case .subscriptionExpired:
            return "订阅已过期"
        case .subscriptionExpiringSoon:
            return "订阅即将到期"
        }
    }

    static func < (lhs: UsageThresholdAlertKind, rhs: UsageThresholdAlertKind) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

struct UsageThresholdAlertState: Equatable {
    let kinds: [UsageThresholdAlertKind]
    let isNew: Bool

    var primaryMessage: String? {
        kinds.first?.message
    }

    var messages: [String] {
        kinds.map(\.message)
    }
}

struct UsageSnapshotCacheEntry: Codable, Equatable {
    let configurationFingerprint: UsageConfigurationFingerprint
    let savedAt: Date
    let lastSuccessfulRefreshAt: Date
    let snapshot: UsageResponse
}

struct KeyedUsageSnapshotCacheEntry: Codable, Equatable {
    let keyID: String
    let configurationFingerprint: UsageConfigurationFingerprint
    let savedAt: Date
    let lastSuccessfulRefreshAt: Date
    let snapshot: UsageResponse

    var legacyEntry: UsageSnapshotCacheEntry {
        UsageSnapshotCacheEntry(
            configurationFingerprint: configurationFingerprint,
            savedAt: savedAt,
            lastSuccessfulRefreshAt: lastSuccessfulRefreshAt,
            snapshot: snapshot
        )
    }
}

final class UsageSnapshotCacheStore {
    private let userDefaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults, key: String) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func loadLegacyEntry() -> UsageSnapshotCacheEntry? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder.sub2api.decode(UsageSnapshotCacheEntry.self, from: data)
    }

    func loadKeyedEntries() -> [String: UsageSnapshotCacheEntry] {
        guard let data = userDefaults.data(forKey: key) else { return [:] }
        if let keyedEntries = try? JSONDecoder.sub2api.decode([KeyedUsageSnapshotCacheEntry].self, from: data) {
            return Dictionary(uniqueKeysWithValues: keyedEntries.map { ($0.keyID, $0.legacyEntry) })
        }
        return [:]
    }

    func save(_ entry: UsageSnapshotCacheEntry, for keyID: String) {
        var entries = loadKeyedEntries()
        entries[keyID] = entry
        let keyedEntries = entries.map { keyID, entry in
            KeyedUsageSnapshotCacheEntry(
                keyID: keyID,
                configurationFingerprint: entry.configurationFingerprint,
                savedAt: entry.savedAt,
                lastSuccessfulRefreshAt: entry.lastSuccessfulRefreshAt,
                snapshot: entry.snapshot
            )
        }
        guard let data = try? JSONEncoder.sub2api.encode(keyedEntries) else { return }
        userDefaults.set(data, forKey: key)
    }
}
