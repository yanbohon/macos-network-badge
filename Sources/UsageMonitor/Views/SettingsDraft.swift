import Foundation

@MainActor
protocol SettingsValuesPersisting {
    func updateBaseURL(_ value: String)
    func updateAPIKey(_ value: String)
    func updateKeyConfiguration(
        id: String,
        name: String,
        symbolName: String,
        apiKey: String,
        baseURLMode: UsageKeyBaseURLMode,
        baseURLOverride: String
    )
}

struct SettingsDraft: Equatable {
    struct KeyDraft: Equatable, Identifiable {
        var id: String
        var name: String
        var symbolName: String
        var apiKey: String
        var baseURLMode: UsageKeyBaseURLMode
        var baseURLOverride: String

        init(
            id: String,
            name: String,
            symbolName: String,
            apiKey: String,
            baseURLMode: UsageKeyBaseURLMode,
            baseURLOverride: String
        ) {
            self.id = id
            self.name = name
            self.symbolName = symbolName
            self.apiKey = apiKey
            self.baseURLMode = baseURLMode
            self.baseURLOverride = baseURLOverride
        }

        init(configuration: UsageKeyConfiguration) {
            id = configuration.id
            name = configuration.name
            symbolName = configuration.symbolName
            apiKey = configuration.apiKey
            baseURLMode = configuration.baseURLMode
            baseURLOverride = configuration.baseURLOverride
        }
    }

    var defaultBaseURL: String
    var keys: [KeyDraft]

    init(baseURL: String = "", apiKey: String = "") {
        defaultBaseURL = baseURL
        keys = [
            KeyDraft(
                id: "legacy-first-key",
                name: "Key 1",
                symbolName: UsageKeyConfiguration.defaultSymbolName,
                apiKey: apiKey,
                baseURLMode: .inherited,
                baseURLOverride: ""
            ),
        ]
    }

    init(defaultBaseURL: String = "", keys: [KeyDraft]) {
        self.defaultBaseURL = defaultBaseURL
        self.keys = keys.isEmpty
            ? [
                KeyDraft(
                    id: UUID().uuidString,
                    name: "Key 1",
                    symbolName: UsageKeyConfiguration.defaultSymbolName,
                    apiKey: "",
                    baseURLMode: .inherited,
                    baseURLOverride: ""
                ),
            ]
            : keys
    }

    var baseURL: String {
        get { defaultBaseURL }
        set { defaultBaseURL = newValue }
    }

    var apiKey: String {
        get { keys.first?.apiKey ?? "" }
        set {
            if keys.isEmpty {
                keys = [
                    KeyDraft(
                        id: UUID().uuidString,
                        name: "Key 1",
                        symbolName: UsageKeyConfiguration.defaultSymbolName,
                        apiKey: newValue,
                        baseURLMode: .inherited,
                        baseURLOverride: ""
                    ),
                ]
            } else {
                keys[0].apiKey = newValue
            }
        }
    }

    @MainActor
    func commit(to persister: SettingsValuesPersisting) {
        persister.updateBaseURL(normalizedBaseURL)
        let normalized = normalized()
        for key in normalized.keys {
            persister.updateKeyConfiguration(
                id: key.id,
                name: key.name,
                symbolName: key.symbolName,
                apiKey: key.apiKey,
                baseURLMode: key.baseURLMode,
                baseURLOverride: key.baseURLOverride
            )
        }
        if let firstAPIKey = normalized.keys.first?.apiKey {
            persister.updateAPIKey(firstAPIKey)
        }
    }

    var normalizedBaseURL: String {
        UsageKeyConfiguration.normalizedBaseURL(defaultBaseURL)
    }

    var normalizedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalized() -> SettingsDraft {
        let normalizedKeys = keys.enumerated().map { index, key in
            let configuration = UsageKeyConfiguration(
                id: key.id,
                name: key.name,
                symbolName: key.symbolName,
                apiKey: key.apiKey,
                baseURLMode: key.baseURLMode,
                baseURLOverride: key.baseURLOverride
            ).normalized(index: index)
            return KeyDraft(configuration: configuration)
        }
        return SettingsDraft(
            defaultBaseURL: normalizedBaseURL,
            keys: normalizedKeys
        )
    }
}
