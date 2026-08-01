import AppKit

@main
enum UsageMonitorApp {
    static let launchWindowCheckArgument = "--launch-window-check"

    static func backgroundActivitiesEnabled(arguments: [String]) -> Bool {
        !arguments.contains(launchWindowCheckArgument)
    }

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate(
            startsBackgroundActivities: backgroundActivitiesEnabled(
                arguments: ProcessInfo.processInfo.arguments
            )
        )
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let startsBackgroundActivities: Bool
    private let backgroundUpdateCoordinator = BackgroundUpdateCoordinator()
    private lazy var barkNotificationManager = BarkNotificationManager()
    private lazy var settingsWindowController = SettingsWindowController(
        backgroundUpdateCoordinator: backgroundUpdateCoordinator,
        barkNotificationManager: barkNotificationManager
    )
    private var monitor: UsageSnapshotMonitor?
    private var serviceStatusMonitor: ServiceStatusMonitor?
    private var statusBarController: StatusBarController?

    init(startsBackgroundActivities: Bool = true) {
        self.startsBackgroundActivities = startsBackgroundActivities
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UsageDefaultsMigration.migrateStandardDefaultsFromLegacyBundleIfNeeded()
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = StandardEditMenu.makeMainMenu()
        let monitor = UsageSnapshotMonitor()
        let serviceStatusMonitor = ServiceStatusMonitor(
            notificationSink: barkNotificationManager
        )
        self.monitor = monitor
        self.serviceStatusMonitor = serviceStatusMonitor
        statusBarController = StatusBarController(
            usageMonitor: monitor,
            serviceStatusMonitor: serviceStatusMonitor,
            settingsWindowController: settingsWindowController,
            startsMonitors: startsBackgroundActivities
        )
        if startsBackgroundActivities {
            backgroundUpdateCoordinator.start()
        }
    }
}
