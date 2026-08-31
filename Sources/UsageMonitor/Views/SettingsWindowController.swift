import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: ObservableObject {
    static let initialContentSize = NSSize(width: 520, height: 600)
    static let minimumContentSize = NSSize(width: 460, height: 480)

    private var window: NSWindow?
    private let backgroundUpdateCoordinator: BackgroundUpdateCoordinator
    private let barkNotificationManager: BarkNotificationManager
    private let activateApplication: () -> Void

    init(
        backgroundUpdateCoordinator: BackgroundUpdateCoordinator? = nil,
        barkNotificationManager: BarkNotificationManager? = nil,
        activateApplication: (() -> Void)? = nil
    ) {
        self.backgroundUpdateCoordinator = backgroundUpdateCoordinator ?? BackgroundUpdateCoordinator()
        self.barkNotificationManager = barkNotificationManager ?? BarkNotificationManager()
        self.activateApplication = activateApplication ?? {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func showWindow(
        monitor: UsageSnapshotMonitor,
        serviceStatusMonitor: ServiceStatusMonitor,
        cursorMonitor: CursorUsageMonitor
    ) {
        if let window {
            bringToFront(window)
            return
        }

        let newWindow = makeWindow(
            monitor: monitor,
            serviceStatusMonitor: serviceStatusMonitor,
            cursorMonitor: cursorMonitor
        )
        bringToFront(newWindow)
        window = newWindow
    }

    func makeWindow(
        monitor: UsageSnapshotMonitor,
        serviceStatusMonitor: ServiceStatusMonitor,
        cursorMonitor: CursorUsageMonitor
    ) -> NSWindow {
        let view = SettingsView(
            monitor: monitor,
            serviceStatusMonitor: serviceStatusMonitor,
            cursorMonitor: cursorMonitor,
            barkNotificationManager: barkNotificationManager,
            backgroundUpdateCoordinator: backgroundUpdateCoordinator
        )
        let hostingController = NSHostingController(rootView: view)
        let newWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialContentSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "用量监控"
        newWindow.contentViewController = hostingController
        newWindow.contentMinSize = Self.minimumContentSize
        newWindow.setContentSize(Self.initialContentSize)
        newWindow.isReleasedWhenClosed = false
        newWindow.initialFirstResponder = hostingController.view
        newWindow.center()
        return newWindow
    }

    func bringToFront(_ window: NSWindow) {
        activateApplication()
        window.makeKeyAndOrderFront(nil)
        if let responder = window.initialFirstResponder {
            window.makeFirstResponder(responder)
        }
        window.orderFrontRegardless()
    }
}
