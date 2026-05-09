import AppKit
import SwiftUI

final class SettingsWindowController: ObservableObject {
    private var window: NSWindow?

    func showWindow(monitor: SubscriptionMonitor) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView(monitor: monitor)
        let hostingController = NSHostingController(rootView: view)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "用量监控"
        newWindow.contentViewController = hostingController
        newWindow.contentMinSize = NSSize(width: 420, height: 360)
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow
    }
}
