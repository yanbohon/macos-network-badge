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

    func testStatusCellsNormalizeToFiveEntries() {
        let cells = [
            ServiceStatusDisplayCell(kind: .green, probe: nil),
            ServiceStatusDisplayCell(kind: .yellow, probe: nil),
            ServiceStatusDisplayCell(kind: .red, probe: nil),
            ServiceStatusDisplayCell(kind: .gray, probe: nil),
        ]

        let normalized = MenuBarTitleView.normalizedStatusCells(for: cells, count: 5)

        XCTAssertEqual(normalized.count, 5)
        XCTAssertEqual(normalized.suffix(4).map(\.kind), [.green, .yellow, .red, .gray])
        XCTAssertEqual(normalized.prefix(1).map(\.kind), [.gray])
        XCTAssertEqual(MenuBarTitleView.latestStatusKind(for: cells, count: 5), .gray)
    }

    func testStatusCellsNormalizeToDynamicHorizontalCounts() {
        let cells = [
            ServiceStatusDisplayCell(kind: .green, probe: nil),
            ServiceStatusDisplayCell(kind: .yellow, probe: nil),
            ServiceStatusDisplayCell(kind: .red, probe: nil),
            ServiceStatusDisplayCell(kind: .gray, probe: nil),
        ]

        let withDecimals = MenuBarTitleView.normalizedStatusCells(for: cells, count: 6)
        let withoutDecimals = MenuBarTitleView.normalizedStatusCells(for: cells, count: 4)

        XCTAssertEqual(withDecimals.count, 6)
        XCTAssertEqual(withDecimals.prefix(2).map(\.kind), [.gray, .gray])
        XCTAssertEqual(withDecimals.suffix(4).map(\.kind), [.green, .yellow, .red, .gray])

        XCTAssertEqual(withoutDecimals.count, 4)
        XCTAssertEqual(withoutDecimals.map(\.kind), [.green, .yellow, .red, .gray])
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
