import XCTest
@testable import UsageMonitor

final class MultiKeySettingsDraftTests: XCTestCase {
    func testSettingsDraftNormalizesPerKeyFields() {
        let draft = SettingsDraft(
            defaultBaseURL: "  https://global.example.com/// ",
            keys: [
                .init(
                    id: "a",
                    name: "  Work  ",
                    symbolName: "  bolt.fill  ",
                    apiKey: "  key-a  ",
                    baseURLMode: .independent,
                    baseURLOverride: "  https://a.example.com/// "
                ),
                .init(
                    id: "b",
                    name: "   ",
                    symbolName: "   ",
                    apiKey: "   ",
                    baseURLMode: .inherited,
                    baseURLOverride: "  https://unused.example.com/// "
                ),
            ]
        )

        let normalized = draft.normalized()

        XCTAssertEqual(normalized.defaultBaseURL, "https://global.example.com")
        XCTAssertEqual(normalized.keys[0].name, "Work")
        XCTAssertEqual(normalized.keys[0].symbolName, "bolt.fill")
        XCTAssertEqual(normalized.keys[0].apiKey, "key-a")
        XCTAssertEqual(normalized.keys[0].baseURLOverride, "https://a.example.com")
        XCTAssertEqual(normalized.keys[1].name, "Key 2")
        XCTAssertEqual(normalized.keys[1].symbolName, "key.fill")
        XCTAssertEqual(normalized.keys[1].apiKey, "")
        XCTAssertEqual(normalized.keys[1].baseURLOverride, "")
    }
}
