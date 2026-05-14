import Foundation

struct ServiceStatusResponse: Codable, Equatable {
    let allOK: Bool
    let generatedAt: TimeInterval
    let services: [ServiceStatusService]

    enum CodingKeys: String, CodingKey {
        case allOK = "all_ok"
        case generatedAt = "generated_at"
        case services
    }

    init(allOK: Bool, generatedAt: TimeInterval, services: [ServiceStatusService]) {
        self.allOK = allOK
        self.generatedAt = generatedAt
        self.services = services
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allOK = try container.decode(Bool.self, forKey: .allOK)
        generatedAt = try container.decodeStatusTimeInterval(forKey: .generatedAt)
        services = try container.decodeIfPresent([ServiceStatusService].self, forKey: .services) ?? []
    }

    func service(model: String) -> ServiceStatusService? {
        services.first { $0.model == model }
    }
}

struct ServiceStatusService: Codable, Equatable {
    let model: String
    let uptimePct: Double?
    let last: ServiceStatusProbe?
    let history: [ServiceStatusProbe]

    enum CodingKeys: String, CodingKey {
        case model
        case uptimePct = "uptime_pct"
        case last
        case history
    }

    init(
        model: String,
        uptimePct: Double?,
        last: ServiceStatusProbe?,
        history: [ServiceStatusProbe]
    ) {
        self.model = model
        self.uptimePct = uptimePct
        self.last = last
        self.history = history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        uptimePct = try container.decodeStatusDoubleIfPresent(forKey: .uptimePct)
        last = try container.decodeIfPresent(ServiceStatusProbe.self, forKey: .last)
        history = try container.decodeIfPresent([ServiceStatusProbe].self, forKey: .history) ?? []
    }

    func latestDisplayCells(count: Int = 8) -> [ServiceStatusDisplayCell] {
        let recentHistory = history.suffix(count).map {
            ServiceStatusDisplayCell(kind: ServiceStatusCellKind.classify($0), probe: $0)
        }
        let missingCount = max(0, count - recentHistory.count)
        let missingCells = Array(repeating: ServiceStatusDisplayCell(kind: .gray, probe: nil), count: missingCount)
        return missingCells + recentHistory
    }
}

struct ServiceStatusProbe: Codable, Equatable {
    let ts: TimeInterval?
    let ok: Bool?
    let latencyMS: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ts
        case ok
        case latencyMS = "latency_ms"
        case error
    }

    init(ts: TimeInterval?, ok: Bool?, latencyMS: Int?, error: String?) {
        self.ts = ts
        self.ok = ok
        self.latencyMS = latencyMS
        self.error = error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ts = try container.decodeStatusTimeIntervalIfPresent(forKey: .ts)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
        latencyMS = try container.decodeStatusIntIfPresent(forKey: .latencyMS)
        error = try container.decodeIfPresent(String.self, forKey: .error)
    }
}

struct ServiceStatusDisplayCell: Equatable {
    let kind: ServiceStatusCellKind
    let probe: ServiceStatusProbe?

    var helpText: String {
        guard let probe else { return "状态未知" }
        switch kind {
        case .green:
            return "正常 \(probe.latencyMS.map { "\($0) ms" } ?? "")".trimmingCharacters(in: .whitespaces)
        case .yellow:
            return "高延迟 \(probe.latencyMS.map { "\($0) ms" } ?? "")".trimmingCharacters(in: .whitespaces)
        case .red:
            if let error = probe.error, !error.isEmpty {
                return "失败：\(error)"
            }
            return "失败"
        case .gray:
            return "状态未知"
        }
    }
}

enum ServiceStatusCellKind: Equatable {
    case green
    case yellow
    case red
    case gray

    static func classify(_ probe: ServiceStatusProbe?) -> ServiceStatusCellKind {
        guard let probe, let ok = probe.ok else {
            return .gray
        }
        guard ok else {
            return .red
        }
        guard let latencyMS = probe.latencyMS else {
            return .gray
        }
        return latencyMS >= 3_000 ? .yellow : .green
    }
}

extension JSONDecoder {
    static var serviceStatus: JSONDecoder {
        JSONDecoder()
    }
}

private extension KeyedDecodingContainer {
    func decodeStatusTimeInterval(forKey key: Key) throws -> TimeInterval {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return TimeInterval(value)
        }
        if let value = try? decode(String.self, forKey: key),
           let interval = TimeInterval(value) {
            return interval
        }
        return try decode(Double.self, forKey: key)
    }

    func decodeStatusTimeIntervalIfPresent(forKey key: Key) throws -> TimeInterval? {
        guard contains(key), !(try decodeNil(forKey: key)) else {
            return nil
        }
        return try decodeStatusTimeInterval(forKey: key)
    }

    func decodeStatusDoubleIfPresent(forKey key: Key) throws -> Double? {
        guard contains(key), !(try decodeNil(forKey: key)) else {
            return nil
        }
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
        return try decode(Double.self, forKey: key)
    }

    func decodeStatusIntIfPresent(forKey key: Key) throws -> Int? {
        guard contains(key), !(try decodeNil(forKey: key)) else {
            return nil
        }
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
        return try decode(Int.self, forKey: key)
    }
}
