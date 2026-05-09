import Foundation

protocol Sub2APIRequestLoading {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: Sub2APIRequestLoading {}

enum Sub2APIClientError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int, String?)
    case authorizationFailure
    case decoding
    case network(String)

    var userMessage: String {
        switch self {
        case .invalidResponse, .decoding:
            return "响应格式不符合预期"
        case let .httpStatus(status, message):
            if let message, !message.isEmpty {
                return message
            }
            return "HTTP \(status)"
        case .authorizationFailure:
            return "API Key 无效，请检查后重试"
        case .network:
            return "网络请求失败"
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

final class Sub2APIClient {
    private let requestLoader: Sub2APIRequestLoading
    private let decoder = JSONDecoder.sub2api

    init(requestLoader: Sub2APIRequestLoading = URLSession.shared) {
        self.requestLoader = requestLoader
    }

    func usage(baseURL: URL, apiKey: String) async throws -> UsageResponse {
        var request = URLRequest(url: apiURL(baseURL: baseURL, path: "/v1/usage"))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let response: UsageResponse = try await load(request)
        guard response.isValid else {
            throw Sub2APIClientError.authorizationFailure
        }
        return response
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

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw Sub2APIClientError.authorizationFailure
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
