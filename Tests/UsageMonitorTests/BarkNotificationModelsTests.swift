import XCTest
@testable import UsageMonitor

final class BarkNotificationModelsTests: XCTestCase {
    func testNotificationLevelsUseSettingsDisplayNames() {
        XCTAssertEqual(
            BarkNotificationLevel.allCases.map(\.displayName),
            ["默认", "即时", "静默", "重要"]
        )
    }
}
