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

    func testPopoverListsCursorAccountsAndKeysWithoutPager() throws {
        let source = try menuBarViewSource()

        XCTAssertTrue(source.contains("cursorSection"))
        XCTAssertTrue(source.contains("keysSection"))
        XCTAssertTrue(source.contains("account.membershipDisplayName"))
        XCTAssertTrue(source.contains("membershipColor(for: account)"))
        XCTAssertTrue(source.contains("cursorStatusLine(for: account)"))
        XCTAssertTrue(source.contains("account.billingCycleEndText"))
        XCTAssertTrue(source.contains("Text(\"Auto \\(account.autoUsageText)\")"))
        XCTAssertTrue(source.contains("Text(\"API \\(account.apiUsageText)\")"))
        XCTAssertTrue(source.contains("todayBalanceText(for: entry)"))
        XCTAssertTrue(source.contains("refreshText(for: entry)"))
        XCTAssertFalse(source.contains("Text(\"菜单栏\")"))
        XCTAssertFalse(source.contains("keyPager"))
        XCTAssertFalse(source.contains("UsageKeyPager.selectedEntry"))
        XCTAssertFalse(source.contains("monitor.refreshCurrentKey"))
        XCTAssertTrue(source.contains("monitor.refreshAll"))
        XCTAssertTrue(source.contains("cursorMonitor.refreshAll"))
    }

    func testPopoverDefaultsToGPT56SolAndDisclosesRemainingModels() throws {
        let source = try menuBarViewSource()

        XCTAssertTrue(source.contains("@State private var showsAllServiceStatuses = false"))
        XCTAssertTrue(source.contains("serviceStatusMonitor.timelineRows.first"))
        XCTAssertTrue(source.contains("serviceStatusMonitor.timelineRows.dropFirst()"))
        XCTAssertTrue(source.contains("if showsAllServiceStatuses"))
        XCTAssertTrue(source.contains("chevron.up"))
        XCTAssertTrue(source.contains("chevron.down"))
        XCTAssertTrue(source.contains("展开其他模型状态"))
    }

    func testPopoverOmitsVerboseUsageDetailsAndDuplicateKeyRefreshStatus() throws {
        let source = try menuBarViewSource()

        XCTAssertFalse(source.contains("usageSection(snapshot.usage)"))
        XCTAssertFalse(source.contains("modelStatsSection(snapshot.modelStats)"))
        XCTAssertFalse(source.contains("private func usageSection"))
        XCTAssertFalse(source.contains("private func modelStatsSection"))
        XCTAssertFalse(source.contains("private func keySummary"))
        XCTAssertFalse(source.contains("private func usageSnapshot"))
        XCTAssertFalse(source.contains("private func planSection"))
        XCTAssertFalse(source.contains("private func subscriptionSection"))
        XCTAssertFalse(source.contains("private func currentKeyDetail"))
        XCTAssertFalse(source.contains("snapshot.planName"))
        XCTAssertFalse(source.contains("Base URL"))
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

        XCTAssertTrue(source.contains("显示 SF Symbol"))
        XCTAssertTrue(source.contains("showMenuBarSymbolsBinding"))
    }

    func testSettingsExposesCursorAccountTab() throws {
        let source = try settingsViewSource()
        let cursorPage = try cursorSettingsPageSource()

        XCTAssertTrue(source.contains("SettingsTab.cursor"))
        XCTAssertTrue(source.contains("CursorSettingsPage(monitor: cursorMonitor)"))
        XCTAssertTrue(source.contains("Label(\"Cursor\""))
        XCTAssertTrue(cursorPage.contains("Access Token"))
        XCTAssertTrue(cursorPage.contains("Refresh Token"))
        XCTAssertTrue(cursorPage.contains("Card Session"))
        XCTAssertTrue(cursorPage.contains("账号类型"))
        XCTAssertTrue(cursorPage.contains("kind == .team"))
        XCTAssertTrue(cursorPage.contains("在菜单栏显示"))
        XCTAssertTrue(cursorPage.contains("SF Symbol"))
        XCTAssertTrue(cursorPage.contains("验证并刷新"))
        XCTAssertTrue(cursorPage.contains("复制 Access Token"))
        XCTAssertTrue(cursorPage.contains("copyAccessToken()"))
        XCTAssertTrue(cursorPage.contains("CursorSessionToken.exportableAccessToken"))
        XCTAssertTrue(cursorPage.contains("NSPasteboard.general.setString"))
    }

    func testSettingsExposesMenuBarServiceStatusPicker() throws {
        let source = try settingsViewSource()

        XCTAssertTrue(source.contains("菜单栏服务状态"))
        XCTAssertTrue(source.contains("$serviceStatusMonitor.menuBarModel"))
        XCTAssertTrue(source.contains("ServiceStatusMonitor.supportedModels"))
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

    private func cursorSettingsPageSource() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/UsageMonitor/Views/CursorSettingsPage.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
