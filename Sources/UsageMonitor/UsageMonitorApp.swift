import SwiftUI

@main
struct UsageMonitorApp: App {
    @StateObject private var monitor = UsageSnapshotMonitor()
    @StateObject private var settingsWindowController = SettingsWindowController()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                monitor: monitor,
                settingsWindowController: settingsWindowController
            )
        } label: {
            MenuBarTitleView(
                text: monitor.menuBarText,
                color: monitor.healthState.swiftUIColor
            )
                .onAppear {
                    monitor.start()
                }
        }
        .menuBarExtraStyle(.window)
        .commands {
            TextEditingCommands()
        }
    }
}

private struct MenuBarTitleView: View {
    let text: String
    let color: Color

    private var lines: [String] {
        text.components(separatedBy: "\n")
    }

    var body: some View {
        Group {
            if lines.count == 2 {
                VStack(alignment: .center, spacing: -2) {
                    Text(lines[0])
                    Text(lines[1])
                }
                .font(.system(size: 9, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
            } else {
                Text(text)
            }
        }
        .monospacedDigit()
        .foregroundColor(color)
    }
}
