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

    func testStatusCellsNormalizeToVerticalEntries() {
        let cells = [
            ServiceStatusDisplayCell(kind: .green, probe: nil),
            ServiceStatusDisplayCell(kind: .yellow, probe: nil),
            ServiceStatusDisplayCell(kind: .red, probe: nil),
            ServiceStatusDisplayCell(kind: .gray, probe: nil),
        ]

        let normalized = MenuBarTitleView.normalizedStatusCells(for: cells, count: 2)

        XCTAssertEqual(normalized.count, 2)
        XCTAssertEqual(normalized.map(\.kind), [.red, .gray])
        XCTAssertEqual(MenuBarTitleView.latestStatusKind(for: cells, count: 2), .gray)
    }

    func testStatusCellsPadMissingVerticalEntries() {
        let cells = [
            ServiceStatusDisplayCell(kind: .green, probe: nil),
        ]

        let normalized = MenuBarTitleView.normalizedStatusCells(for: cells, count: 2)

        XCTAssertEqual(normalized.map(\.kind), [.gray, .green])
    }

    func testAccessibilityTitlePrefixesLatestStatusDescription() {
        let cells = [
            ServiceStatusDisplayCell(kind: .green, probe: nil),
            ServiceStatusDisplayCell(kind: .yellow, probe: nil),
            ServiceStatusDisplayCell(kind: .red, probe: nil),
        ]

        XCTAssertEqual(
            MenuBarTitleView.accessibilityTitle(text: "$84.04", statusCells: cells, count: 5),
            "服务状态失败 $84.04"
        )
    }

    func testMenuBarTitleUsesSharedStatusCellMetrics() {
        XCTAssertEqual(MenuBarTitleView.statusCellSize.width, 4)
        XCTAssertEqual(MenuBarTitleView.statusCellSize.height, 4)
        XCTAssertEqual(MenuBarTitleView.topSectionRatio, 0.25)
    }
}
