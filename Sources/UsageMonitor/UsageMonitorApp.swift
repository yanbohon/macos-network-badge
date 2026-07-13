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
    private let backgroundUpdateCoordinator = BackgroundUpdateCoordinator()
    private lazy var settingsWindowController = SettingsWindowController(
        backgroundUpdateCoordinator: backgroundUpdateCoordinator
    )
    private var monitor: UsageSnapshotMonitor?
    private var serviceStatusMonitor: ServiceStatusMonitor?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UsageDefaultsMigration.migrateStandardDefaultsFromLegacyBundleIfNeeded()
        NSApp.setActivationPolicy(.accessory)
        let monitor = UsageSnapshotMonitor()
        let serviceStatusMonitor = ServiceStatusMonitor()
        self.monitor = monitor
        self.serviceStatusMonitor = serviceStatusMonitor
        statusBarController = StatusBarController(
            usageMonitor: monitor,
            serviceStatusMonitor: serviceStatusMonitor,
            settingsWindowController: settingsWindowController
        )
        backgroundUpdateCoordinator.start()
    }
}
