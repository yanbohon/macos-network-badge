import XCTest
@testable import UsageMonitor

@MainActor
final class SettingsDraftTests: XCTestCase {
    func testCommitTrimsValuesBeforePersisting() {
        let persister = RecordingSettingsPersister()
        let draft = SettingsDraft(
            baseURL: "  https://sub.example.com/// ",
            apiKey: "  key_123  "
        )

        draft.commit(to: persister)

        XCTAssertEqual(persister.baseURLs, ["https://sub.example.com"])
        XCTAssertEqual(persister.apiKeys, ["key_123"])
    }

    func testCommitClearsEmptyAPIKey() {
        let persister = RecordingSettingsPersister()
        let draft = SettingsDraft(
            baseURL: "https://sub.example.com",
            apiKey: "   "
        )

        draft.commit(to: persister)

        XCTAssertEqual(persister.baseURLs, ["https://sub.example.com"])
        XCTAssertEqual(persister.apiKeys, [""])
    }
}

private final class RecordingSettingsPersister: SettingsValuesPersisting {
    var baseURLs: [String] = []
    var apiKeys: [String] = []
    var keyConfigurations: [UsageKeyConfiguration] = []

    func updateBaseURL(_ value: String) {
        baseURLs.append(value)
    }

    func updateAPIKey(_ value: String) {
        apiKeys.append(value)
    }

    func updateKeyConfiguration(
        id: String,
        name: String,
        symbolName: String,
        apiKey: String,
        baseURLMode: UsageKeyBaseURLMode,
        baseURLOverride: String
    ) {
        keyConfigurations.append(
            UsageKeyConfiguration(
                id: id,
                name: name,
                symbolName: symbolName,
                apiKey: apiKey,
                baseURLMode: baseURLMode,
                baseURLOverride: baseURLOverride
            )
        )
    }
}
