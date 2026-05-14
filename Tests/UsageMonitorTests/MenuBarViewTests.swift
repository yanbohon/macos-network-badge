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
}
