import AppKit
import XCTest
@testable import UsageMonitor

@MainActor
final class StatusBarControllerTests: XCTestCase {
    func testStatusBarTitleUsesLatestStatusAndDisplayTextForAccessibility() {
        let title = StatusBarController.titleText(
            displayText: "$52.58",
            statusCells: [
                ServiceStatusDisplayCell(kind: .green, probe: nil),
                ServiceStatusDisplayCell(kind: .red, probe: nil),
            ],
            layoutMode: .verticalTwo,
            showMenuBarDecimals: true
        )

        XCTAssertEqual(title, "服务状态失败 $52.58")
    }

    func testStatusBarLengthExpandsWithDisplayTextInsteadOfUsingFixedWidth() {
        let shortWidth = StatusBarController.statusItemLength(
            for: "$5",
            layoutMode: .verticalTwo,
            showMenuBarDecimals: true
        )
        let longWidth = StatusBarController.statusItemLength(
            for: "$105.43",
            layoutMode: .verticalTwo,
            showMenuBarDecimals: true
        )

        XCTAssertLessThan(shortWidth, longWidth)
        XCTAssertGreaterThan(shortWidth, 0)
    }

    func testStatusBarUsesExplicitVerticalOnlyMetrics() {
        XCTAssertEqual(StatusBarController.horizontalPadding, 1)
        XCTAssertEqual(StatusBarController.verticalPadding, 1)
        XCTAssertEqual(StatusBarController.textWidthSlack, 3)
        XCTAssertEqual(StatusBarController.horizontalTextHeightSlack, 2)
        XCTAssertEqual(StatusBarController.maximumStatusCellCount, 2)
        XCTAssertEqual(ServiceStatusLayoutMode.allCases, [.verticalTwo])
        XCTAssertEqual(ServiceStatusLayoutMode.verticalTwo.statusCellCount(showMenuBarDecimals: true), 2)
        XCTAssertEqual(ServiceStatusLayoutMode.verticalTwo.statusCellCount(showMenuBarDecimals: false), 2)
    }

    func testVerticalLayoutReservesRoomForStatusStripSpacingAndShortCurrencyText() {
        let displayText = "$5"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let measuredTextWidth = ceil((displayText as NSString).size(withAttributes: [.font: font]).width)
            + StatusBarController.textWidthSlack
        let expectedMinimumWidth =
            StatusBarController.horizontalPadding
            + ceil(MenuBarTitleView.statusCellSize.width)
            + StatusBarController.statusTextSpacing
            + measuredTextWidth
            + StatusBarController.horizontalPadding

        let verticalWidth = StatusBarController.statusItemLength(
            for: displayText,
            layoutMode: .verticalTwo,
            showMenuBarDecimals: true
        )

        XCTAssertGreaterThanOrEqual(verticalWidth, expectedMinimumWidth)
    }

    func testVerticalLayoutUsesOpticalContentOffset() {
        XCTAssertEqual(StatusBarController.verticalStatusOffsetY, 0)
        XCTAssertEqual(StatusBarController.verticalTextOffsetY, -1)

        let contentRect = NSRect(x: 1, y: 1, width: 46, height: 20)
        let gridY = StatusBarController.verticalGridY(
            in: contentRect,
            stackHeight: 10
        )
        let textFrame = StatusBarController.verticalTextFrame(
            in: contentRect,
            labelSize: NSSize(width: 23, height: 15),
            gridX: 1,
            layoutMode: .verticalTwo,
            showMenuBarDecimals: true
        )

        XCTAssertEqual(gridY, 6)
        XCTAssertEqual(textFrame.minX, 10)
        XCTAssertEqual(textFrame.minY, 1)
        XCTAssertEqual(textFrame.width, 37)
        XCTAssertEqual(textFrame.height, 17)
    }
}
