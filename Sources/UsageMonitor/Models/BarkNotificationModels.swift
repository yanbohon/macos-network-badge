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
    var clickURLText: String
    var title: String
    var body: String
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
    let clickURL: String?

    init(title: String, body: String, clickURL: String? = nil) {
        self.title = title
        self.body = body
        self.clickURL = clickURL
    }
}

struct BarkNotificationConfiguration: Equatable {
    let serverURL: URL
    let deviceKey: String
    let level: BarkNotificationLevel
    let volume: Int?
    let group: String?
    let iconURL: String?
}

enum BarkNotificationDeliveryState: Equatable {
    case idle
    case sending
    case success(String)
    case failure(String)
}
