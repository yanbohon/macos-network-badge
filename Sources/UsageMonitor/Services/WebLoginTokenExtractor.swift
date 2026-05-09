import Foundation

struct WebLoginToken: Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval?
    let user: Sub2APIUser?
}

enum WebLoginTokenExtractor {
    static let capturedAuthStorageKey = "__usage_monitor_auth_response"

    private static let accessTokenKeys = [
        "access_token",
        "accessToken",
        "token",
        "auth_token",
        "jwt",
        "sub2api_access_token",
    ]

    private static let refreshTokenKeys = [
        "refresh_token",
        "refreshToken",
        "sub2api_refresh_token",
    ]

    static func extract(from storage: [String: String], cookies: [String: String]) -> WebLoginToken? {
        if let captured = firstValue(named: [capturedAuthStorageKey], in: storage),
           let token = decodeCapturedAuth(captured) {
            return token
        }

        guard let accessToken = firstValue(named: accessTokenKeys, in: storage, cookies), !accessToken.isEmpty else {
            return nil
        }

        return WebLoginToken(
            accessToken: accessToken,
            refreshToken: firstValue(named: refreshTokenKeys, in: storage, cookies),
            expiresIn: nil,
            user: nil
        )
    }

    private static func decodeCapturedAuth(_ raw: String) -> WebLoginToken? {
        guard let data = raw.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder.sub2api
        if let envelope = try? decoder.decode(Sub2APILoginEnvelope.self, from: data),
           envelope.code == 0,
           let loginData = envelope.data,
           !loginData.accessToken.isEmpty {
            return WebLoginToken(
                accessToken: loginData.accessToken,
                refreshToken: loginData.refreshToken,
                expiresIn: loginData.expiresIn,
                user: loginData.user
            )
        }

        if let loginData = try? decoder.decode(Sub2APILoginData.self, from: data),
           !loginData.accessToken.isEmpty {
            return WebLoginToken(
                accessToken: loginData.accessToken,
                refreshToken: loginData.refreshToken,
                expiresIn: loginData.expiresIn,
                user: loginData.user
            )
        }

        return nil
    }

    private static func firstValue(named names: [String], in dictionaries: [String: String]...) -> String? {
        for dictionary in dictionaries {
            for name in names {
                if let value = dictionary.first(where: { normalized($0.key) == normalized(name) })?.value
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private static func normalized(_ key: String) -> String {
        key
            .replacingOccurrences(of: "local:", with: "")
            .replacingOccurrences(of: "session:", with: "")
            .lowercased()
    }
}
