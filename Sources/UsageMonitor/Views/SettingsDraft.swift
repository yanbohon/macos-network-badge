import Foundation

@MainActor
protocol SettingsValuesPersisting {
    func updateBaseURL(_ value: String)
    func updateAPIKey(_ value: String)
}

struct SettingsDraft: Equatable {
    var baseURL: String
    var apiKey: String

    init(baseURL: String = "", apiKey: String = "") {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    @MainActor
    func commit(to persister: SettingsValuesPersisting) {
        persister.updateBaseURL(normalizedBaseURL)
        persister.updateAPIKey(normalizedAPIKey)
    }

    var normalizedBaseURL: String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    var normalizedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
