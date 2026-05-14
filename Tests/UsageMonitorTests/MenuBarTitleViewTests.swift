import SwiftUI
import XCTest
@testable import UsageMonitor

final class MenuBarTitleViewTests: XCTestCase {
    func testTitleViewReceivesUsageTextColorAndStatusCells() {
        let cells = [
            ServiceStatusDisplayCell(kind: .green, probe: nil),
            ServiceStatusDisplayCell(kind: .yellow, probe: nil),
            ServiceStatusDisplayCell(kind: .red, probe: nil),
            ServiceStatusDisplayCell(kind: .gray, probe: nil),
        ]

        let view = MenuBarTitleView(
            text: "$84.04",
            color: .green,
            statusCells: cells,
            statusCellsAreStale: true
        )

        XCTAssertEqual(view.text, "$84.04")
        XCTAssertEqual(view.statusCells.map(\.kind), [.green, .yellow, .red, .gray])
        XCTAssertTrue(view.statusCellsAreStale)
    }

    func testStatusCellsExposeOneStableMenuBarSymbolForLatestStatus() {
        let cells = [
            ServiceStatusDisplayCell(kind: .green, probe: nil),
            ServiceStatusDisplayCell(kind: .yellow, probe: nil),
            ServiceStatusDisplayCell(kind: .red, probe: nil),
            ServiceStatusDisplayCell(kind: .gray, probe: nil),
        ]

        XCTAssertEqual(MenuBarTitleView.statusSymbolText(for: cells), "■")
        XCTAssertEqual(MenuBarTitleView.latestStatusKind(for: cells), .gray)
    }

    func testMenuBarTextPlacesStatusBeforeDollarAmountInOneString() {
        let cells = [
            ServiceStatusDisplayCell(kind: .green, probe: nil),
            ServiceStatusDisplayCell(kind: .yellow, probe: nil),
            ServiceStatusDisplayCell(kind: .red, probe: nil),
        ]

        XCTAssertEqual(MenuBarTitleView.combinedText(text: "$84.04", statusCells: cells), "■ $84.04")
    }

    func testMenuBarTitleUsesCompactWidthForSingleStatusPrefix() {
        XCTAssertLessThanOrEqual(MenuBarTitleView.menuBarTitleWidth, 90)
        XCTAssertGreaterThanOrEqual(MenuBarTitleView.menuBarTitleWidth, 72)
    }
}
