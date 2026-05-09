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

    static func truncatedCurrency(_ amount: Double) -> String {
        "$" + String(Int(amount))
    }

    static func menuBarDailyUsageText(_ amount: Double, showDecimals: Bool) -> String {
        showDecimals ? currency(amount) : truncatedCurrency(amount)
    }

    static func balanceText(_ remaining: Double) -> String {
        currency(remaining)
    }

    static func usageLimitText(used: Double, limit: Double) -> String {
        if limit == 0 {
            return "\(currency(used)) / ∞"
        }
        return "\(currency(used)) / \(currency(limit))"
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

    static func bucketText(_ bucket: UsageUsageBucket) -> String {
        "\(bucket.requestCount) 次 · \(integer(bucket.totalTokens)) tokens · \(currency(bucket.totalCostUSD))"
    }

    static func tokenBreakdownText(input: Int, output: Int) -> String {
        "输入 \(integer(input)) · 输出 \(integer(output))"
    }

    static func costBreakdownText(input: Double, output: Double) -> String {
        "输入 \(currency(input)) · 输出 \(currency(output))"
    }

    static func rateText(rpm: Double, tpm: Double) -> String {
        String(format: "RPM %.2f · TPM %.2f", rpm, tpm)
    }

    private static func integer(_ value: Int) -> String {
        integerFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
