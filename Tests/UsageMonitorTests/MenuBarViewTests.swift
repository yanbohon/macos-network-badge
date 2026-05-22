import Foundation
import XCTest

final class MenuBarViewTests: XCTestCase {
    func testPopoverDoesNotExposeRawServiceStatusJSON() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/UsageMonitor/Views/MenuBarView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("原始响应 JSON"))
        XCTAssertFalse(source.contains("serviceStatusMonitor.rawJSONText"))
    }

    func testPopoverContainsKeyPagerAndCurrentKeyRefreshActions() throws {
        let source = try menuBarViewSource()

        XCTAssertTrue(source.contains("keyPager"))
        XCTAssertTrue(source.contains("UsageKeyPager.selectedEntry"))
        XCTAssertTrue(source.contains("monitor.refreshCurrentKey"))
        XCTAssertTrue(source.contains("monitor.refreshAll"))
        XCTAssertTrue(source.contains("Base URL"))
    }

    private func menuBarViewSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/UsageMonitor/Views/MenuBarView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
