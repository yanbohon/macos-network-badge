import AppKit
import XCTest
@testable import UsageMonitor

@MainActor
final class StatusBarControllerTests: XCTestCase {
    func testStatusBarControllerCanSkipStartingMonitorsForLaunchCheck() {
        let usageTimers = ManualTimerFactory()
        let serviceTimers = ManualTimerFactory()
        let usageMonitor = UsageSnapshotMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: usageTimers
        )
        let serviceMonitor = ServiceStatusMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            timerFactory: serviceTimers
        )

        _ = StatusBarController(
            usageMonitor: usageMonitor,
            serviceStatusMonitor: serviceMonitor,
            settingsWindowController: SettingsWindowController(activateApplication: {}),
            startsMonitors: false
        )

        XCTAssertEqual(usageTimers.scheduledIntervals, [])
        XCTAssertEqual(serviceTimers.scheduledIntervals, [])
    }

    func testPopoverUsesHostedContentFittingSizeForAnchorPosition() throws {
        let usageMonitor = UsageSnapshotMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )
        let serviceMonitor = ServiceStatusMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            timerFactory: ManualTimerFactory()
        )
        let controller = StatusBarController(
            usageMonitor: usageMonitor,
            serviceStatusMonitor: serviceMonitor,
            settingsWindowController: SettingsWindowController(activateApplication: {}),
            startsMonitors: false
        )
        let popover = try XCTUnwrap(
            Mirror(reflecting: controller).children.first(where: { $0.label == "popover" })?.value as? NSPopover
        )
        let hostedView = try XCTUnwrap(popover.contentViewController?.view)

        XCTAssertEqual(popover.contentSize, hostedView.fittingSize)
    }

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
        XCTAssertEqual(StatusBarController.keyTextFontSize, 8)
        XCTAssertEqual(StatusBarController.textWidthSlack, 3)
        XCTAssertEqual(StatusBarController.keyTextWidthSlack, 2)
        XCTAssertEqual(StatusBarController.horizontalTextHeightSlack, 2)
        XCTAssertEqual(StatusBarController.keyTextHeightSlack, 1)
        XCTAssertEqual(StatusBarController.keyColumnSpacing, 2)
        XCTAssertEqual(StatusBarController.keyRowSpacing, 0)
        XCTAssertEqual(StatusBarController.keySymbolWidth, 9)
        XCTAssertEqual(StatusBarController.keySymbolOpticalLiftY, 1)
        XCTAssertEqual(StatusBarController.keySymbolTextSpacing, 1)
        XCTAssertEqual(StatusBarController.maximumStatusCellCount, 3)
        XCTAssertEqual(ServiceStatusLayoutMode.allCases, [.verticalTwo])
        XCTAssertEqual(
            ServiceStatusLayoutMode.verticalTwo.statusCellCount(keyCount: 1, showMenuBarDecimals: true),
            2
        )
        XCTAssertEqual(
            ServiceStatusLayoutMode.verticalTwo.statusCellCount(keyCount: 2, showMenuBarDecimals: true),
            3
        )
        XCTAssertEqual(
            ServiceStatusLayoutMode.verticalTwo.statusCellCount(keyCount: 4, showMenuBarDecimals: false),
            3
        )
        XCTAssertEqual(StatusBarController.statusCellCount(forKeyCount: 0), 2)
        XCTAssertEqual(StatusBarController.statusCellCount(forKeyCount: 1), 2)
        XCTAssertEqual(StatusBarController.statusCellCount(forKeyCount: 2), 3)
        XCTAssertEqual(StatusBarController.statusCellCount(forKeyCount: 4), 3)
    }

    func testMenuBarKeySymbolUsesCenteredOpticalOffset() {
        XCTAssertEqual(StatusBarController.keySymbolOffsetY(for: 10), 1.5)
        XCTAssertEqual(StatusBarController.keySymbolOffsetY(for: 15), 4)
    }

    func testFourKeyStatusBarLengthStaysCompact() {
        let rows = [
            MenuBarKeyDisplayRow(id: "a", name: "A", symbolName: "key.fill", text: "$105.43"),
            MenuBarKeyDisplayRow(id: "b", name: "B", symbolName: "key.fill", text: "$105.43"),
            MenuBarKeyDisplayRow(id: "c", name: "C", symbolName: "key.fill", text: "$105.43"),
            MenuBarKeyDisplayRow(id: "d", name: "D", symbolName: "key.fill", text: "$105.43"),
        ]

        XCTAssertLessThan(StatusBarController.statusItemLength(forKeyRows: rows), 120)
    }

    func testSingleKeyStatusBarUsesOriginalTextScale() {
        let row = MenuBarKeyDisplayRow(id: "a", name: "A", symbolName: "key.fill", text: "$105.43")
        let compactRows = [row, row]

        XCTAssertEqual(StatusBarController.keyTextSize(for: row.text, keyCount: 1).height, 15)
        XCTAssertEqual(StatusBarController.keySymbolWidth(forKeyCount: 1), 11)
        XCTAssertEqual(StatusBarController.keyTextSize(for: row.text, keyCount: compactRows.count).height, 10)
        XCTAssertEqual(StatusBarController.keySymbolWidth(forKeyCount: compactRows.count), 9)
    }

    func testKeySymbolsCanBeHiddenGloballyAcrossSingleAndMultiKeyLayouts() {
        let row = MenuBarKeyDisplayRow(id: "a", name: "A", symbolName: "key.fill", text: "$105.43")
        let compactRows = [row, row]

        XCTAssertFalse(StatusBarController.shouldHideKeySymbol(hideMenuBarSymbols: false))
        XCTAssertTrue(StatusBarController.shouldHideKeySymbol(hideMenuBarSymbols: true))
        XCTAssertEqual(StatusBarController.keySymbolWidth(forKeyCount: 1, hideMenuBarSymbols: true), 0)
        XCTAssertEqual(StatusBarController.keySymbolTextSpacing(hideMenuBarSymbols: true), 0)
        XCTAssertEqual(StatusBarController.keySymbolWidth(forKeyCount: compactRows.count, hideMenuBarSymbols: true), 0)
        XCTAssertEqual(StatusBarController.keySymbolTextSpacing(hideMenuBarSymbols: true), 0)
        XCTAssertLessThan(
            StatusBarController.statusItemLength(forKeyRows: [row], hideMenuBarSymbols: true),
            StatusBarController.statusItemLength(forKeyRows: [row], hideMenuBarSymbols: false)
        )
        XCTAssertLessThan(
            StatusBarController.statusItemLength(forKeyRows: compactRows, hideMenuBarSymbols: true),
            StatusBarController.statusItemLength(forKeyRows: compactRows, hideMenuBarSymbols: false)
        )
    }

    func testSingleKeyHeightUsesOneRowWhenSymbolsAreHidden() {
        let row = MenuBarKeyDisplayRow(id: "a", name: "A", symbolName: "key.fill", text: "$105.43")
        let expectedHeight = max(
            ceil(StatusBarController.keyTextSize(for: row.text, keyCount: 1).height),
            StatusBarController.statusStackHeight(
                for: .verticalTwo,
                keyCount: 1,
                showMenuBarDecimals: true
            )
        ) + (StatusBarController.verticalPadding * 2)

        XCTAssertEqual(
            StatusBarController.statusItemHeight(
                forKeyRows: [row],
                showMenuBarDecimals: true,
                hideMenuBarSymbols: true
            ),
            expectedHeight
        )
    }

    func testTwoKeyHeightStillUsesTwoRows() {
        let rows = [
            MenuBarKeyDisplayRow(id: "a", name: "A", symbolName: "key.fill", text: "$105.43"),
            MenuBarKeyDisplayRow(id: "b", name: "B", symbolName: "key.fill", text: "$105.43"),
        ]
        let rowHeight = ceil(StatusBarController.keyTextSize(for: rows[0].text, keyCount: rows.count).height)
        let expectedHeight = max(
            (rowHeight * 2) + StatusBarController.keyRowSpacing,
            StatusBarController.statusStackHeight(
                for: .verticalTwo,
                keyCount: rows.count,
                showMenuBarDecimals: true
            )
        ) + (StatusBarController.verticalPadding * 2)

        XCTAssertEqual(
            StatusBarController.statusItemHeight(
                forKeyRows: rows,
                showMenuBarDecimals: true,
                hideMenuBarSymbols: true
            ),
            expectedHeight
        )
    }

    func testSingleKeyStatusCellsCenterWithinOneRowHeight() {
        let contentRect = NSRect(x: 1, y: 1, width: 80, height: 15)
        let stackHeight = StatusBarController.statusStackHeight(
            for: .verticalTwo,
            keyCount: 1,
            showMenuBarDecimals: true
        )

        XCTAssertEqual(
            StatusBarController.verticalGridY(in: contentRect, stackHeight: stackHeight),
            3.75
        )
    }

    func testStatusCellsUseSingleThreeCellColumn() {
        let threeCellHeight = (MenuBarTitleView.statusCellSize.height * 3)
            + (MenuBarTitleView.statusCellSpacing * 2)
        let oneCellWidth = MenuBarTitleView.statusCellSize.width

        XCTAssertEqual(
            StatusBarController.statusStackHeight(
                for: .verticalTwo,
                keyCount: 2,
                showMenuBarDecimals: true
            ),
            threeCellHeight
        )
        XCTAssertEqual(
            StatusBarController.statusStripWidth(
                for: .verticalTwo,
                keyCount: 2,
                showMenuBarDecimals: true
            ),
            oneCellWidth
        )
        XCTAssertEqual(
            StatusBarController.statusCellFrame(at: 0, gridX: 1, gridY: 2, keyCount: 2).origin,
            NSPoint(x: 1, y: 13)
        )
        XCTAssertEqual(
            StatusBarController.statusCellFrame(at: 1, gridX: 1, gridY: 2, keyCount: 2).origin,
            NSPoint(x: 1, y: 7.5)
        )
        XCTAssertEqual(
            StatusBarController.statusCellFrame(at: 2, gridX: 1, gridY: 2, keyCount: 2).origin,
            NSPoint(x: 1, y: 2)
        )
    }

    func testStatusBarBadgeImageRendersVisiblePixels() throws {
        let rows = [
            MenuBarKeyDisplayRow(id: "a", name: "A", symbolName: "key.fill", text: "$0.03"),
            MenuBarKeyDisplayRow(id: "b", name: "B", symbolName: "key.fill", text: "未配置"),
        ]
        let cells = [
            ServiceStatusDisplayCell(kind: .green, probe: nil),
            ServiceStatusDisplayCell(kind: .yellow, probe: nil),
            ServiceStatusDisplayCell(kind: .red, probe: nil),
        ]

        let image = StatusBarController.statusItemImage(
            keyRows: rows,
            statusCells: cells,
            statusCellsAreStale: false,
            showMenuBarDecimals: true,
            hideMenuBarSymbols: true,
            height: 24
        )

        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let dataProvider = try XCTUnwrap(cgImage.dataProvider)
        let data = try XCTUnwrap(dataProvider.data)
        let bytes = CFDataGetBytePtr(data)
        let nonTransparentPixels = stride(from: 3, to: CFDataGetLength(data), by: 4)
            .filter { bytes?[$0] ?? 0 > 0 }
            .count

        XCTAssertGreaterThan(nonTransparentPixels, 0)
    }

    func testStatusBarButtonUsesBadgeSubviewAsVisibleRenderer() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/UsageMonitor/Controllers/StatusBarController.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("button.addSubview(badgeView)"))
        XCTAssertTrue(source.contains("badgeView.update("))
        XCTAssertFalse(source.contains("statusItem.button?.image = image"))
    }

    func testStatusBarBadgeImageReflectsPerKeySymbolColor() throws {
        let redRows = [
            MenuBarKeyDisplayRow(
                id: "a",
                name: "A",
                symbolName: "key.fill",
                symbolColorHex: "#FF3B30",
                text: "$1.23"
            ),
        ]
        let blueRows = [
            MenuBarKeyDisplayRow(
                id: "a",
                name: "A",
                symbolName: "key.fill",
                symbolColorHex: "#38BDF8",
                text: "$1.23"
            ),
        ]
        let cells = [
            ServiceStatusDisplayCell(kind: .green, probe: nil),
            ServiceStatusDisplayCell(kind: .green, probe: nil),
        ]

        let redImage = StatusBarController.statusItemImage(
            keyRows: redRows,
            statusCells: cells,
            statusCellsAreStale: false,
            showMenuBarDecimals: true,
            hideMenuBarSymbols: false,
            height: 24
        )
        let blueImage = StatusBarController.statusItemImage(
            keyRows: blueRows,
            statusCells: cells,
            statusCellsAreStale: false,
            showMenuBarDecimals: true,
            hideMenuBarSymbols: false,
            height: 24
        )

        let redData = try imageData(redImage)
        let blueData = try imageData(blueImage)

        XCTAssertNotEqual(redData as Data, blueData as Data)
    }

    func testStatusBarControllerUpdatesKeySymbolAfterConfigurationChange() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let usageLoader = RequestRecordingLoader()
        let usageMonitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: usageLoader),
            timerFactory: ManualTimerFactory()
        )
        let serviceMonitor = ServiceStatusMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            client: StubServiceStatusClient(results: [
                .success(Self.statusResult()),
            ]),
            timerFactory: ManualTimerFactory()
        )
        let controller = StatusBarController(
            usageMonitor: usageMonitor,
            serviceStatusMonitor: serviceMonitor,
            settingsWindowController: SettingsWindowController(activateApplication: {}),
            statusBar: .system
        )

        try await Task.sleep(nanoseconds: 100_000_000)

        let button = try statusItemButton(from: controller)
        let initialImageDescription = try XCTUnwrap(firstSymbolImageDescription(in: button))
        XCTAssertTrue(initialImageDescription.contains("symbol = key.fill"))

        let keyID = usageMonitor.usageKeys[0].id
        usageMonitor.updateKeyConfiguration(
            id: keyID,
            name: "Work",
            symbolName: "star.fill",
            apiKey: "key-a",
            baseURLMode: .inherited,
            baseURLOverride: ""
        )

        try await Task.sleep(nanoseconds: 100_000_000)

        let updatedImageDescription = try XCTUnwrap(firstSymbolImageDescription(in: button))
        XCTAssertTrue(updatedImageDescription.contains("symbol = star.fill"))
    }

    func testStatusBarControllerUsesSelectedServiceModel() async throws {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let usageMonitor = UsageSnapshotMonitor(
            userDefaults: defaults,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )
        let serviceMonitor = ServiceStatusMonitor(
            userDefaults: defaults,
            client: StubServiceStatusClient(results: [.success(Self.statusResult())]),
            timerFactory: ManualTimerFactory()
        )
        let controller = StatusBarController(
            usageMonitor: usageMonitor,
            serviceStatusMonitor: serviceMonitor,
            settingsWindowController: SettingsWindowController(activateApplication: {}),
            statusBar: .system
        )

        while serviceMonitor.lastSuccessfulRefresh == nil {
            await Task.yield()
        }
        await Task.yield()

        let button = try statusItemButton(from: controller)
        XCTAssertTrue(try XCTUnwrap(button.accessibilityTitle()).contains("服务状态正常"))

        serviceMonitor.menuBarModel = .gpt55
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(try XCTUnwrap(button.accessibilityTitle()).contains("服务状态失败"))
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

    private func statusItemButton(from controller: StatusBarController) throws -> NSStatusBarButton {
        let statusItem = try XCTUnwrap(
            Mirror(reflecting: controller).children.first(where: { $0.label == "statusItem" })?.value as? NSStatusItem
        )
        return try XCTUnwrap(statusItem.button)
    }

    private func imageData(_ image: NSImage) throws -> CFData {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil))
        return try XCTUnwrap(cgImage.dataProvider?.data)
    }

    private func firstSymbolImageDescription(in button: NSStatusBarButton) throws -> String {
        let imageView = try XCTUnwrap(findFirstImageView(in: button))
        return try XCTUnwrap(imageView.image?.description)
    }

    private func findFirstImageView(in view: NSView) -> NSImageView? {
        if let imageView = view as? NSImageView {
            return imageView
        }
        for subview in view.subviews {
            if let imageView = findFirstImageView(in: subview) {
                return imageView
            }
        }
        return nil
    }

    private static func statusResult() -> StatusAPIResult {
        StatusAPIResult(
            response: ServiceStatusResponse(
                allOK: true,
                generatedAt: 1_778_762_578,
                services: [
                    ServiceStatusService(
                        model: "gpt-5.6-sol",
                        uptimePct: 100,
                        last: ServiceStatusProbe(ts: 9, ok: true, latencyMS: 900, error: nil),
                        history: [
                            ServiceStatusProbe(ts: 9, ok: true, latencyMS: 900, error: nil),
                        ]
                    ),
                    ServiceStatusService(
                        model: "gpt-5.5",
                        uptimePct: 99.5,
                        last: ServiceStatusProbe(ts: 9, ok: true, latencyMS: 1_111, error: nil),
                        history: [
                            ServiceStatusProbe(ts: 1, ok: true, latencyMS: 100, error: nil),
                            ServiceStatusProbe(ts: 2, ok: true, latencyMS: 3_000, error: nil),
                            ServiceStatusProbe(ts: 3, ok: false, latencyMS: nil, error: "timeout"),
                        ]
                    ),
                ]
            ),
            prettyRawJSON: #"{"all_ok":true}"#
        )
    }
}
