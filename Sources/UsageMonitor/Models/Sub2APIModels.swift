import Foundation

struct Sub2APILoginEnvelope: Decodable {
    let code: Int
    let message: String?
    let data: Sub2APILoginData?
}

struct Sub2APILoginData: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval
    let tokenType: String
    let user: Sub2APIUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case user
    }
}

struct Sub2APIUser: Decodable, Equatable {
    let id: Int
    let email: String
    let balance: Double
    let status: String
}

struct Sub2APISubscriptionsEnvelope: Decodable {
    let code: Int
    let message: String?
    let data: [Sub2APISubscription]
}

struct Sub2APISubscription: Decodable, Equatable, Identifiable {
    let id: String
    let status: String
    let usedTodayUSD: Double
    let usedWeekUSD: Double
    let usedMonthUSD: Double
    let expiresAt: Date?
    let group: Sub2APIGroup

    var isActive: Bool {
        status == "active"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case usedTodayUSD = "used_today_usd"
        case usedWeekUSD = "used_week_usd"
        case usedMonthUSD = "used_month_usd"
        case dailyUsageUSD = "daily_usage_usd"
        case weeklyUsageUSD = "weekly_usage_usd"
        case monthlyUsageUSD = "monthly_usage_usd"
        case expiresAt = "expires_at"
        case group
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeFlexibleString(forKey: .id)
        status = try container.decode(String.self, forKey: .status)
        usedTodayUSD = try container.decodeFlexibleDouble(forKeys: [.usedTodayUSD, .dailyUsageUSD])
        usedWeekUSD = try container.decodeFlexibleDouble(forKeys: [.usedWeekUSD, .weeklyUsageUSD])
        usedMonthUSD = try container.decodeFlexibleDouble(forKeys: [.usedMonthUSD, .monthlyUsageUSD])
        group = try container.decode(Sub2APIGroup.self, forKey: .group)
        if let rawDate = try container.decodeIfPresent(String.self, forKey: .expiresAt) {
            expiresAt = DateParsers.iso8601(rawDate)
        } else {
            expiresAt = nil
        }
    }
}

struct Sub2APIGroup: Decodable, Equatable {
    let name: String
    let platform: String
    let dailyLimitUSD: Double
    let weeklyLimitUSD: Double
    let monthlyLimitUSD: Double

    enum CodingKeys: String, CodingKey {
        case name
        case platform
        case dailyLimitUSD = "daily_limit_usd"
        case weeklyLimitUSD = "weekly_limit_usd"
        case monthlyLimitUSD = "monthly_limit_usd"
    }
}

struct SubscriptionCatalog: Equatable {
    let all: [Sub2APISubscription]

    var active: [Sub2APISubscription] {
        all.filter(\.isActive)
    }

    var inactiveCount: Int {
        all.count - active.count
    }

    func selectedSubscription(id: String?) -> Sub2APISubscription? {
        let activeSubscriptions = active
        if let id, let match = activeSubscriptions.first(where: { $0.id == id }) {
            return match
        }
        if let id, all.contains(where: { $0.id == id && !$0.isActive }) {
            return nil
        }
        return activeSubscriptions.first
    }
}

extension JSONDecoder {
    static var sub2api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private enum DateParsers {
    static func iso8601(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Double.self, forKey: key) {
            return String(value)
        }
        return try decode(String.self, forKey: key)
    }

    func decodeFlexibleDouble(forKeys keys: [Key]) throws -> Double {
        for key in keys {
            if let value = try? decode(Double.self, forKey: key) {
                return value
            }
            if let value = try? decode(Int.self, forKey: key) {
                return Double(value)
            }
            if let value = try? decode(String.self, forKey: key),
               let double = Double(value) {
                return double
            }
        }
        return try decode(Double.self, forKey: keys[0])
    }
}
