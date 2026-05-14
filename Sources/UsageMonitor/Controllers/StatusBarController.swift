import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    static let horizontalPadding: CGFloat = 1
    static let verticalPadding: CGFloat = 1
    static let textWidthSlack: CGFloat = 3
    static let horizontalTextHeightSlack: CGFloat = 2
    static let statusTextSpacing: CGFloat = 5
    static let maximumStatusCellCount = 6
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

    static func statusItemLength(
        for displayText: String,
        layoutMode: ServiceStatusLayoutMode,
        showMenuBarDecimals: Bool
    ) -> CGFloat {
        let textWidth = ceil(textSize(for: displayText).width) + textWidthSlack
        switch layoutMode {
        case .horizontalFive:
            return ceil(
                horizontalPadding
                + max(textWidth, statusStripWidth(for: layoutMode, showMenuBarDecimals: showMenuBarDecimals))
                + horizontalPadding
            )
        case .verticalTwo:
            return ceil(
                horizontalPadding
                + statusStripWidth(for: layoutMode, showMenuBarDecimals: showMenuBarDecimals)
                + statusTextSpacing
                + textWidth
                + horizontalPadding
            )
        }
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
            y: contentRect.minY + floor((bottomSectionHeight - textHeight) / 2),
            width: contentRect.width,
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
        let displayText = usageMonitor.menuBarText
        let layoutMode = usageMonitor.serviceStatusLayoutMode
        let showMenuBarDecimals = usageMonitor.showMenuBarDecimals
        let statusCells = MenuBarTitleView.normalizedStatusCells(
            for: serviceStatusMonitor.displayCells,
            count: layoutMode.statusCellCount(showMenuBarDecimals: showMenuBarDecimals)
        )

        statusItem.length = Self.statusItemLength(
            for: displayText,
            layoutMode: layoutMode,
            showMenuBarDecimals: showMenuBarDecimals
        )
        badgeView.update(
            displayText: displayText,
            statusCells: statusCells,
            statusCellsAreStale: serviceStatusMonitor.isStaleAfterFailure,
            layoutMode: layoutMode,
            showMenuBarDecimals: showMenuBarDecimals
        )
        statusItem.button?.setAccessibilityTitle(
            Self.titleText(
                displayText: displayText,
                statusCells: statusCells,
                layoutMode: layoutMode,
                showMenuBarDecimals: showMenuBarDecimals
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
    private let textView: StatusBarTextView
    private var displayText = ""
    private var statusCells: [ServiceStatusDisplayCell] = []
    private var statusCellsAreStale = false
    private var layoutMode: ServiceStatusLayoutMode = .horizontalFive
    private var showMenuBarDecimals = true

    init(font: NSFont) {
        textView = StatusBarTextView(font: font)
        super.init(frame: .zero)
        indicatorViews.forEach { indicatorView in
            indicatorView.wantsLayer = true
            addSubview(indicatorView)
        }
        addSubview(textView)
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
        textView.frame = bounds
        switch layoutMode {
        case .horizontalFive:
            let topSectionHeight = max(4, floor(contentRect.height * MenuBarTitleView.topSectionRatio))
            let bottomSectionHeight = max(0, contentRect.height - topSectionHeight)
            let gridY = contentRect.maxY - topSectionHeight
                + floor((topSectionHeight - MenuBarTitleView.statusCellSize.height) / 2)
            let gridX = contentRect.minX
                + floor(
                    (
                        contentRect.width
                        - StatusBarController.statusStripWidth(for: layoutMode, showMenuBarDecimals: showMenuBarDecimals)
                    ) / 2
                )

            for (index, indicatorView) in indicatorViews.enumerated() {
                if index < statusCells.count {
                    let originX = gridX + CGFloat(index) * (MenuBarTitleView.statusCellSize.width + MenuBarTitleView.statusCellSpacing)
                    indicatorView.frame = NSRect(
                        x: originX,
                        y: gridY,
                        width: MenuBarTitleView.statusCellSize.width,
                        height: MenuBarTitleView.statusCellSize.height
                    )
                } else {
                    indicatorView.frame = .zero
                }
                indicatorView.layer?.cornerRadius = 1
            }

            textView.alignment = .center
            textView.textRect = StatusBarController.horizontalTextFrame(
                in: contentRect,
                bottomSectionHeight: bottomSectionHeight,
                labelSize: labelSize,
                displayText: displayText,
                layoutMode: layoutMode
            )
        case .verticalTwo:
            let stackHeight = StatusBarController.statusStackHeight(for: layoutMode, showMenuBarDecimals: showMenuBarDecimals)
            let gridY = contentRect.minY + floor((contentRect.height - stackHeight) / 2)
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

            textView.alignment = .left
            textView.textRect = NSRect(
                x: gridX
                    + StatusBarController.statusStripWidth(for: layoutMode, showMenuBarDecimals: showMenuBarDecimals)
                    + StatusBarController.statusTextSpacing,
                y: contentRect.minY
                    + floor((contentRect.height - ceil(labelSize.height) - StatusBarController.horizontalTextHeightSlack) / 2),
                width: max(
                    0,
                    contentRect.width
                        - StatusBarController.statusStripWidth(for: layoutMode, showMenuBarDecimals: showMenuBarDecimals)
                        - StatusBarController.statusTextSpacing
                ),
                height: ceil(labelSize.height) + StatusBarController.horizontalTextHeightSlack
            )
        }
    }

    func update(
        displayText: String,
        statusCells: [ServiceStatusDisplayCell],
        statusCellsAreStale: Bool,
        layoutMode: ServiceStatusLayoutMode,
        showMenuBarDecimals: Bool
    ) {
        self.displayText = displayText
        self.statusCells = statusCells
        self.statusCellsAreStale = statusCellsAreStale
        self.layoutMode = layoutMode
        self.showMenuBarDecimals = showMenuBarDecimals
        textView.text = displayText
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
                for: displayText,
                layoutMode: layoutMode,
                showMenuBarDecimals: showMenuBarDecimals
            ),
            height: intrinsicHeight(for: layoutMode)
        )
    }

    private func statusCellOpacity(for kind: ServiceStatusCellKind) -> CGFloat {
        let baseOpacity: CGFloat = kind == .gray ? 0.45 : 1
        return statusCellsAreStale ? baseOpacity * 0.55 : baseOpacity
    }

    private func intrinsicHeight(for layoutMode: ServiceStatusLayoutMode) -> CGFloat {
        switch layoutMode {
        case .horizontalFive:
            return StatusBarController.textSize(for: displayText).height
                + MenuBarTitleView.statusCellSize.height
                + (StatusBarController.verticalPadding * 2)
                + StatusBarController.horizontalTextHeightSlack
                + 1
        case .verticalTwo:
            return max(
                StatusBarController.textSize(for: displayText).height,
                StatusBarController.statusStackHeight(
                    for: layoutMode,
                    showMenuBarDecimals: showMenuBarDecimals
                )
            )
                + (StatusBarController.verticalPadding * 2)
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
        switch layoutMode {
        case .horizontalFive:
            let count = layoutMode.statusCellCount(showMenuBarDecimals: showMenuBarDecimals)
            let cellWidth = CGFloat(count) * MenuBarTitleView.statusCellSize.width
            let spacingWidth = CGFloat(count - 1) * MenuBarTitleView.statusCellSpacing
            return ceil(cellWidth + spacingWidth)
        case .verticalTwo:
            return ceil(MenuBarTitleView.statusCellSize.width)
        }
    }

    static func statusStackHeight(for layoutMode: ServiceStatusLayoutMode, showMenuBarDecimals: Bool) -> CGFloat {
        switch layoutMode {
        case .horizontalFive:
            return ceil(MenuBarTitleView.statusCellSize.height)
        case .verticalTwo:
            let count = layoutMode.statusCellCount(showMenuBarDecimals: showMenuBarDecimals)
            let cellHeight = CGFloat(count) * MenuBarTitleView.statusCellSize.height
            let spacingHeight = CGFloat(count - 1) * MenuBarTitleView.statusCellSpacing
            return ceil(cellHeight + spacingHeight)
        }
    }
}

extension ServiceStatusLayoutMode {
    func statusCellCount(showMenuBarDecimals: Bool) -> Int {
        switch self {
        case .horizontalFive:
            return showMenuBarDecimals ? 6 : 4
        case .verticalTwo:
            return 2
        }
    }
}
