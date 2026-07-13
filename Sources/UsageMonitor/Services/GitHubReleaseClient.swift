import Foundation

protocol GitHubReleaseRequestLoading {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: GitHubReleaseRequestLoading {}

final class GitHubReleaseClient: GitHubReleaseProviding {
    private static let releasesAPIURL = URL(
        string: "https://api.github.com/repos/yanbohon/macos-network-badge/releases"
    )!
    private static let latestReleaseURL = URL(
        string: "https://github.com/yanbohon/macos-network-badge/releases/latest"
    )!

    private let requestLoader: GitHubReleaseRequestLoading
    private let decoder = JSONDecoder()

    init(requestLoader: GitHubReleaseRequestLoading = URLSession.shared) {
        self.requestLoader = requestLoader
    }

    func fetchReleases() async throws -> [GitHubRelease] {
        do {
            return try await fetchReleasesFromAPI()
        } catch let error as GitHubReleaseClientError {
            guard error.isRateLimitResponse else {
                throw error
            }
            return [try await fetchLatestStableRelease()]
        }
    }

    private func fetchReleasesFromAPI() async throws -> [GitHubRelease] {
        var request = URLRequest(url: Self.releasesAPIURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("UsageMonitor", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await load(request)

        do {
            return try decoder.decode([GitHubRelease].self, from: data)
        } catch {
            throw GitHubReleaseClientError.decoding
        }
    }

    private func fetchLatestStableRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("UsageMonitor", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await load(request)
        guard let releaseURL = response.url, let tagName = releaseTag(from: releaseURL) else {
            throw GitHubReleaseClientError.invalidResponse
        }

        return GitHubRelease(
            tagName: tagName,
            draft: false,
            prerelease: false,
            publishedAt: nil,
            htmlURL: releaseURL,
            assets: []
        )
    }

    private func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
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
        return (data, httpResponse)
    }

    private func releaseTag(from url: URL) -> String? {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "github.com" else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard
            pathComponents.count == 5,
            Array(pathComponents.prefix(4)) == ["yanbohon", "macos-network-badge", "releases", "tag"],
            let tagName = pathComponents.last,
            !tagName.isEmpty
        else {
            return nil
        }
        return tagName
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

private extension GitHubReleaseClientError {
    var isRateLimitResponse: Bool {
        guard case let .httpStatus(statusCode, message) = self else { return false }
        return statusCode == 429
            || (statusCode == 403 && message?.localizedCaseInsensitiveContains("rate limit") == true)
    }
}
