import Foundation

protocol BarkNotificationRequestLoading {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: BarkNotificationRequestLoading {}

protocol BarkNotificationSending {
    func send(
        _ message: BarkNotificationMessage,
        configuration: BarkNotificationConfiguration
    ) async throws
}

enum BarkNotificationClientError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int, String?)
    case api(Int, String?)
    case encoding
    case decoding
    case network(String)

    var userMessage: String {
        switch self {
        case .invalidResponse, .decoding:
            return "Bark 响应格式异常"
        case let .httpStatus(status, message):
            return message?.nonEmpty ?? "Bark HTTP \(status)"
        case let .api(code, message):
            return message?.nonEmpty ?? "Bark 错误 \(code)"
        case .encoding:
            return "Bark 请求参数无效"
        case .network:
            return "Bark 请求失败"
        }
    }
}

final class BarkNotificationClient: BarkNotificationSending {
    private struct Payload: Encodable {
        let deviceKey: String
        let title: String
        let body: String
        let level: String
        let volume: Int?
        let group: String?
        let icon: String?

        enum CodingKeys: String, CodingKey {
            case deviceKey = "device_key"
            case title
            case body
            case level
            case volume
            case group
            case icon
        }
    }

    private struct APIResponse: Decodable {
        let code: Int
        let message: String?
    }

    private struct ErrorResponse: Decodable {
        let message: String?
    }

    private let requestLoader: BarkNotificationRequestLoading
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(requestLoader: BarkNotificationRequestLoading = URLSession.shared) {
        self.requestLoader = requestLoader
    }

    func send(
        _ message: BarkNotificationMessage,
        configuration: BarkNotificationConfiguration
    ) async throws {
        let endpoint = configuration.serverURL.appendingPathComponent("push", isDirectory: false)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try encoder.encode(
                Payload(
                    deviceKey: configuration.deviceKey,
                    title: message.title,
                    body: message.body,
                    level: configuration.level.rawValue,
                    volume: configuration.volume,
                    group: configuration.group,
                    icon: configuration.iconURL
                )
            )
        } catch {
            throw BarkNotificationClientError.encoding
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await requestLoader.data(for: request)
        } catch let error as BarkNotificationClientError {
            throw error
        } catch {
            throw BarkNotificationClientError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BarkNotificationClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BarkNotificationClientError.httpStatus(
                httpResponse.statusCode,
                decodeMessage(from: data)
            )
        }

        let apiResponse: APIResponse
        do {
            apiResponse = try decoder.decode(APIResponse.self, from: data)
        } catch {
            throw BarkNotificationClientError.decoding
        }
        guard apiResponse.code == 200 else {
            throw BarkNotificationClientError.api(apiResponse.code, apiResponse.message)
        }
    }

    private func decodeMessage(from data: Data) -> String? {
        (try? decoder.decode(ErrorResponse.self, from: data))?.message
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
