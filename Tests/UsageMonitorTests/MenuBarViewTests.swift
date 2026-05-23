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

    func testSettingsKeyRowsExposeWholeRowClickTarget() throws {
        let source = try settingsViewSource()

        XCTAssertTrue(source.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        XCTAssertTrue(source.contains(".contentShape(Rectangle())"))
    }

    func testSettingsExposesSingleKeySymbolVisibilityToggle() throws {
        let source = try settingsViewSource()

        XCTAssertTrue(source.contains("菜单栏隐藏 SF Symbol"))
        XCTAssertTrue(source.contains("$monitor.hideMenuBarSymbols"))
    }

    private func menuBarViewSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/UsageMonitor/Views/MenuBarView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func settingsViewSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/UsageMonitor/Views/SettingsView.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
