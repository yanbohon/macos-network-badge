import AppKit
import XCTest
@testable import UsageMonitor

@MainActor
final class StatusBarControllerTests: XCTestCase {
    func testStatusBarTitleUsesOneStatusBlockBeforeUsageText() {
        let cells = [
            ServiceStatusDisplayCell(kind: .green, probe: nil),
            ServiceStatusDisplayCell(kind: .yellow, probe: nil),
            ServiceStatusDisplayCell(kind: .red, probe: nil),
            ServiceStatusDisplayCell(kind: .gray, probe: nil),
        ]

        let title = StatusBarController.titleText(usageText: "$52.58", statusCells: cells)

        XCTAssertEqual(title, "■ $52.58")
    }

    func testStatusBarLengthExpandsWithUsageTextInsteadOfUsingFixedWidth() {
        let shortWidth = StatusBarController.statusItemLength(for: "$5")
        let longWidth = StatusBarController.statusItemLength(for: "$105.43")

        XCTAssertLessThan(shortWidth, longWidth)
        XCTAssertGreaterThan(shortWidth, 0)
    }

    func testStatusBarUsesExplicitSymmetricHorizontalPadding() {
        XCTAssertEqual(StatusBarController.horizontalPadding, 6)
        XCTAssertEqual(StatusBarController.contentSpacing, 4)
        XCTAssertEqual(StatusBarController.statusIndicatorSize.width, 8)
        XCTAssertEqual(StatusBarController.statusIndicatorSize.height, 8)
    }

    func testAttributedTitleKeepsUsageTextWhiteAndColorsStatusFromLatestCell() {
        let title = StatusBarController.attributedTitle(
            usageText: "$52.58",
            statusCells: [
                ServiceStatusDisplayCell(kind: .green, probe: nil),
                ServiceStatusDisplayCell(kind: .yellow, probe: nil),
                ServiceStatusDisplayCell(kind: .red, probe: nil),
            ]
        )

        XCTAssertEqual(title.string, "■ $52.58")
        let statusColor = title.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor
        XCTAssertEqual(statusColor, .systemRed)

        let usageColor = title.attribute(
            .foregroundColor,
            at: title.length - 1,
            effectiveRange: nil
        ) as? NSColor
        XCTAssertEqual(usageColor, .white)
    }

    func testAttributedTitleUsesGrayStatusBlockWhenCellsAreMissing() {
        let title = StatusBarController.attributedTitle(
            usageText: "$52.58",
            statusCells: []
        )

        XCTAssertEqual(title.string, "■ $52.58")
        let statusColor = title.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor
        XCTAssertEqual(statusColor, .secondaryLabelColor)

        let usageColor = title.attribute(
            .foregroundColor,
            at: title.length - 1,
            effectiveRange: nil
        ) as? NSColor
        XCTAssertEqual(usageColor, .white)
    }
}
