import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    static let horizontalPadding: CGFloat = 6
    static let contentSpacing: CGFloat = 4
    static let statusIndicatorSize = NSSize(width: 8, height: 8)
    private static let titleFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)

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

    static func titleText(usageText: String, statusCells: [ServiceStatusDisplayCell]) -> String {
        MenuBarTitleView.combinedText(text: usageText, statusCells: statusCells)
    }

    static func statusItemLength(for usageText: String) -> CGFloat {
        let textWidth = ceil((usageText as NSString).size(withAttributes: [
            .font: titleFont,
        ]).width)
        return ceil(horizontalPadding + statusIndicatorSize.width + contentSpacing + textWidth + horizontalPadding)
    }

    static func attributedTitle(
        usageText: String,
        statusCells: [ServiceStatusDisplayCell]
    ) -> NSAttributedString {
        let statusText = MenuBarTitleView.statusSymbolText(for: statusCells)
        let title = NSMutableAttributedString(
            string: MenuBarTitleView.combinedText(text: usageText, statusCells: statusCells)
        )
        let fullRange = NSRange(location: 0, length: title.length)
        title.addAttributes(
            [
                .font: titleFont,
                .foregroundColor: NSColor.white,
            ],
            range: fullRange
        )
        if !statusText.isEmpty {
            title.addAttribute(
                .foregroundColor,
                value: MenuBarTitleView.latestStatusKind(for: statusCells).statusBarColor,
                range: NSRange(location: 0, length: (statusText as NSString).length)
            )
        }
        return title
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
        let usageText = usageMonitor.menuBarText
        let statusCells = serviceStatusMonitor.displayCells
        let statusKind = MenuBarTitleView.latestStatusKind(for: statusCells)

        statusItem.length = Self.statusItemLength(for: usageText)
        badgeView.update(usageText: usageText, statusKind: statusKind)
        statusItem.button?.setAccessibilityTitle(Self.titleText(usageText: usageText, statusCells: statusCells))
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
    private let indicatorView = NSView(frame: .zero)
    private let textField = NSTextField(labelWithString: "")
    private var usageText = ""

    init(font: NSFont) {
        super.init(frame: .zero)
        indicatorView.wantsLayer = true
        textField.font = font
        textField.textColor = .white
        textField.lineBreakMode = .byClipping
        textField.alignment = .left
        addSubview(indicatorView)
        addSubview(textField)
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
        let labelSize = textField.intrinsicContentSize
        let indicatorY = floor((bounds.height - StatusBarController.statusIndicatorSize.height) / 2)
        let labelY = floor((bounds.height - labelSize.height) / 2)
        let indicatorX = StatusBarController.horizontalPadding
        let labelX = indicatorX + StatusBarController.statusIndicatorSize.width + StatusBarController.contentSpacing
        let availableLabelWidth = max(0, bounds.width - labelX - StatusBarController.horizontalPadding)

        indicatorView.frame = NSRect(
            x: indicatorX,
            y: indicatorY,
            width: StatusBarController.statusIndicatorSize.width,
            height: StatusBarController.statusIndicatorSize.height
        )
        indicatorView.layer?.cornerRadius = 1.5
        textField.frame = NSRect(
            x: labelX,
            y: labelY,
            width: min(ceil(labelSize.width), availableLabelWidth),
            height: ceil(labelSize.height)
        )
    }

    func update(usageText: String, statusKind: ServiceStatusCellKind) {
        self.usageText = usageText
        textField.stringValue = usageText
        indicatorView.layer?.backgroundColor = statusKind.statusBarColor.cgColor
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: StatusBarController.statusItemLength(for: usageText),
            height: max(textField.intrinsicContentSize.height, StatusBarController.statusIndicatorSize.height)
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
