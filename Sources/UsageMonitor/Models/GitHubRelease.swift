import Foundation

protocol GitHubReleaseProviding {
    func fetchReleases() async throws -> [GitHubRelease]
}

struct GitHubReleaseAsset: Equatable, Decodable {
    let name: String
    let browserDownloadURL: URL

    init(name: String, browserDownloadURL: URL) {
        self.name = name
        self.browserDownloadURL = browserDownloadURL
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

struct GitHubRelease: Equatable, Decodable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let publishedAt: Date?
    let htmlURL: URL
    let assets: [GitHubReleaseAsset]

    init(
        tagName: String,
        draft: Bool,
        prerelease: Bool,
        publishedAt: Date?,
        htmlURL: URL,
        assets: [GitHubReleaseAsset]
    ) {
        self.tagName = tagName
        self.draft = draft
        self.prerelease = prerelease
        self.publishedAt = publishedAt
        self.htmlURL = htmlURL
        self.assets = assets
    }

    var version: AppVersion? {
        AppVersion.parse(tagName)
    }

    var dmgAsset: GitHubReleaseAsset? {
        assets.first { $0.name == "UsageMonitor.dmg" }
    }

    var checksumAsset: GitHubReleaseAsset? {
        assets.first { $0.name == "UsageMonitor.dmg.sha256" }
    }

    var downloadURL: URL {
        dmgAsset?.browserDownloadURL ?? htmlURL
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
        case publishedAt = "published_at"
        case htmlURL = "html_url"
        case assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        draft = try container.decode(Bool.self, forKey: .draft)
        prerelease = try container.decode(Bool.self, forKey: .prerelease)
        let publishedAtString = try container.decodeIfPresent(String.self, forKey: .publishedAt)
        publishedAt = GitHubReleaseDateParser.date(from: publishedAtString)
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        assets = try container.decodeIfPresent([GitHubReleaseAsset].self, forKey: .assets) ?? []
    }
}

enum GitHubReleaseClientError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int, String?)
    case decoding
    case network(String)
}

private enum GitHubReleaseDateParser {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string)
    }
}
