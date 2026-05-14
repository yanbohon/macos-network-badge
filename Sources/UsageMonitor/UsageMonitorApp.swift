import SwiftUI

@main
struct UsageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            TextEditingCommands()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = UsageSnapshotMonitor()
    private let serviceStatusMonitor = ServiceStatusMonitor()
    private let settingsWindowController = SettingsWindowController()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(
            usageMonitor: monitor,
            serviceStatusMonitor: serviceStatusMonitor,
            settingsWindowController: settingsWindowController
        )
    }
}
