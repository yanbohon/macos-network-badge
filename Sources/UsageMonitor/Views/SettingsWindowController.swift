import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: ObservableObject {
    static let initialContentSize = NSSize(width: 500, height: 560)
    static let minimumContentSize = NSSize(width: 420, height: 400)

    private var window: NSWindow?
    private let backgroundUpdateCoordinator: BackgroundUpdateCoordinator
    private let activateApplication: () -> Void

    init(
        backgroundUpdateCoordinator: BackgroundUpdateCoordinator? = nil,
        activateApplication: (() -> Void)? = nil
    ) {
        self.backgroundUpdateCoordinator = backgroundUpdateCoordinator ?? BackgroundUpdateCoordinator()
        self.activateApplication = activateApplication ?? {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func showWindow(
        monitor: UsageSnapshotMonitor,
        serviceStatusMonitor: ServiceStatusMonitor
    ) {
        if let window {
            bringToFront(window)
            return
        }

        let newWindow = makeWindow(
            monitor: monitor,
            serviceStatusMonitor: serviceStatusMonitor
        )
        bringToFront(newWindow)
        window = newWindow
    }

    func makeWindow(
        monitor: UsageSnapshotMonitor,
        serviceStatusMonitor: ServiceStatusMonitor
    ) -> NSWindow {
        let view = SettingsView(
            monitor: monitor,
            serviceStatusMonitor: serviceStatusMonitor,
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
