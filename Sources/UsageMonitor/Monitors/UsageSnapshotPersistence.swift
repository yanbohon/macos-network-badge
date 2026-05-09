import Foundation
import CryptoKit

struct UsageConfigurationFingerprint: Codable, Equatable {
    let normalizedBaseURL: String
    let apiKeyFingerprint: String

    init(normalizedBaseURL: String, apiKeyFingerprint: String) {
        self.normalizedBaseURL = normalizedBaseURL
        self.apiKeyFingerprint = apiKeyFingerprint
    }

    static func make(baseURLText: String, apiKey: String) -> UsageConfigurationFingerprint? {
        let normalizedBaseURL = normalizeBaseURL(baseURLText)
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

    private static func normalizeBaseURL(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    private static func isValidBaseURL(_ value: String) -> Bool {
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

final class UsageSnapshotCacheStore {
    private let userDefaults: UserDefaults
    private let key: String

    init(userDefaults: UserDefaults, key: String) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func load() -> UsageSnapshotCacheEntry? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? JSONDecoder.sub2api.decode(UsageSnapshotCacheEntry.self, from: data)
    }

    func save(_ entry: UsageSnapshotCacheEntry) {
        guard let data = try? JSONEncoder.sub2api.encode(entry) else { return }
        userDefaults.set(data, forKey: key)
    }
}

