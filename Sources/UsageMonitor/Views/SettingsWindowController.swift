import AppKit
import SwiftUI

final class SettingsWindowController: ObservableObject {
    private var window: NSWindow?
    private let activateApplication: () -> Void

    init(activateApplication: @escaping () -> Void = {
        NSApp.activate(ignoringOtherApps: true)
    }) {
        self.activateApplication = activateApplication
    }

    func showWindow(monitor: UsageSnapshotMonitor) {
        if let window {
            bringToFront(window)
            return
        }

        let newWindow = makeWindow(monitor: monitor)
        bringToFront(newWindow)
        window = newWindow
    }

    func makeWindow(monitor: UsageSnapshotMonitor) -> NSWindow {
        let view = SettingsView(monitor: monitor)
        let hostingController = NSHostingController(rootView: view)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "用量监控"
        newWindow.contentViewController = hostingController
        newWindow.contentMinSize = NSSize(width: 420, height: 320)
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
