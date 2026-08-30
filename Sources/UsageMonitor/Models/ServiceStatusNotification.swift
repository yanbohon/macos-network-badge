import Foundation

enum ServiceAvailability: Equatable {
    case available
    case unavailable

    init?(cellKind: ServiceStatusCellKind) {
        switch cellKind {
        case .green, .yellow:
            self = .available
        case .red:
            self = .unavailable
        case .gray:
            return nil
        }
    }
}

struct ServiceStatusChange: Equatable {
    let model: ServiceStatusModel
    let previousAvailability: ServiceAvailability
    let availability: ServiceAvailability
    let cellKind: ServiceStatusCellKind
    let probe: ServiceStatusProbe
}

@MainActor
protocol ServiceStatusNotificationSinking: AnyObject {
    func serviceStatusDidChange(_ change: ServiceStatusChange)
}
