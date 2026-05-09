import Foundation

enum UsageHealthState: Equatable {
    case normal
    case warning
    case danger
}

enum UsageFormatters {
    static func currency(_ amount: Double) -> String {
        "$" + String(format: "%.2f", amount)
    }

    static func dailyUsageText(used: Double, limit: Double) -> String {
        if limit == 0 {
            return "\(currency(used))/∞"
        }
        return "\(currency(used))/\(currency(limit))"
    }

    static func compactDailyUsageText(used: Double, limit: Double) -> String {
        if limit == 0 {
            return "\(currency(used))\n∞"
        }
        return "\(currency(used))\n\(currency(limit))"
    }

    static func percentage(used: Double, limit: Double) -> Double? {
        guard limit > 0 else { return nil }
        return used / limit
    }

    static func percentageText(used: Double, limit: Double) -> String {
        guard let percentage = percentage(used: used, limit: limit) else {
            return "不限量"
        }
        return String(format: "%.1f%%", percentage * 100)
    }

    static func remainingText(used: Double, limit: Double) -> String {
        guard limit > 0 else { return "∞" }
        return currency(max(0, limit - used))
    }

    static func healthState(used: Double, limit: Double) -> UsageHealthState {
        guard let percentage = percentage(used: used, limit: limit) else {
            return .normal
        }
        if percentage >= 0.95 {
            return .danger
        }
        if percentage >= 0.80 {
            return .warning
        }
        return .normal
    }

    static func expiryText(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "未设置到期时间" }
        if date < now { return "已过期" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
