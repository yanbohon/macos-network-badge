import AppKit
import XCTest
@testable import UsageMonitor

@MainActor
final class MultiKeyLayoutTests: XCTestCase {
    func testMenuBarGridColumnCountForKeyCounts() {
        XCTAssertEqual(MenuBarTitleView.keyGridColumnCount(forKeyCount: 1), 1)
        XCTAssertEqual(MenuBarTitleView.keyGridColumnCount(forKeyCount: 2), 1)
        XCTAssertEqual(MenuBarTitleView.keyGridColumnCount(forKeyCount: 3), 2)
        XCTAssertEqual(MenuBarTitleView.keyGridColumnCount(forKeyCount: 4), 2)
        XCTAssertEqual(MenuBarTitleView.keyGridColumnCount(forKeyCount: 5), 3)
    }

    func testMenuBarGridFillsTopToBottomThenLeftToRight() {
        let rows = (1...5).map {
            MenuBarKeyDisplayRow(id: "key-\($0)", name: "Key \($0)", symbolName: "key.fill", text: "$\($0)")
        }

        let columns = MenuBarTitleView.keyGridColumns(for: rows)

        XCTAssertEqual(columns.map { $0.map(\.id) }, [
            ["key-1", "key-2"],
            ["key-3", "key-4"],
            ["key-5"],
        ])
    }

    func testMenuBarFallbackSymbolBehavior() {
        XCTAssertEqual(MenuBarTitleView.resolvedSymbolName("bolt.fill"), "bolt.fill")
        XCTAssertEqual(MenuBarTitleView.resolvedSymbolName(""), "key.fill")
        XCTAssertEqual(MenuBarTitleView.resolvedSymbolName("not.a.real.symbol.name"), "key.fill")
    }

    func testAccessibilityTitleIncludesAllKeyDisplayTexts() {
        let title = StatusBarController.titleText(
            keyRows: [
                MenuBarKeyDisplayRow(id: "a", name: "Alpha", symbolName: "key.fill", text: "$1.23"),
                MenuBarKeyDisplayRow(id: "b", name: "Beta", symbolName: "bolt.fill", text: "未授权"),
            ],
            statusCells: [ServiceStatusDisplayCell(kind: .green, probe: nil)],
            statusCellsAreStale: true
        )

        XCTAssertEqual(title, "服务状态正常（缓存） Alpha $1.23，Beta 未授权")
    }

    func testStatusBarLengthExpandsForMultiKeyColumns() {
        let oneColumn = StatusBarController.statusItemLength(
            forKeyRows: [
                MenuBarKeyDisplayRow(id: "a", name: "A", symbolName: "key.fill", text: "$1.23"),
                MenuBarKeyDisplayRow(id: "b", name: "B", symbolName: "key.fill", text: "$2.34"),
            ]
        )
        let threeColumns = StatusBarController.statusItemLength(
            forKeyRows: (1...5).map {
                MenuBarKeyDisplayRow(id: "\($0)", name: "Key \($0)", symbolName: "key.fill", text: "$\($0).00")
            }
        )

        XCTAssertGreaterThan(threeColumns, oneColumn)
    }
}
