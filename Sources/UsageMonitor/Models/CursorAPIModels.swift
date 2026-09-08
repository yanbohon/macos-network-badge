import Foundation

enum CursorSessionToken {
    static func normalizedAccessToken(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let decoded = trimmed.removingPercentEncoding ?? trimmed
        if let separator = decoded.range(of: "::") {
            return String(decoded[separator.upperBound...])
        }
        return decoded
    }

    static func jwtPayload(from accessToken: String) -> [String: Any]? {
        let token = normalizedAccessToken(accessToken)
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        switch payload.count % 4 {
        case 2:
            payload += "=="
        case 3:
            payload += "="
        default:
            break
        }

        guard
            let data = Data(base64Encoded: payload),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return object
    }

    static func workosUserID(from accessToken: String) -> String? {
        let trimmed = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        if let separator = decoded.range(of: "::") {
            let prefix = String(decoded[..<separator.lowerBound])
            if prefix.hasPrefix("user_") {
                return prefix
            }
        }

        guard let sub = jwtPayload(from: accessToken)?["sub"] as? String else {
            return nil
        }
        let userID = sub.split(separator: "|").last.map(String.init) ?? sub
        return userID.hasPrefix("user_") ? userID : nil
    }

    static func sessionCookie(from accessToken: String) -> String? {
        let token = normalizedAccessToken(accessToken)
        guard !token.isEmpty, let userID = workosUserID(from: accessToken) else {
            return nil
        }
        return "WorkosCursorSessionToken=\(userID)%3A%3A\(token)"
    }

    static func exportableAccessToken(from accessToken: String) -> String {
        let token = normalizedAccessToken(accessToken)
        guard !token.isEmpty else { return "" }
        guard let userID = workosUserID(from: accessToken) else {
            return token
        }
        if token.hasPrefix("\(userID)::") {
            return token
        }
        return "\(userID)::\(token)"
    }

    static func expiration(from accessToken: String) -> Date? {
        let exp: Int?
        if let value = jwtPayload(from: accessToken)?["exp"] as? Int {
            exp = value
        } else if let value = jwtPayload(from: accessToken)?["exp"] as? Double {
            exp = Int(value)
        } else {
            exp = nil
        }
        return exp.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    static func needsRefresh(
        _ accessToken: String,
        now: Date = Date(),
        threshold: TimeInterval = 5 * 60
    ) -> Bool {
        guard let expiration = expiration(from: accessToken) else {
            return true
        }
        return expiration.timeIntervalSince(now) <= threshold
    }
}

struct CursorUsageSummary: Equatable {
    var autoPercentUsed: Double?
    var apiPercentUsed: Double?
    var membershipType: String?
    var billingCycleEnd: Date?

    static func parse(from data: Data) throws -> CursorUsageSummary {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw CursorAPIClientError.decoding
        }

        let plan =
            nestedObject(root, "individualUsage", "plan")
            ?? nestedObject(root, "individual_usage", "plan")
            ?? objectValue(root["planUsage"])
            ?? objectValue(root["plan_usage"])

        return CursorUsageSummary(
            autoPercentUsed: pickNumber(plan, "autoPercentUsed", "auto_percent_used"),
            apiPercentUsed: pickNumber(plan, "apiPercentUsed", "api_percent_used"),
            membershipType: pickString(root, "membershipType", "membership_type"),
            billingCycleEnd: pickDate(root, "billingCycleEnd", "billing_cycle_end")
        )
    }

    static func displayPercent(from raw: Double) -> Int {
        let base = raw > 0 && raw < 1 ? 1 : raw
        return Int(min(100, max(0, base)).rounded())
    }

    static func billingCycleEndText(from date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        if date < now {
            return "已到期"
        }
        return "到期 \(date.formatted(date: .abbreviated, time: .omitted))"
    }

    static func membershipDisplayName(from raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        switch normalizedMembershipKey(raw) {
        case "team", "teams", "business", "enterprise":
            return "Team"
        default:
            return trimmed
        }
    }

    static func membershipColorHex(from raw: String?) -> String? {
        guard membershipDisplayName(from: raw) != nil else { return nil }
        switch normalizedMembershipKey(raw) {
        case "free", "hobby":
            return "#94A3B8"
        case "free_trial", "pro_trial", "trial":
            return "#FB7185"
        case "pro":
            return "#38BDF8"
        case "pro_plus", "proplus":
            return "#34D399"
        case "ultra":
            return "#FBBF24"
        case "team", "teams", "business", "enterprise":
            return "#A78BFA"
        default:
            return "#94A3B8"
        }
    }

    private static func normalizedMembershipKey(_ raw: String?) -> String {
        (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}

struct CursorSandUsageStatus: Equatable {
    var usagePercent: Double?
    var hasNonZeroIncludedLimit: Bool
    var planLabel: String?
    var nextReset: Date?

    var shouldShowRing: Bool {
        hasNonZeroIncludedLimit && usagePercent != nil
    }

    static func parse(from data: Data) throws -> CursorSandUsageStatus {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw CursorAPIClientError.decoding
        }

        return CursorSandUsageStatus(
            usagePercent: pickNumber(root, "usagePercent", "usage_percent"),
            hasNonZeroIncludedLimit: pickBool(root, "hasNonZeroIncludedLimit", "has_non_zero_included_limit") ?? false,
            planLabel: pickString(root, "grokPlanLabel", "grok_plan_label", "planLabel", "plan_label"),
            nextReset: pickDate(root, "nextResetTimestampUtc", "next_reset_timestamp_utc")
        )
    }
}

struct CursorTeamExtractionUsage: Equatable {
    var email: String?
    var membershipType: String?
    var autoPercentUsed: Double?
    var sandPercentUsed: Double?
    var sandHasAllowance: Bool
    var sandPlanLabel: String?
    var sandResetAt: Date?

    static func parse(from data: Data) throws -> CursorTeamExtractionUsage {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw CursorAPIClientError.decoding
        }

        let results = root["results"] as? [[String: Any]] ?? []
        guard let first = results.first else {
            throw CursorAPIClientError.decoding
        }

        let cursorModels = objectValue(first["cursorModels"]) ?? objectValue(first["cursor_models"])
        let grokBot = objectValue(first["grokBot"]) ?? objectValue(first["grok_bot"])

        return CursorTeamExtractionUsage(
            email: pickString(first, "email"),
            membershipType: pickString(first, "membershipType", "membership_type"),
            autoPercentUsed: pickNumber(cursorModels, "usedPercent", "used_percent"),
            sandPercentUsed: pickNumber(grokBot, "usedPercent", "used_percent"),
            sandHasAllowance: pickBool(grokBot ?? [:], "hasAllowance", "has_allowance") ?? false,
            sandPlanLabel: pickString(grokBot, "planLabel", "plan_label"),
            sandResetAt: pickDate(grokBot ?? [:], "resetAt", "reset_at")
        )
    }
}

struct CursorUserMeta: Equatable {
    var email: String?
    var workosID: String?

    static func parse(from data: Data) throws -> CursorUserMeta {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw CursorAPIClientError.decoding
        }
        return CursorUserMeta(
            email: pickString(root, "email"),
            workosID: pickString(root, "workosId", "workos_id")
        )
    }
}

struct CursorTokenRefreshResult: Equatable {
    var accessToken: String
    var refreshToken: String?
    var shouldLogout: Bool

    static func parse(from data: Data) throws -> CursorTokenRefreshResult {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else {
            throw CursorAPIClientError.decoding
        }

        if pickBool(root, "shouldLogout", "should_logout") == true {
            throw CursorAPIClientError.authorizationFailure
        }

        guard let accessToken = pickString(root, "accessToken", "access_token"), !accessToken.isEmpty else {
            throw CursorAPIClientError.decoding
        }

        return CursorTokenRefreshResult(
            accessToken: accessToken,
            refreshToken: pickString(root, "refreshToken", "refresh_token"),
            shouldLogout: false
        )
    }
}

private func nestedObject(_ root: [String: Any], _ first: String, _ second: String) -> [String: Any]? {
    guard let child = objectValue(root[first]) else { return nil }
    return objectValue(child[second])
}

private func objectValue(_ value: Any?) -> [String: Any]? {
    value as? [String: Any]
}

private func pickString(_ object: [String: Any]?, _ keys: String...) -> String? {
    guard let object else { return nil }
    for key in keys {
        if let value = object[key] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
    }
    return nil
}

private func pickNumber(_ object: [String: Any]?, _ keys: String...) -> Double? {
    guard let object else { return nil }
    for key in keys {
        if let value = object[key] as? Double {
            return value
        }
        if let value = object[key] as? Int {
            return Double(value)
        }
        if let value = object[key] as? NSNumber {
            return value.doubleValue
        }
        if let value = object[key] as? String, let parsed = Double(value) {
            return parsed
        }
    }
    return nil
}

private func pickBool(_ object: [String: Any], _ keys: String...) -> Bool? {
    for key in keys {
        if let value = object[key] as? Bool {
            return value
        }
        if let value = object[key] as? String {
            switch value.lowercased() {
            case "true":
                return true
            case "false":
                return false
            default:
                break
            }
        }
    }
    return nil
}

private func pickDate(_ object: [String: Any], _ keys: String...) -> Date? {
    for key in keys {
        if let value = object[key] as? String {
            if let date = ISO8601DateFormatter.cursor.date(from: value) {
                return date
            }
            if let date = ISO8601DateFormatter.cursorFractional.date(from: value) {
                return date
            }
        }
        if let value = object[key] as? TimeInterval {
            return Date(timeIntervalSince1970: value)
        }
        if let value = object[key] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(value))
        }
    }
    return nil
}

private extension ISO8601DateFormatter {
    static let cursor: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let cursorFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
