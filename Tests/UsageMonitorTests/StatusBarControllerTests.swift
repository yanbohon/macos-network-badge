import AppKit
import XCTest
@testable import UsageMonitor

@MainActor
final class StatusBarControllerTests: XCTestCase {
    func testStatusBarTitleUsesLatestStatusAndDisplayTextForAccessibility() {
        let cells = [
            ServiceStatusDisplayCell(kind: .green, probe: nil),
            ServiceStatusDisplayCell(kind: .yellow, probe: nil),
            ServiceStatusDisplayCell(kind: .red, probe: nil),
            ServiceStatusDisplayCell(kind: .gray, probe: nil),
        ]

        let title = StatusBarController.titleText(
            displayText: "$52.58",
            statusCells: cells,
            layoutMode: .horizontalFive,
            showMenuBarDecimals: true
        )

        XCTAssertEqual(title, "服务状态未知 $52.58")
    }

    func testStatusBarLengthExpandsWithDisplayTextInsteadOfUsingFixedWidth() {
        let shortWidth = StatusBarController.statusItemLength(
            for: "$5",
            layoutMode: .horizontalFive,
            showMenuBarDecimals: true
        )
        let longWidth = StatusBarController.statusItemLength(
            for: "$105.43",
            layoutMode: .horizontalFive,
            showMenuBarDecimals: true
        )

        XCTAssertLessThan(shortWidth, longWidth)
        XCTAssertGreaterThan(shortWidth, 0)
    }

    func testStatusBarUsesExplicitPaddingAndHorizontalGridMinimumWidth() {
        XCTAssertEqual(StatusBarController.horizontalPadding, 1)
        XCTAssertEqual(StatusBarController.verticalPadding, 1)
        XCTAssertEqual(StatusBarController.textWidthSlack, 3)
        XCTAssertEqual(StatusBarController.horizontalTextHeightSlack, 2)
        XCTAssertEqual(StatusBarController.horizontalContentOffsetY, -1)

        let minimumGridWidth =
            CGFloat(6) * MenuBarTitleView.statusCellSize.width
            + CGFloat(5) * MenuBarTitleView.statusCellSpacing
            + (StatusBarController.horizontalPadding * 2)
        XCTAssertGreaterThanOrEqual(
            StatusBarController.statusItemLength(
                for: "",
                layoutMode: .horizontalFive,
                showMenuBarDecimals: true
            ),
            ceil(minimumGridWidth)
        )
    }

    func testStatusBarTitleReflectsLatestKnownCellKind() {
        let title = StatusBarController.titleText(
            displayText: "$415.96",
            statusCells: [
                ServiceStatusDisplayCell(kind: .gray, probe: nil),
                ServiceStatusDisplayCell(kind: .yellow, probe: nil),
                ServiceStatusDisplayCell(kind: .green, probe: nil),
            ]
            ,
            layoutMode: .horizontalFive,
            showMenuBarDecimals: true
        )

        XCTAssertEqual(title, "服务状态正常 $415.96")
    }

    func testVerticalLayoutUsesNarrowerMinimumStatusWidthThanHorizontal() {
        let horizontalWidth = StatusBarController.statusItemLength(
            for: "",
            layoutMode: .horizontalFive,
            showMenuBarDecimals: true
        )
        let verticalWidth = StatusBarController.statusItemLength(
            for: "",
            layoutMode: .verticalTwo,
            showMenuBarDecimals: true
        )

        XCTAssertLessThan(verticalWidth, horizontalWidth)
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

    func testHorizontalCurrencyTextUsesOpticalLeftOffsetOnlyForDollarValues() {
        XCTAssertEqual(
            StatusBarController.horizontalTextOffsetX(for: "$13", layoutMode: .horizontalFive),
            0
        )
        XCTAssertEqual(
            StatusBarController.horizontalTextOffsetX(for: "未刷新", layoutMode: .horizontalFive),
            0
        )
        XCTAssertEqual(
            StatusBarController.horizontalTextOffsetX(for: "$13", layoutMode: .verticalTwo),
            0
        )
    }

    func testHorizontalTextFrameCentersFinalHeightWithSlack() {
        let frame = StatusBarController.horizontalTextFrame(
            in: NSRect(x: 1, y: 1, width: 46, height: 20),
            bottomSectionHeight: 15,
            labelSize: NSSize(width: 23, height: 15),
            displayText: "$18",
            layoutMode: .horizontalFive
        )

        XCTAssertEqual(frame.height, 17)
        XCTAssertEqual(frame.minY, -1)
        XCTAssertEqual(frame.width, 46)
    }

    func testHorizontalLayoutStatusCellCountTracksDecimalPreference() {
        XCTAssertEqual(ServiceStatusLayoutMode.horizontalFive.statusCellCount(showMenuBarDecimals: true), 6)
        XCTAssertEqual(ServiceStatusLayoutMode.horizontalFive.statusCellCount(showMenuBarDecimals: false), 4)
        XCTAssertEqual(ServiceStatusLayoutMode.verticalTwo.statusCellCount(showMenuBarDecimals: true), 2)
    }

    func testStatusBarCanRenderSixHorizontalStatusCells() {
        XCTAssertEqual(StatusBarController.maximumStatusCellCount, 6)
    }
}
