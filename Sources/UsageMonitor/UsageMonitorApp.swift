import AppKit

@main
enum UsageMonitorApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
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
        NSApp.mainMenu = StandardEditMenu.makeMainMenu()
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
