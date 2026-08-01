import Foundation

enum BarkNotificationLevel: String, CaseIterable, Identifiable {
    case active
    case timeSensitive
    case passive
    case critical

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active:
            return "立即"
        case .timeSensitive:
            return "时效"
        case .passive:
            return "静默"
        case .critical:
            return "警告"
        }
    }

    var systemImage: String {
        switch self {
        case .active:
            return "bell.fill"
        case .timeSensitive:
            return "clock.badge.exclamationmark"
        case .passive:
            return "bell.slash.fill"
        case .critical:
            return "exclamationmark.triangle.fill"
        }
    }

    var helpText: String {
        switch self {
        case .active:
            return "立即提醒"
        case .timeSensitive:
            return "时效性通知"
        case .passive:
            return "静默通知"
        case .critical:
            return "重要警告"
        }
    }
}

struct BarkNotificationTemplate: Codable, Equatable {
    var iconURLText: String
    var title: String
    var body: String

    private enum CodingKeys: String, CodingKey {
        case iconURLText
        case title
        case body
    }

    init(iconURLText: String, title: String, body: String) {
        self.iconURLText = iconURLText
        self.title = title
        self.body = body
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iconURLText = try container.decodeIfPresent(String.self, forKey: .iconURLText) ?? ""
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
    }
}

enum BarkNotificationTemplateVariable: String, CaseIterable {
    case group
    case model
    case status
    case latency
    case error

    var token: String {
        "{{\(rawValue)}}"
    }

    static var helpText: String {
        "可用变量：" + allCases.map(\.token).joined(separator: "、")
    }
}

enum BarkServiceNotificationKind: String {
    case available
    case unavailable

    var displayName: String {
        switch self {
        case .available:
            return "服务可用通知"
        case .unavailable:
            return "服务不可用通知"
        }
    }
}

struct BarkNotificationMessage: Equatable {
    let title: String
    let body: String
    let iconURL: String?

    init(
        title: String,
        body: String,
        iconURL: String? = nil
    ) {
        self.title = title
        self.body = body
        self.iconURL = iconURL
    }
}

struct BarkNotificationConfiguration: Equatable {
    let serverURL: URL
    let deviceKey: String
    let level: BarkNotificationLevel
    let volume: Int?
    let group: String?
}

enum BarkNotificationDeliveryState: Equatable {
    case idle
    case sending
    case success(String)
    case failure(String)
}
