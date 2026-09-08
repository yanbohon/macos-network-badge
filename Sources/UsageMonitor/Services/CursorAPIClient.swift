import Foundation

protocol CursorAPIRequestLoading {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: CursorAPIRequestLoading {}

enum CursorAPIClientError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int, String?)
    case authorizationFailure
    case decoding
    case network(String)
    case missingSessionCookie

    var userMessage: String {
        switch self {
        case .invalidResponse, .decoding:
            return "Cursor 响应格式不符合预期"
        case let .httpStatus(status, message):
            if let message, !message.isEmpty {
                return message
            }
            return "HTTP \(status)"
        case .authorizationFailure:
            return "Cursor 会话已过期或无效，请更新 Token"
        case .network:
            return "网络请求失败"
        case .missingSessionCookie:
            return "无法从 Access Token 解析 Cursor 会话"
        }
    }

    var isUnauthorized: Bool {
        switch self {
        case .authorizationFailure:
            return true
        case let .httpStatus(status, _):
            return status == 401 || status == 403
        default:
            return false
        }
    }
}

final class CursorAPIClient {
    static let usageSummaryURL = URL(string: "https://cursor.com/api/usage-summary")!
    static let sandUsageURL = URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status")!
    static let teamExtractionUsageURL = URL(string: "https://ss.hxfwq.com/api/user/extractions/usage")!
    static let oauthTokenURL = URL(string: "https://api2.cursor.sh/oauth/token")!
    static let userMetaURL = URL(string: "https://api2.cursor.sh/aiserver.v1.AuthService/GetUserMeta")!
    static let authClientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"
    static let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"

    private let requestLoader: CursorAPIRequestLoading

    init(requestLoader: CursorAPIRequestLoading = URLSession.shared) {
        self.requestLoader = requestLoader
    }

    func refreshAccessToken(refreshToken: String) async throws -> CursorTokenRefreshResult {
        var request = URLRequest(url: Self.oauthTokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": Self.authClientID,
            "refresh_token": refreshToken,
        ])

        let data = try await loadData(request)
        return try CursorTokenRefreshResult.parse(from: data)
    }

    func fetchUsageSummary(accessToken: String) async throws -> CursorUsageSummary {
        let data = try await loadData(dashboardRequest(
            url: Self.usageSummaryURL,
            accessToken: accessToken,
            method: "GET"
        ))
        return try CursorUsageSummary.parse(from: data)
    }

    func fetchTeamExtractionUsage(cardSession: String) async throws -> CursorTeamExtractionUsage {
        let session = cardSession.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !session.isEmpty else {
            throw CursorAPIClientError.missingSessionCookie
        }

        var request = URLRequest(url: Self.teamExtractionUsageURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("card_session=\(session)", forHTTPHeaderField: "Cookie")
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        let data = try await loadData(request)
        return try CursorTeamExtractionUsage.parse(from: data)
    }

    func fetchSandUsage(accessToken: String) async throws -> CursorSandUsageStatus {
        var request = try dashboardRequest(
            url: Self.sandUsageURL,
            accessToken: accessToken,
            method: "POST"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.httpBody = Data("{}".utf8)
        let data = try await loadData(request)
        return try CursorSandUsageStatus.parse(from: data)
    }

    private func dashboardRequest(url: URL, accessToken: String, method: String) throws -> URLRequest {
        guard let cookie = CursorSessionToken.sessionCookie(from: accessToken) else {
            throw CursorAPIClientError.missingSessionCookie
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    func fetchUserMeta(accessToken: String) async throws -> CursorUserMeta {
        var request = URLRequest(url: Self.userMetaURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(CursorSessionToken.normalizedAccessToken(accessToken))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [String: String]())

        let data = try await loadData(request)
        return try CursorUserMeta.parse(from: data)
    }

    private func loadData(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await requestLoader.data(for: request)
        } catch let error as CursorAPIClientError {
            throw error
        } catch {
            throw CursorAPIClientError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CursorAPIClientError.invalidResponse
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw CursorAPIClientError.authorizationFailure
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CursorAPIClientError.httpStatus(httpResponse.statusCode, decodeMessage(from: data))
        }

        return data
    }

    private func decodeMessage(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = object["message"] as? String,
            !message.isEmpty
        else {
            return nil
        }
        return message
    }
}
