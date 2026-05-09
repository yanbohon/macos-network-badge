import SwiftUI

@main
struct UsageMonitorApp: App {
    @StateObject private var monitor = SubscriptionMonitor()
    @StateObject private var settingsWindowController = SettingsWindowController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                monitor: monitor,
                settingsWindowController: settingsWindowController
            )
        } label: {
            Text(monitor.menuBarText)
                .monospacedDigit()
                .foregroundColor(monitor.selectedHealthState.swiftUIColor)
                .onAppear {
                    monitor.start()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
