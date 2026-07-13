import XCTest
@testable import UsageMonitor

@MainActor
final class SettingsWindowConfigurationTests: XCTestCase {
    func testCreatedWindowUsesSettingsLayoutSize() {
        let controller = SettingsWindowController(activateApplication: {})
        let monitor = UsageSnapshotMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        let serviceStatusMonitor = ServiceStatusMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            timerFactory: ManualTimerFactory()
        )

        let window = controller.makeWindow(
            monitor: monitor,
            serviceStatusMonitor: serviceStatusMonitor
        )

        XCTAssertEqual(window.title, "用量监控")
        XCTAssertEqual(window.contentView?.frame.size, SettingsWindowController.initialContentSize)
        XCTAssertEqual(window.contentMinSize, SettingsWindowController.minimumContentSize)
    }

    func testCreatedWindowUsesHostingViewAsInitialFirstResponder() {
        let controller = SettingsWindowController(activateApplication: {})
        let monitor = UsageSnapshotMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        let serviceStatusMonitor = ServiceStatusMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            timerFactory: ManualTimerFactory()
        )

        let window = controller.makeWindow(
            monitor: monitor,
            serviceStatusMonitor: serviceStatusMonitor
        )

        XCTAssertTrue(window.initialFirstResponder === window.contentViewController?.view)
    }
}
