import Foundation

struct UpdateReleaseInfo: Equatable, Identifiable {
    let version: AppVersion
    let publishedAt: Date?
    let releaseURL: URL

    var id: URL {
        releaseURL
    }

    var versionText: String {
        version.displayText
    }
}

enum UpdateCheckFailure: Equatable {
    case invalidResponse
    case network

    var userMessage: String {
        switch self {
        case .invalidResponse:
            return "更新信息格式异常"
        case .network:
            return "检查更新失败，请稍后重试"
        }
    }
}

enum UpdateCheckResult: Equatable {
    case upToDate
    case updateAvailable(UpdateReleaseInfo)
    case failure(UpdateCheckFailure)

    var statusText: String {
        switch self {
        case .upToDate:
            return "已是最新版"
        case let .updateAvailable(info):
            return "发现新版本 \(info.versionText)"
        case let .failure(failure):
            return failure.userMessage
        }
    }

    var releaseURL: URL? {
        switch self {
        case .upToDate, .failure:
            return nil
        case let .updateAvailable(info):
            return info.releaseURL
        }
    }
}

struct UpdateChecker {
    private let client: GitHubReleaseProviding
    private let currentVersionProvider: () -> AppVersion?

    init(
        client: GitHubReleaseProviding = GitHubReleaseClient(),
        currentVersion: AppVersion? = nil,
        bundle: Bundle = .main
    ) {
        self.client = client
        if let currentVersion {
            currentVersionProvider = { currentVersion }
        } else {
            currentVersionProvider = {
                let rawVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                return rawVersion.flatMap { AppVersion.parse($0) }
            }
        }
    }

    func checkForUpdate() async -> UpdateCheckResult {
        guard let currentVersion = currentVersionProvider() else {
            return .failure(.invalidResponse)
        }

        do {
            let releases = try await client.fetchReleases()
            let candidates = releases.compactMap { release -> UpdateReleaseInfo? in
                guard !release.draft else { return nil }
                guard !release.prerelease else { return nil }
                guard let releaseVersion = release.version else { return nil }
                guard !releaseVersion.isPrerelease else { return nil }
                guard releaseVersion > currentVersion else { return nil }
                return UpdateReleaseInfo(
                    version: releaseVersion,
                    publishedAt: release.publishedAt,
                    releaseURL: release.htmlURL
                )
            }

            guard let bestCandidate = candidates.sorted(by: { $0.version < $1.version }).last else {
                return .upToDate
            }
            return .updateAvailable(bestCandidate)
        } catch let error as GitHubReleaseClientError {
            switch error {
            case .invalidResponse, .decoding:
                return .failure(.invalidResponse)
            case .httpStatus, .network:
                return .failure(.network)
            }
        } catch {
            return .failure(.network)
        }
    }
}
