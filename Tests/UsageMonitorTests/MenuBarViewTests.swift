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

    func testPopoverOmitsVerboseUsageDetailsAndDuplicateKeyRefreshStatus() throws {
        let source = try menuBarViewSource()

        XCTAssertFalse(source.contains("usageSection(snapshot.usage)"))
        XCTAssertFalse(source.contains("modelStatsSection(snapshot.modelStats)"))
        XCTAssertFalse(source.contains("private func usageSection"))
        XCTAssertFalse(source.contains("private func modelStatsSection"))

        let keySummaryStart = try XCTUnwrap(source.range(of: "private func keySummary"))
        let usageSnapshotStart = try XCTUnwrap(
            source.range(
                of: "private func usageSnapshot",
                range: keySummaryStart.upperBound..<source.endIndex
            )
        )
        let keySummarySource = source[keySummaryStart.lowerBound..<usageSnapshotStart.lowerBound]

        XCTAssertFalse(keySummarySource.contains("statusLineText(for: entry)"))
        XCTAssertFalse(keySummarySource.contains("entry.lastSuccessfulRefresh"))
    }

    func testSettingsKeyRowsExposeWholeRowClickTarget() throws {
        let source = try settingsViewSource()

        XCTAssertTrue(source.contains("private func keyRowButton"))
        XCTAssertTrue(source.contains(".contentShape(Rectangle())"))
    }

    func testSettingsViewHasOnlyOnePrimaryValidationAction() throws {
        let source = try settingsViewSource()
        let occurrences = source.components(separatedBy: "Text(primaryButtonTitle)").count - 1

        XCTAssertEqual(occurrences, 1)
    }

    func testSettingsValidationButtonDoesNotDependOnBackgroundRefreshState() throws {
        let source = try settingsViewSource()

        XCTAssertFalse(source.contains("connectionStatus.isValidating || monitor.isRefreshing"))
    }

    func testSettingsExposesSingleKeySymbolVisibilityToggle() throws {
        let source = try settingsViewSource()

        XCTAssertTrue(source.contains("菜单栏隐藏 SF Symbol"))
        XCTAssertTrue(source.contains("$monitor.hideMenuBarSymbols"))
    }

    func testSettingsExposesPerKeyMenuBarAndSymbolColorControls() throws {
        let source = try settingsViewSource()

        XCTAssertTrue(source.contains("在菜单栏显示"))
        XCTAssertTrue(source.contains("SF Symbol 颜色"))
        XCTAssertTrue(source.contains("ColorPicker("))
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
