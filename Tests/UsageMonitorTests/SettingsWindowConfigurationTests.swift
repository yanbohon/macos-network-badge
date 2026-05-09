import XCTest
@testable import UsageMonitor

@MainActor
final class SettingsWindowConfigurationTests: XCTestCase {
    func testCreatedWindowUsesHostingViewAsInitialFirstResponder() {
        let controller = SettingsWindowController(activateApplication: {})
        let monitor = UsageSnapshotMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )

        let window = controller.makeWindow(monitor: monitor)

        XCTAssertTrue(window.initialFirstResponder === window.contentViewController?.view)
    }
}
