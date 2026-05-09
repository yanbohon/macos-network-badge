import Foundation

struct UsageResponse: Decodable, Equatable {
    let isValid: Bool
    let mode: String
    let modelStats: [UsageModelStat]
    let planName: String
    let remaining: Double
    let subscription: UsageSubscription
    let unit: String
    let usage: UsageUsageSummary

    enum CodingKeys: String, CodingKey {
        case isValid
        case mode
        case modelStats = "model_stats"
        case planName
        case planNameSnake = "plan_name"
        case remaining
        case subscription
        case unit
        case usage
    }

    init(
        isValid: Bool,
        mode: String,
        modelStats: [UsageModelStat],
        planName: String,
        remaining: Double,
        subscription: UsageSubscription,
        unit: String,
        usage: UsageUsageSummary
    ) {
        self.isValid = isValid
        self.mode = mode
        self.modelStats = modelStats
        self.planName = planName
        self.remaining = remaining
        self.subscription = subscription
        self.unit = unit
        self.usage = usage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isValid = try container.decode(Bool.self, forKey: .isValid)
        mode = try container.decode(String.self, forKey: .mode)
        modelStats = try container.decodeIfPresent([UsageModelStat].self, forKey: .modelStats) ?? []
        planName = try container.decodeFlexibleString(forKeys: [.planName, .planNameSnake])
        remaining = try container.decodeFlexibleDouble(forKey: .remaining)
        subscription = try container.decode(UsageSubscription.self, forKey: .subscription)
        unit = try container.decode(String.self, forKey: .unit)
        usage = try container.decode(UsageUsageSummary.self, forKey: .usage)
    }
}

struct UsageModelStat: Decodable, Equatable {
    let modelName: String
    let requestCount: Int
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    let inputCostUSD: Double
    let outputCostUSD: Double
    let totalCostUSD: Double

    enum CodingKeys: String, CodingKey {
        case model
        case modelName = "model_name"
        case name
        case requestCount = "request_count"
        case requests
        case count
        case inputTokens = "input_tokens"
        case promptTokens = "prompt_tokens"
        case outputTokens = "output_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case tokens
        case inputCostUSD = "input_cost_usd"
        case inputCost = "input_cost"
        case outputCostUSD = "output_cost_usd"
        case outputCost = "output_cost"
        case totalCostUSD = "total_cost_usd"
        case totalCost = "total_cost"
        case cost
    }

    init(
        modelName: String,
        requestCount: Int,
        inputTokens: Int,
        outputTokens: Int,
        totalTokens: Int,
        inputCostUSD: Double,
        outputCostUSD: Double,
        totalCostUSD: Double
    ) {
        self.modelName = modelName
        self.requestCount = requestCount
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.inputCostUSD = inputCostUSD
        self.outputCostUSD = outputCostUSD
        self.totalCostUSD = totalCostUSD
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelName = try container.decodeFlexibleString(forKeys: [.model, .modelName, .name])
        requestCount = try container.decodeFlexibleInt(forKeys: [.requestCount, .requests, .count], default: 0)
        inputTokens = try container.decodeFlexibleInt(forKeys: [.inputTokens, .promptTokens], default: 0)
        outputTokens = try container.decodeFlexibleInt(forKeys: [.outputTokens, .completionTokens], default: 0)
        totalTokens = try container.decodeFlexibleInt(
            forKeys: [.totalTokens, .tokens],
            default: inputTokens + outputTokens
        )
        inputCostUSD = try container.decodeFlexibleDouble(forKeys: [.inputCostUSD, .inputCost], default: 0)
        outputCostUSD = try container.decodeFlexibleDouble(forKeys: [.outputCostUSD, .outputCost], default: 0)
        totalCostUSD = try container.decodeFlexibleDouble(
            forKeys: [.totalCostUSD, .totalCost, .cost],
            default: inputCostUSD + outputCostUSD
        )
    }
}

struct UsageSubscription: Decodable, Equatable {
    let dailyUsageUSD: Double
    let dailyLimitUSD: Double
    let weeklyUsageUSD: Double
    let weeklyLimitUSD: Double
    let monthlyUsageUSD: Double
    let monthlyLimitUSD: Double
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case dailyUsageUSD = "daily_usage_usd"
        case dailyLimitUSD = "daily_limit_usd"
        case weeklyUsageUSD = "weekly_usage_usd"
        case weeklyLimitUSD = "weekly_limit_usd"
        case monthlyUsageUSD = "monthly_usage_usd"
        case monthlyLimitUSD = "monthly_limit_usd"
        case expiresAt = "expires_at"
    }

    init(
        dailyUsageUSD: Double,
        dailyLimitUSD: Double,
        weeklyUsageUSD: Double,
        weeklyLimitUSD: Double,
        monthlyUsageUSD: Double,
        monthlyLimitUSD: Double,
        expiresAt: Date?
    ) {
        self.dailyUsageUSD = dailyUsageUSD
        self.dailyLimitUSD = dailyLimitUSD
        self.weeklyUsageUSD = weeklyUsageUSD
        self.weeklyLimitUSD = weeklyLimitUSD
        self.monthlyUsageUSD = monthlyUsageUSD
        self.monthlyLimitUSD = monthlyLimitUSD
        self.expiresAt = expiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dailyUsageUSD = try container.decodeFlexibleDouble(forKey: .dailyUsageUSD)
        dailyLimitUSD = try container.decodeFlexibleDouble(forKey: .dailyLimitUSD)
        weeklyUsageUSD = try container.decodeFlexibleDouble(forKey: .weeklyUsageUSD)
        weeklyLimitUSD = try container.decodeFlexibleDouble(forKey: .weeklyLimitUSD)
        monthlyUsageUSD = try container.decodeFlexibleDouble(forKey: .monthlyUsageUSD)
        monthlyLimitUSD = try container.decodeFlexibleDouble(forKey: .monthlyLimitUSD)
        if let rawDate = try container.decodeIfPresent(String.self, forKey: .expiresAt) {
            expiresAt = DateParsers.iso8601(rawDate)
        } else {
            expiresAt = nil
        }
    }
}

struct UsageUsageSummary: Decodable, Equatable {
    let today: UsageUsageBucket
    let total: UsageUsageBucket
    let averageDurationMS: Double
    let rpm: Double
    let tpm: Double

    enum CodingKeys: String, CodingKey {
        case today
        case total
        case averageDurationMS = "average_duration_ms"
        case rpm
        case tpm
    }

    init(
        today: UsageUsageBucket,
        total: UsageUsageBucket,
        averageDurationMS: Double,
        rpm: Double,
        tpm: Double
    ) {
        self.today = today
        self.total = total
        self.averageDurationMS = averageDurationMS
        self.rpm = rpm
        self.tpm = tpm
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        today = try container.decode(UsageUsageBucket.self, forKey: .today)
        total = try container.decode(UsageUsageBucket.self, forKey: .total)
        averageDurationMS = try container.decodeFlexibleDouble(forKey: .averageDurationMS)
        rpm = try container.decodeFlexibleDouble(forKey: .rpm)
        tpm = try container.decodeFlexibleDouble(forKey: .tpm)
    }
}

struct UsageUsageBucket: Decodable, Equatable {
    let requestCount: Int
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    let inputCostUSD: Double
    let outputCostUSD: Double
    let totalCostUSD: Double

    enum CodingKeys: String, CodingKey {
        case requestCount = "request_count"
        case requests
        case count
        case inputTokens = "input_tokens"
        case promptTokens = "prompt_tokens"
        case outputTokens = "output_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case tokens
        case inputCostUSD = "input_cost_usd"
        case inputCost = "input_cost"
        case outputCostUSD = "output_cost_usd"
        case outputCost = "output_cost"
        case totalCostUSD = "total_cost_usd"
        case totalCost = "total_cost"
        case cost
    }

    init(
        requestCount: Int,
        inputTokens: Int,
        outputTokens: Int,
        totalTokens: Int,
        inputCostUSD: Double,
        outputCostUSD: Double,
        totalCostUSD: Double
    ) {
        self.requestCount = requestCount
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.inputCostUSD = inputCostUSD
        self.outputCostUSD = outputCostUSD
        self.totalCostUSD = totalCostUSD
    }

    init(from decoder: Decoder) throws {
        if let costOnly = try? decoder.singleValueContainer().decodeFlexibleDouble() {
            requestCount = 0
            inputTokens = 0
            outputTokens = 0
            totalTokens = 0
            inputCostUSD = 0
            outputCostUSD = 0
            totalCostUSD = costOnly
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestCount = try container.decodeFlexibleInt(forKeys: [.requestCount, .requests, .count], default: 0)
        inputTokens = try container.decodeFlexibleInt(forKeys: [.inputTokens, .promptTokens], default: 0)
        outputTokens = try container.decodeFlexibleInt(forKeys: [.outputTokens, .completionTokens], default: 0)
        totalTokens = try container.decodeFlexibleInt(
            forKeys: [.totalTokens, .tokens],
            default: inputTokens + outputTokens
        )
        inputCostUSD = try container.decodeFlexibleDouble(forKeys: [.inputCostUSD, .inputCost], default: 0)
        outputCostUSD = try container.decodeFlexibleDouble(forKeys: [.outputCostUSD, .outputCost], default: 0)
        totalCostUSD = try container.decodeFlexibleDouble(
            forKeys: [.totalCostUSD, .totalCost, .cost],
            default: inputCostUSD + outputCostUSD
        )
    }
}

extension JSONDecoder {
    static var sub2api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = DateParsers.iso8601(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO8601 date"
                )
            }
            return date
        }
        return decoder
    }
}

private enum DateParsers {
    static func iso8601(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleString(forKeys keys: [Key]) throws -> String {
        for key in keys {
            if let value = try? decode(String.self, forKey: key) {
                return value
            }
            if let value = try? decode(Int.self, forKey: key) {
                return String(value)
            }
            if let value = try? decode(Double.self, forKey: key) {
                return String(value)
            }
        }
        return try decode(String.self, forKey: keys[0])
    }

    func decodeFlexibleDouble(forKey key: Key) throws -> Double {
        try decodeFlexibleDouble(forKeys: [key])
    }

    func decodeFlexibleDouble(forKeys keys: [Key], default defaultValue: Double? = nil) throws -> Double {
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
        if let defaultValue {
            return defaultValue
        }
        return try decode(Double.self, forKey: keys[0])
    }

    func decodeFlexibleInt(forKeys keys: [Key], default defaultValue: Int? = nil) throws -> Int {
        for key in keys {
            if let value = try? decode(Int.self, forKey: key) {
                return value
            }
            if let value = try? decode(Double.self, forKey: key) {
                return Int(value)
            }
            if let value = try? decode(String.self, forKey: key),
               let double = Double(value) {
                return Int(double)
            }
        }
        if let defaultValue {
            return defaultValue
        }
        return try decode(Int.self, forKey: keys[0])
    }
}

private extension SingleValueDecodingContainer {
    func decodeFlexibleDouble() throws -> Double {
        if let value = try? decode(Double.self) {
            return value
        }
        if let value = try? decode(Int.self) {
            return Double(value)
        }
        if let value = try? decode(String.self),
           let double = Double(value) {
            return double
        }
        return try decode(Double.self)
    }
}
