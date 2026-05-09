import Foundation

protocol Sub2APIRequestLoading {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: Sub2APIRequestLoading {}

enum Sub2APIClientError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int, String?)
    case apiMessage(String)
    case missingAccessToken
    case decoding
    case network(String)

    var userMessage: String {
        switch self {
        case .invalidResponse:
            return "响应格式不符合预期"
        case let .httpStatus(status, message):
            if let message, !message.isEmpty {
                return message
            }
            if status == 401 || status == 403 {
                return "登录已失效，请重新验证"
            }
            return "HTTP \(status)"
        case let .apiMessage(message):
            return message
        case .missingAccessToken:
            return "响应格式不符合预期"
        case .decoding:
            return "响应格式不符合预期"
        case .network:
            return "网络请求失败"
        }
    }

    var isUnauthorized: Bool {
        switch self {
        case let .httpStatus(status, _):
            status == 401 || status == 403
        default:
            false
        }
    }
}

final class Sub2APIClient {
    private let requestLoader: Sub2APIRequestLoading
    private let decoder = JSONDecoder.sub2api

    init(requestLoader: Sub2APIRequestLoading = URLSession.shared) {
        self.requestLoader = requestLoader
    }

    func login(baseURL: URL, email: String, password: String) async throws -> Sub2APILoginData {
        var request = URLRequest(url: apiURL(baseURL: baseURL, path: "/api/v1/auth/login"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
        ])

        let envelope: Sub2APILoginEnvelope = try await load(request)
        guard envelope.code == 0 else {
            throw Sub2APIClientError.apiMessage(envelope.message ?? "登录失败")
        }
        guard let data = envelope.data, !data.accessToken.isEmpty else {
            throw Sub2APIClientError.missingAccessToken
        }
        return data
    }

    func subscriptions(baseURL: URL, accessToken: String) async throws -> [Sub2APISubscription] {
        var request = URLRequest(url: apiURL(baseURL: baseURL, path: "/api/v1/subscriptions"))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let envelope: Sub2APISubscriptionsEnvelope = try await load(request)
        guard envelope.code == 0 else {
            throw Sub2APIClientError.apiMessage(envelope.message ?? "刷新失败")
        }
        return envelope.data
    }

    private func load<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await requestLoader.data(for: request)
        } catch let error as Sub2APIClientError {
            throw error
        } catch {
            throw Sub2APIClientError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Sub2APIClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = decodeMessage(from: data)
            throw Sub2APIClientError.httpStatus(httpResponse.statusCode, message)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw Sub2APIClientError.decoding
        }
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

    private func apiURL(baseURL: URL, path: String) -> URL {
        let normalizedBase = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: normalizedBase + path)!
    }
}
