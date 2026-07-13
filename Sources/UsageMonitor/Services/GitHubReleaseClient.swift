import Foundation

protocol GitHubReleaseRequestLoading {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: GitHubReleaseRequestLoading {}

final class GitHubReleaseClient: GitHubReleaseProviding {
    private let requestLoader: GitHubReleaseRequestLoading
    private let decoder = JSONDecoder()

    init(requestLoader: GitHubReleaseRequestLoading = URLSession.shared) {
        self.requestLoader = requestLoader
    }

    func fetchReleases() async throws -> [GitHubRelease] {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/yanbohon/macos-network-badge/releases")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("UsageMonitor", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await requestLoader.data(for: request)
        } catch let error as GitHubReleaseClientError {
            throw error
        } catch {
            throw GitHubReleaseClientError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubReleaseClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = decodeMessage(from: data)
            throw GitHubReleaseClientError.httpStatus(httpResponse.statusCode, message)
        }

        do {
            return try decoder.decode([GitHubRelease].self, from: data)
        } catch {
            throw GitHubReleaseClientError.decoding
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
}
