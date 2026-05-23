import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    static let horizontalPadding: CGFloat = 1
    static let verticalPadding: CGFloat = 1
    static let keyTextFontSize: CGFloat = 8
    static let textWidthSlack: CGFloat = 3
    static let keyTextWidthSlack: CGFloat = 2
    static let horizontalTextHeightSlack: CGFloat = 2
    static let keyTextHeightSlack: CGFloat = 1
    static let horizontalContentOffsetY: CGFloat = -1
    static let verticalStatusOffsetY: CGFloat = 0
    static let verticalTextOffsetY: CGFloat = -1
    static let statusTextSpacing: CGFloat = 5
    static let keyColumnSpacing: CGFloat = 2
    static let keyRowSpacing: CGFloat = 0
    static let keySymbolTextSpacing: CGFloat = 1
    static let keySymbolWidth: CGFloat = 9
    static let singleKeySymbolWidth: CGFloat = 11
    static let keySymbolOpticalLiftY: CGFloat = 1
    static let maximumStatusCellCount = 3
    private static let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    private static let keyTextFont = NSFont.monospacedDigitSystemFont(ofSize: keyTextFontSize, weight: .medium)

    private let usageMonitor: UsageSnapshotMonitor
    private let serviceStatusMonitor: ServiceStatusMonitor
    private let settingsWindowController: SettingsWindowController
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let badgeView = StatusBarBadgeView(font: StatusBarController.titleFont)
    private var cancellables: Set<AnyCancellable> = []
    private static let statusItemAutosaveName = NSStatusItem.AutosaveName("UsageMonitor.StatusItem")

    init(
        usageMonitor: UsageSnapshotMonitor,
        serviceStatusMonitor: ServiceStatusMonitor,
        settingsWindowController: SettingsWindowController,
        statusBar: NSStatusBar = .system
    ) {
        self.usageMonitor = usageMonitor
        self.serviceStatusMonitor = serviceStatusMonitor
        self.settingsWindowController = settingsWindowController
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = Self.statusItemAutosaveName
        statusItem.isVisible = true
        super.init()
        configureStatusItem()
        configurePopover()
        bindMonitors()
        usageMonitor.start()
        serviceStatusMonitor.start()
        updateStatusTitle()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    static func titleText(
        displayText: String,
        statusCells: [ServiceStatusDisplayCell],
        layoutMode: ServiceStatusLayoutMode,
        showMenuBarDecimals: Bool
    ) -> String {
        MenuBarTitleView.accessibilityTitle(
            text: displayText,
            statusCells: statusCells,
            count: layoutMode.statusCellCount(showMenuBarDecimals: showMenuBarDecimals)
        )
    }

    static func titleText(
        keyRows: [MenuBarKeyDisplayRow],
        statusCells: [ServiceStatusDisplayCell],
        statusCellsAreStale: Bool
    ) -> String {
        MenuBarTitleView.accessibilityTitle(
            keyRows: keyRows,
            statusCells: statusCells,
            statusCellsAreStale: statusCellsAreStale
        )
    }

    static func statusItemLength(
        for displayText: String,
        layoutMode: ServiceStatusLayoutMode,
        showMenuBarDecimals: Bool
    ) -> CGFloat {
        let textWidth = ceil(textSize(for: displayText).width) + textWidthSlack
        return ceil(
            horizontalPadding
            + statusStripWidth(for: layoutMode, showMenuBarDecimals: showMenuBarDecimals)
            + statusTextSpacing
            + textWidth
            + horizontalPadding
        )
    }

    static func statusItemLength(forKeyRows keyRows: [MenuBarKeyDisplayRow], hideMenuBarSymbols: Bool = false) -> CGFloat {
        let columns = MenuBarTitleView.keyGridColumns(for: keyRows)
        let symbolWidth = keySymbolWidth(forKeyCount: keyRows.count, hideMenuBarSymbols: hideMenuBarSymbols)
        let symbolSpacing = keySymbolTextSpacing(hideMenuBarSymbols: hideMenuBarSymbols)
        let columnWidths = columns.map { column in
            column.map { row in
                symbolWidth
                    + symbolSpacing
                    + ceil(keyTextSize(for: row.text, keyCount: keyRows.count).width)
                    + keyTextWidthSlack
            }.max() ?? 0
        }
        let keysWidth = columnWidths.reduce(0, +)
            + CGFloat(max(0, columns.count - 1)) * keyColumnSpacing
        return ceil(
            horizontalPadding
            + statusStripWidth(for: .verticalTwo, keyCount: keyRows.count, showMenuBarDecimals: true)
            + statusTextSpacing
            + keysWidth
            + horizontalPadding
        )
    }

    static func statusItemHeight(
        forKeyRows keyRows: [MenuBarKeyDisplayRow],
        showMenuBarDecimals: Bool,
        hideMenuBarSymbols: Bool
    ) -> CGFloat {
        let columns = MenuBarTitleView.keyGridColumns(for: keyRows)
        var tallestColumnHeight: CGFloat = 0
        for column in columns {
            var columnHeight: CGFloat = 0
            for row in column {
                columnHeight += ceil(keyTextSize(for: row.text, keyCount: keyRows.count).height)
            }
            columnHeight += CGFloat(max(0, column.count - 1)) * keyRowSpacing
            tallestColumnHeight = max(tallestColumnHeight, columnHeight)
        }
        return max(
            tallestColumnHeight,
            statusStackHeight(
                for: .verticalTwo,
                keyCount: keyRows.count,
                showMenuBarDecimals: showMenuBarDecimals
            )
        )
            + (verticalPadding * 2)
    }

    static func statusCellCount(forKeyCount keyCount: Int) -> Int {
        3
    }

    static func statusItemImage(
        keyRows: [MenuBarKeyDisplayRow],
        statusCells: [ServiceStatusDisplayCell],
        statusCellsAreStale: Bool,
        showMenuBarDecimals: Bool,
        hideMenuBarSymbols: Bool,
        height: CGFloat
    ) -> NSImage {
        let width = statusItemLength(
            forKeyRows: keyRows,
            hideMenuBarSymbols: hideMenuBarSymbols
        )
        let imageSize = NSSize(width: width, height: max(1, height))
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: imageSize).fill()
        drawStatusItemContent(
            in: NSRect(origin: .zero, size: imageSize),
            keyRows: keyRows,
            statusCells: statusCells,
            statusCellsAreStale: statusCellsAreStale,
            showMenuBarDecimals: showMenuBarDecimals,
            hideMenuBarSymbols: hideMenuBarSymbols
        )
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    static func drawStatusItemContent(
        in bounds: NSRect,
        keyRows: [MenuBarKeyDisplayRow],
        statusCells: [ServiceStatusDisplayCell],
        statusCellsAreStale: Bool,
        showMenuBarDecimals: Bool,
        hideMenuBarSymbols: Bool
    ) {
        let contentRect = bounds.insetBy(
            dx: horizontalPadding,
            dy: verticalPadding
        )
        let stackHeight = statusStackHeight(
            for: .verticalTwo,
            keyCount: keyRows.count,
            showMenuBarDecimals: showMenuBarDecimals
        )
        let gridY = verticalGridY(in: contentRect, stackHeight: stackHeight)
        let gridX = contentRect.minX

        for (index, cell) in statusCells.prefix(maximumStatusCellCount).enumerated() {
            cell.kind.statusBarColor
                .withAlphaComponent(statusCellOpacity(for: cell.kind, statusCellsAreStale: statusCellsAreStale))
                .setFill()
            let rect = statusCellFrame(
                at: index,
                gridX: gridX,
                gridY: gridY,
                keyCount: keyRows.count
            )
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
        }

        let columns = MenuBarTitleView.keyGridColumns(for: keyRows)
        var x = gridX + statusStripWidth(
            for: .verticalTwo,
            keyCount: keyRows.count,
            showMenuBarDecimals: showMenuBarDecimals
        )
            + statusTextSpacing
        let effectiveKeyCount = keyRows.count
        let shouldHideSymbols = shouldHideKeySymbol(hideMenuBarSymbols: hideMenuBarSymbols)
        let symbolWidth = keySymbolWidth(
            forKeyCount: effectiveKeyCount,
            hideMenuBarSymbols: hideMenuBarSymbols
        )
        let symbolSpacing = keySymbolTextSpacing(hideMenuBarSymbols: hideMenuBarSymbols)
        let textColor = NSColor.labelColor

        for column in columns {
            let columnWidth = column.map {
                symbolWidth
                    + symbolSpacing
                    + ceil(keyTextSize(for: $0.text, keyCount: effectiveKeyCount).width)
                    + keyTextWidthSlack
            }.max() ?? 0
            for (rowIndex, row) in column.enumerated() {
                let rowHeight = ceil(keyTextSize(for: row.text, keyCount: effectiveKeyCount).height)
                let totalRowsHeight = CGFloat(column.count) * rowHeight
                    + CGFloat(max(0, column.count - 1)) * keyRowSpacing
                let topY = contentRect.minY + floor((contentRect.height - totalRowsHeight) / 2)
                    + CGFloat(column.count - 1 - rowIndex) * (rowHeight + keyRowSpacing)
                    + verticalTextOffsetY

                if !shouldHideSymbols {
                    let symbolName = MenuBarTitleView.resolvedSymbolName(row.symbolName)
                    let symbolRect = NSRect(
                        x: x,
                        y: topY + keySymbolOffsetY(for: rowHeight, keyCount: effectiveKeyCount),
                        width: symbolWidth,
                        height: symbolWidth
                    )
                    drawSymbol(named: symbolName, in: symbolRect, tintColor: textColor)
                }

                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = .left
                paragraphStyle.lineBreakMode = .byClipping
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: keyTextFont(forKeyCount: effectiveKeyCount),
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle,
                ]
                let measuredHeight = ceil(keyTextSize(for: row.text, keyCount: effectiveKeyCount).height)
                let drawHeight = measuredHeight + keyTextHeightSlack
                let textRect = NSRect(
                    x: x + symbolWidth + symbolSpacing,
                    y: topY,
                    width: max(0, columnWidth - symbolWidth - symbolSpacing),
                    height: rowHeight + keyTextHeightSlack
                )
                let drawRect = NSRect(
                    x: textRect.minX,
                    y: textRect.midY - (drawHeight / 2),
                    width: textRect.width,
                    height: drawHeight
                )
                (row.text as NSString).draw(
                    with: drawRect,
                    options: [.usesLineFragmentOrigin],
                    attributes: attributes,
                    context: nil
                )
            }
            x += columnWidth + keyColumnSpacing
        }
    }

    static func drawSymbol(named symbolName: String, in rect: NSRect, tintColor: NSColor) {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return }
        let configured = image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: rect.height, weight: .medium)
        ) ?? image
        NSGraphicsContext.saveGraphicsState()
        configured.draw(in: rect)
        tintColor.setFill()
        rect.fill(using: .sourceAtop)
        NSGraphicsContext.restoreGraphicsState()
    }

    static func statusCellOpacity(for kind: ServiceStatusCellKind, statusCellsAreStale: Bool) -> CGFloat {
        let baseOpacity: CGFloat = kind == .gray ? 0.45 : 1
        return statusCellsAreStale ? baseOpacity * 0.55 : baseOpacity
    }

    static func horizontalTextOffsetX(for displayText: String, layoutMode: ServiceStatusLayoutMode) -> CGFloat {
        0
    }

    static func textSize(for displayText: String) -> NSSize {
        (displayText as NSString).size(withAttributes: [.font: titleFont])
    }

    static func keyTextSize(for displayText: String) -> NSSize {
        (displayText as NSString).size(withAttributes: [.font: keyTextFont])
    }

    static func keyTextSize(for displayText: String, keyCount: Int) -> NSSize {
        (displayText as NSString).size(withAttributes: [.font: keyTextFont(forKeyCount: keyCount)])
    }

    static func keyTextFont(forKeyCount keyCount: Int) -> NSFont {
        keyCount <= 1 ? titleFont : keyTextFont
    }

    static func keySymbolWidth(forKeyCount keyCount: Int) -> CGFloat {
        keyCount <= 1 ? singleKeySymbolWidth : keySymbolWidth
    }

    static func keySymbolWidth(forKeyCount keyCount: Int, hideMenuBarSymbols: Bool) -> CGFloat {
        shouldHideKeySymbol(hideMenuBarSymbols: hideMenuBarSymbols)
            ? 0
            : keySymbolWidth(forKeyCount: keyCount)
    }

    static func keySymbolTextSpacing(hideMenuBarSymbols: Bool) -> CGFloat {
        shouldHideKeySymbol(hideMenuBarSymbols: hideMenuBarSymbols)
            ? 0
            : keySymbolTextSpacing
    }

    static func shouldHideKeySymbol(hideMenuBarSymbols: Bool) -> Bool {
        hideMenuBarSymbols
    }

    static func keySymbolOffsetY(for rowHeight: CGFloat, keyCount: Int = 2) -> CGFloat {
        ((rowHeight - keySymbolWidth(forKeyCount: keyCount)) / 2) + keySymbolOpticalLiftY
    }

    static func horizontalTextFrame(
        in contentRect: NSRect,
        bottomSectionHeight: CGFloat,
        labelSize: NSSize,
        displayText: String,
        layoutMode: ServiceStatusLayoutMode
    ) -> NSRect {
        let textHeight = ceil(labelSize.height) + horizontalTextHeightSlack
        return NSRect(
            x: contentRect.minX + horizontalTextOffsetX(for: displayText, layoutMode: layoutMode),
            y: contentRect.minY + floor((bottomSectionHeight - textHeight) / 2) + horizontalContentOffsetY,
            width: contentRect.width,
            height: textHeight
        )
    }

    static func verticalGridY(in contentRect: NSRect, stackHeight: CGFloat) -> CGFloat {
        contentRect.minY + ((contentRect.height - stackHeight) / 2) + verticalStatusOffsetY
    }

    static func verticalTextFrame(
        in contentRect: NSRect,
        labelSize: NSSize,
        gridX: CGFloat,
        layoutMode: ServiceStatusLayoutMode,
        showMenuBarDecimals: Bool
    ) -> NSRect {
        let statusWidth = statusStripWidth(for: layoutMode, showMenuBarDecimals: showMenuBarDecimals)
        let textHeight = ceil(labelSize.height) + horizontalTextHeightSlack
        return NSRect(
            x: gridX + statusWidth + statusTextSpacing,
            y: contentRect.minY + floor((contentRect.height - textHeight) / 2) + verticalTextOffsetY,
            width: max(0, contentRect.width - statusWidth - statusTextSpacing),
            height: textHeight
        )
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.image = nil
        button.attributedTitle = NSAttributedString(string: "")
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(badgeView)
        NSLayoutConstraint.activate([
            badgeView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            badgeView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            badgeView.topAnchor.constraint(equalTo: button.topAnchor),
            badgeView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 440, height: 620)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                monitor: usageMonitor,
                serviceStatusMonitor: serviceStatusMonitor,
                settingsWindowController: settingsWindowController
            )
        )
    }

    private func bindMonitors() {
        usageMonitor.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleTitleUpdate()
            }
            .store(in: &cancellables)

        serviceStatusMonitor.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.scheduleTitleUpdate()
            }
            .store(in: &cancellables)
    }

    private func scheduleTitleUpdate() {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusTitle()
        }
    }

    private func updateStatusTitle() {
        let keyRows = usageMonitor.menuBarKeyRows
        let statusCellCount = Self.statusCellCount(forKeyCount: keyRows.count)
        let statusCells = MenuBarTitleView.normalizedStatusCells(
            for: serviceStatusMonitor.displayCells,
            count: statusCellCount
        )
        let itemLength = Self.statusItemLength(
            forKeyRows: keyRows,
            hideMenuBarSymbols: usageMonitor.hideMenuBarSymbols
        )

        statusItem.length = itemLength
        statusItem.button?.image = nil
        badgeView.update(
            keyRows: keyRows,
            statusCells: statusCells,
            statusCellsAreStale: serviceStatusMonitor.isStaleAfterFailure,
            showMenuBarDecimals: usageMonitor.showMenuBarDecimals,
            hideMenuBarSymbols: usageMonitor.hideMenuBarSymbols
        )
        statusItem.button?.setAccessibilityTitle(
            Self.titleText(
                keyRows: keyRows,
                statusCells: statusCells,
                statusCellsAreStale: serviceStatusMonitor.isStaleAfterFailure
            )
        )
        statusItem.button?.needsLayout = true
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private final class StatusBarBadgeView: NSView {
    private let indicatorViews = (0..<StatusBarController.maximumStatusCellCount).map { _ in NSView(frame: .zero) }
    private var textViews: [StatusBarTextView] = []
    private var symbolViews: [NSImageView] = []
    private var keyRows: [MenuBarKeyDisplayRow] = []
    private var statusCells: [ServiceStatusDisplayCell] = []
    private var statusCellsAreStale = false
    private var showMenuBarDecimals = true
    private var hideMenuBarSymbols = false
    private let font: NSFont

    init(font: NSFont) {
        self.font = font
        super.init(frame: .zero)
        indicatorViews.forEach { indicatorView in
            indicatorView.wantsLayer = true
            addSubview(indicatorView)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        let contentRect = bounds.insetBy(
            dx: StatusBarController.horizontalPadding,
            dy: StatusBarController.verticalPadding
        )
        let stackHeight = StatusBarController.statusStackHeight(
            for: .verticalTwo,
            keyCount: keyRows.count,
            showMenuBarDecimals: showMenuBarDecimals
        )
        let gridY = StatusBarController.verticalGridY(in: contentRect, stackHeight: stackHeight)
        let gridX = contentRect.minX

        for (index, indicatorView) in indicatorViews.enumerated() {
            if index < statusCells.count {
                indicatorView.frame = StatusBarController.statusCellFrame(
                    at: index,
                    gridX: gridX,
                    gridY: gridY,
                    keyCount: keyRows.count
                )
            } else {
                indicatorView.frame = .zero
            }
            indicatorView.layer?.cornerRadius = 1
        }

        let columns = MenuBarTitleView.keyGridColumns(for: keyRows)
        var x = gridX + StatusBarController.statusStripWidth(
            for: .verticalTwo,
            keyCount: keyRows.count,
            showMenuBarDecimals: showMenuBarDecimals
        )
            + StatusBarController.statusTextSpacing
        let effectiveKeyCount = keyRows.count
        let shouldHideSymbols = StatusBarController.shouldHideKeySymbol(
            hideMenuBarSymbols: hideMenuBarSymbols
        )
        let symbolWidth = StatusBarController.keySymbolWidth(
            forKeyCount: effectiveKeyCount,
            hideMenuBarSymbols: hideMenuBarSymbols
        )
        let symbolSpacing = StatusBarController.keySymbolTextSpacing(hideMenuBarSymbols: hideMenuBarSymbols)
        var viewIndex = 0
        for column in columns {
            let columnWidth = column.map {
                symbolWidth
                    + symbolSpacing
                    + ceil(StatusBarController.keyTextSize(for: $0.text, keyCount: effectiveKeyCount).width)
                    + StatusBarController.keyTextWidthSlack
            }.max() ?? 0
            for (rowIndex, row) in column.enumerated() {
                guard viewIndex < textViews.count, viewIndex < symbolViews.count else { continue }
                let rowHeight = ceil(StatusBarController.keyTextSize(for: row.text, keyCount: effectiveKeyCount).height)
                let totalRowsHeight = CGFloat(column.count) * rowHeight
                    + CGFloat(max(0, column.count - 1)) * StatusBarController.keyRowSpacing
                let topY = contentRect.minY + floor((contentRect.height - totalRowsHeight) / 2)
                    + CGFloat(column.count - 1 - rowIndex) * (rowHeight + StatusBarController.keyRowSpacing)
                    + StatusBarController.verticalTextOffsetY
                symbolViews[viewIndex].isHidden = shouldHideSymbols
                symbolViews[viewIndex].frame = shouldHideSymbols
                    ? .zero
                    : NSRect(
                        x: x,
                        y: topY + StatusBarController.keySymbolOffsetY(for: rowHeight, keyCount: effectiveKeyCount),
                        width: symbolWidth,
                        height: symbolWidth
                    )
                textViews[viewIndex].frame = bounds
                textViews[viewIndex].alignment = .left
                textViews[viewIndex].textRect = NSRect(
                    x: x + symbolWidth + symbolSpacing,
                    y: topY,
                    width: max(0, columnWidth - symbolWidth - symbolSpacing),
                    height: rowHeight + StatusBarController.keyTextHeightSlack
                )
                viewIndex += 1
            }
            x += columnWidth + StatusBarController.keyColumnSpacing
        }
    }

    func update(
        keyRows: [MenuBarKeyDisplayRow],
        statusCells: [ServiceStatusDisplayCell],
        statusCellsAreStale: Bool,
        showMenuBarDecimals: Bool,
        hideMenuBarSymbols: Bool
    ) {
        self.keyRows = keyRows
        self.statusCells = statusCells
        self.statusCellsAreStale = statusCellsAreStale
        self.showMenuBarDecimals = showMenuBarDecimals
        self.hideMenuBarSymbols = hideMenuBarSymbols
        reconcileKeyViews()
        for (index, indicatorView) in indicatorViews.enumerated() {
            if index < self.statusCells.count {
                let cell = self.statusCells[index]
                indicatorView.layer?.backgroundColor = cell.kind.statusBarColor.cgColor
                indicatorView.alphaValue = statusCellOpacity(for: cell.kind)
            } else {
                indicatorView.alphaValue = 0
            }
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: StatusBarController.statusItemLength(
                forKeyRows: keyRows,
                hideMenuBarSymbols: hideMenuBarSymbols
            ),
            height: intrinsicHeight()
        )
    }

    private func statusCellOpacity(for kind: ServiceStatusCellKind) -> CGFloat {
        let baseOpacity: CGFloat = kind == .gray ? 0.45 : 1
        return statusCellsAreStale ? baseOpacity * 0.55 : baseOpacity
    }

    private func intrinsicHeight() -> CGFloat {
        StatusBarController.statusItemHeight(
            forKeyRows: keyRows,
            showMenuBarDecimals: showMenuBarDecimals,
            hideMenuBarSymbols: hideMenuBarSymbols
        )
    }

    private var displayText: String {
        keyRows.map(\.text).joined(separator: " ")
    }

    private func reconcileKeyViews() {
        while textViews.count < keyRows.count {
            let textView = StatusBarTextView(font: font)
            textViews.append(textView)
            addSubview(textView)
            let imageView = NSImageView(frame: .zero)
            imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            imageView.contentTintColor = .white
            symbolViews.append(imageView)
            addSubview(imageView)
        }
        while textViews.count > keyRows.count {
            textViews.removeLast().removeFromSuperview()
            symbolViews.removeLast().removeFromSuperview()
        }
        let effectiveKeyCount = keyRows.count
        let effectiveFont = StatusBarController.keyTextFont(forKeyCount: effectiveKeyCount)
        let shouldHideSymbols = StatusBarController.shouldHideKeySymbol(
            hideMenuBarSymbols: hideMenuBarSymbols
        )
        let effectiveSymbolWidth = StatusBarController.keySymbolWidth(
            forKeyCount: effectiveKeyCount,
            hideMenuBarSymbols: hideMenuBarSymbols
        )
        for (index, row) in keyRows.enumerated() {
            textViews[index].font = effectiveFont
            textViews[index].text = row.text
            let symbolName = MenuBarTitleView.resolvedSymbolName(row.symbolName)
            symbolViews[index].isHidden = shouldHideSymbols
            symbolViews[index].symbolConfiguration = NSImage.SymbolConfiguration(
                pointSize: effectiveSymbolWidth,
                weight: .medium
            )
            symbolViews[index].image = NSImage(systemSymbolName: symbolName, accessibilityDescription: row.name)
        }
    }
}

private final class StatusBarTextView: NSView {
    var font: NSFont {
        didSet { needsDisplay = true }
    }
    var text = "" {
        didSet { needsDisplay = true }
    }
    var textRect = NSRect.zero {
        didSet { needsDisplay = true }
    }
    var alignment: NSTextAlignment = .center {
        didSet { needsDisplay = true }
    }

    init(font: NSFont) {
        self.font = font
        super.init(frame: .zero)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        paragraphStyle.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
        ]
        let measuredHeight = ceil((text as NSString).size(withAttributes: [.font: font]).height)
        let drawHeight = measuredHeight + StatusBarController.keyTextHeightSlack
        let drawRect = NSRect(
            x: textRect.minX,
            y: textRect.midY - (drawHeight / 2),
            width: textRect.width,
            height: drawHeight
        )
        (text as NSString).draw(
            with: drawRect,
            options: [.usesLineFragmentOrigin],
            attributes: attributes,
            context: nil
        )
    }
}

private extension ServiceStatusCellKind {
    var statusBarColor: NSColor {
        switch self {
        case .green:
            return .systemGreen
        case .yellow:
            return .systemOrange
        case .red:
            return .systemRed
        case .gray:
            return .secondaryLabelColor
        }
    }
}

extension StatusBarController {
    static func statusStripWidth(for layoutMode: ServiceStatusLayoutMode, showMenuBarDecimals: Bool) -> CGFloat {
        statusStripWidth(for: layoutMode, keyCount: 1, showMenuBarDecimals: showMenuBarDecimals)
    }

    static func statusStripWidth(
        for layoutMode: ServiceStatusLayoutMode,
        keyCount: Int,
        showMenuBarDecimals: Bool
    ) -> CGFloat {
        let columns = statusCellColumnCount(keyCount: keyCount)
        let width = (CGFloat(columns) * MenuBarTitleView.statusCellSize.width)
            + (CGFloat(max(0, columns - 1)) * MenuBarTitleView.statusCellSpacing)
        return width
    }

    static func statusStackHeight(
        for layoutMode: ServiceStatusLayoutMode,
        keyCount: Int,
        showMenuBarDecimals: Bool
    ) -> CGFloat {
        let rows = statusCellRowCount(keyCount: keyCount)
        let cellHeight = CGFloat(rows) * MenuBarTitleView.statusCellSize.height
        let spacingHeight = CGFloat(max(0, rows - 1)) * MenuBarTitleView.statusCellSpacing
        return cellHeight + spacingHeight
    }

    static func statusStackHeight(for layoutMode: ServiceStatusLayoutMode, showMenuBarDecimals: Bool) -> CGFloat {
        statusStackHeight(for: layoutMode, keyCount: 1, showMenuBarDecimals: showMenuBarDecimals)
    }

    static func statusCellColumnCount(keyCount: Int) -> Int {
        1
    }

    static func statusCellRowCount(keyCount: Int) -> Int {
        3
    }

    static func statusCellFrame(at index: Int, gridX: CGFloat, gridY: CGFloat, keyCount: Int) -> NSRect {
        let columns = statusCellColumnCount(keyCount: keyCount)
        let row = index / columns
        let column = index % columns
        return NSRect(
            x: gridX + CGFloat(column) * (MenuBarTitleView.statusCellSize.width + MenuBarTitleView.statusCellSpacing),
            y: gridY + CGFloat(statusCellRowCount(keyCount: keyCount) - 1 - row)
                * (MenuBarTitleView.statusCellSize.height + MenuBarTitleView.statusCellSpacing),
            width: MenuBarTitleView.statusCellSize.width,
            height: MenuBarTitleView.statusCellSize.height
        )
    }
}

extension ServiceStatusLayoutMode {
    func statusCellCount(showMenuBarDecimals: Bool) -> Int {
        3
    }

    func statusCellCount(keyCount: Int, showMenuBarDecimals: Bool) -> Int {
        3
    }
}
