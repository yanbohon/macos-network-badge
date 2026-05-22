import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    static let horizontalPadding: CGFloat = 1
    static let verticalPadding: CGFloat = 1
    static let textWidthSlack: CGFloat = 3
    static let horizontalTextHeightSlack: CGFloat = 2
    static let horizontalContentOffsetY: CGFloat = -1
    static let verticalStatusOffsetY: CGFloat = 0
    static let verticalTextOffsetY: CGFloat = -1
    static let statusTextSpacing: CGFloat = 5
    static let keyColumnSpacing: CGFloat = 7
    static let keyRowSpacing: CGFloat = 1
    static let keySymbolTextSpacing: CGFloat = 2
    static let keySymbolWidth: CGFloat = 11
    static let maximumStatusCellCount = 2
    private static let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    private let usageMonitor: UsageSnapshotMonitor
    private let serviceStatusMonitor: ServiceStatusMonitor
    private let settingsWindowController: SettingsWindowController
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let badgeView = StatusBarBadgeView(font: StatusBarController.titleFont)
    private var cancellables: Set<AnyCancellable> = []

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

    static func statusItemLength(forKeyRows keyRows: [MenuBarKeyDisplayRow]) -> CGFloat {
        let columns = MenuBarTitleView.keyGridColumns(for: keyRows)
        let columnWidths = columns.map { column in
            column.map { row in
                keySymbolWidth + keySymbolTextSpacing + ceil(textSize(for: row.text).width) + textWidthSlack
            }.max() ?? 0
        }
        let keysWidth = columnWidths.reduce(0, +)
            + CGFloat(max(0, columns.count - 1)) * keyColumnSpacing
        return ceil(
            horizontalPadding
            + statusStripWidth(for: .verticalTwo, showMenuBarDecimals: true)
            + statusTextSpacing
            + keysWidth
            + horizontalPadding
        )
    }

    static func horizontalTextOffsetX(for displayText: String, layoutMode: ServiceStatusLayoutMode) -> CGFloat {
        0
    }

    static func textSize(for displayText: String) -> NSSize {
        (displayText as NSString).size(withAttributes: [.font: titleFont])
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
        contentRect.minY + floor((contentRect.height - stackHeight) / 2) + verticalStatusOffsetY
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
        let statusCells = MenuBarTitleView.normalizedStatusCells(
            for: serviceStatusMonitor.displayCells,
            count: ServiceStatusLayoutMode.verticalTwo.statusCellCount(showMenuBarDecimals: true)
        )

        statusItem.length = Self.statusItemLength(forKeyRows: keyRows)
        badgeView.update(
            keyRows: keyRows,
            statusCells: statusCells,
            statusCellsAreStale: serviceStatusMonitor.isStaleAfterFailure,
            showMenuBarDecimals: usageMonitor.showMenuBarDecimals
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
        let labelSize = StatusBarController.textSize(for: displayText)
        _ = labelSize
        let stackHeight = StatusBarController.statusStackHeight(for: .verticalTwo, showMenuBarDecimals: showMenuBarDecimals)
        let gridY = StatusBarController.verticalGridY(in: contentRect, stackHeight: stackHeight)
        let gridX = contentRect.minX

        for (index, indicatorView) in indicatorViews.enumerated() {
            if index < statusCells.count {
                let originY = gridY + CGFloat(statusCells.count - 1 - index)
                    * (MenuBarTitleView.statusCellSize.height + MenuBarTitleView.statusCellSpacing)
                indicatorView.frame = NSRect(
                    x: gridX,
                    y: originY,
                    width: MenuBarTitleView.statusCellSize.width,
                    height: MenuBarTitleView.statusCellSize.height
                )
            } else {
                indicatorView.frame = .zero
            }
            indicatorView.layer?.cornerRadius = 1
        }

        let columns = MenuBarTitleView.keyGridColumns(for: keyRows)
        var x = gridX + StatusBarController.statusStripWidth(for: .verticalTwo, showMenuBarDecimals: showMenuBarDecimals)
            + StatusBarController.statusTextSpacing
        var viewIndex = 0
        for column in columns {
            let columnWidth = column.map {
                StatusBarController.keySymbolWidth
                    + StatusBarController.keySymbolTextSpacing
                    + ceil(StatusBarController.textSize(for: $0.text).width)
                    + StatusBarController.textWidthSlack
            }.max() ?? 0
            for (rowIndex, row) in column.enumerated() {
                guard viewIndex < textViews.count, viewIndex < symbolViews.count else { continue }
                let rowHeight = ceil(StatusBarController.textSize(for: row.text).height)
                let totalRowsHeight = CGFloat(column.count) * rowHeight
                    + CGFloat(max(0, column.count - 1)) * StatusBarController.keyRowSpacing
                let topY = contentRect.minY + floor((contentRect.height - totalRowsHeight) / 2)
                    + CGFloat(column.count - 1 - rowIndex) * (rowHeight + StatusBarController.keyRowSpacing)
                    + StatusBarController.verticalTextOffsetY
                symbolViews[viewIndex].frame = NSRect(
                    x: x,
                    y: topY + 2,
                    width: StatusBarController.keySymbolWidth,
                    height: StatusBarController.keySymbolWidth
                )
                textViews[viewIndex].frame = bounds
                textViews[viewIndex].alignment = .left
                textViews[viewIndex].textRect = NSRect(
                    x: x + StatusBarController.keySymbolWidth + StatusBarController.keySymbolTextSpacing,
                    y: topY,
                    width: max(0, columnWidth - StatusBarController.keySymbolWidth - StatusBarController.keySymbolTextSpacing),
                    height: rowHeight + StatusBarController.horizontalTextHeightSlack
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
        showMenuBarDecimals: Bool
    ) {
        self.keyRows = keyRows
        self.statusCells = statusCells
        self.statusCellsAreStale = statusCellsAreStale
        self.showMenuBarDecimals = showMenuBarDecimals
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
            width: StatusBarController.statusItemLength(forKeyRows: keyRows),
            height: intrinsicHeight()
        )
    }

    private func statusCellOpacity(for kind: ServiceStatusCellKind) -> CGFloat {
        let baseOpacity: CGFloat = kind == .gray ? 0.45 : 1
        return statusCellsAreStale ? baseOpacity * 0.55 : baseOpacity
    }

    private func intrinsicHeight() -> CGFloat {
        let rowHeight = keyRows.map { StatusBarController.textSize(for: $0.text).height }.max() ?? 0
        return max(
            (rowHeight * 2) + StatusBarController.keyRowSpacing,
            StatusBarController.statusStackHeight(
                for: .verticalTwo,
                showMenuBarDecimals: showMenuBarDecimals
            )
        )
            + (StatusBarController.verticalPadding * 2)
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
        for (index, row) in keyRows.enumerated() {
            textViews[index].text = row.text
            let symbolName = MenuBarTitleView.resolvedSymbolName(row.symbolName)
            symbolViews[index].image = NSImage(systemSymbolName: symbolName, accessibilityDescription: row.name)
        }
    }
}

private final class StatusBarTextView: NSView {
    let font: NSFont
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
        let measuredHeight = ceil(StatusBarController.textSize(for: text).height)
        let drawHeight = measuredHeight + StatusBarController.horizontalTextHeightSlack
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

private extension StatusBarController {
    static func statusStripWidth(for layoutMode: ServiceStatusLayoutMode, showMenuBarDecimals: Bool) -> CGFloat {
        return ceil(MenuBarTitleView.statusCellSize.width)
    }

    static func statusStackHeight(for layoutMode: ServiceStatusLayoutMode, showMenuBarDecimals: Bool) -> CGFloat {
        let count = layoutMode.statusCellCount(showMenuBarDecimals: showMenuBarDecimals)
        let cellHeight = CGFloat(count) * MenuBarTitleView.statusCellSize.height
        let spacingHeight = CGFloat(count - 1) * MenuBarTitleView.statusCellSpacing
        return ceil(cellHeight + spacingHeight)
    }
}

extension ServiceStatusLayoutMode {
    func statusCellCount(showMenuBarDecimals: Bool) -> Int {
        2
    }
}
