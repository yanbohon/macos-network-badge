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
            return "立即提醒"
        case .timeSensitive:
            return "时效性"
        case .passive:
            return "静默"
        case .critical:
            return "重要警告"
        }
    }
}

struct BarkNotificationMessage: Equatable {
    let title: String
    let body: String
}

struct BarkNotificationConfiguration: Equatable {
    let serverURL: URL
    let deviceKey: String
    let level: BarkNotificationLevel
    let volume: Int?
    let group: String?
    let sound: String?
    let iconURL: String?
    let clickURL: String?
}

enum BarkNotificationDeliveryState: Equatable {
    case idle
    case sending
    case success(String)
    case failure(String)
}
