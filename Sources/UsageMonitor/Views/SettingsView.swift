import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: UsageSnapshotMonitor
    @State private var draft: SettingsDraft
    @State private var validationStatus: String?

    init(monitor: UsageSnapshotMonitor) {
        self.monitor = monitor
        _draft = State(initialValue: SettingsDraft(baseURL: monitor.baseURLText, apiKey: monitor.apiKey))
    }

    var body: some View {
        Form {
            Section("连接") {
                NativeTextInput(
                    placeholder: "Base URL",
                    text: $draft.baseURL,
                    autoFocus: true
                )
                NativeTextInput(
                    placeholder: "API Key",
                    text: $draft.apiKey,
                    secure: true
                )
                Text("API Key 保存在本机应用偏好设置中。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("验证并刷新") {
                    Task { await validateAndRefresh() }
                }
                .disabled(monitor.isRefreshing)
                if let validationStatus {
                    Text(validationStatus)
                        .font(.caption)
                        .foregroundColor(validationStatus == "验证成功" ? .green : .orange)
                }
            }

            Section("显示") {
                Toggle("菜单栏显示小数点", isOn: $monitor.showMenuBarDecimals)
            }

            Section("刷新") {
                Picker("刷新间隔", selection: $monitor.refreshIntervalMinutes) {
                    ForEach(UsageSnapshotMonitor.allowedRefreshIntervals, id: \.self) { minutes in
                        Text("\(minutes) 分钟").tag(minutes)
                    }
                }
                Button("手动刷新") {
                    commitDraft()
                    Task { await monitor.refreshNow() }
                }
                .disabled(monitor.isRefreshing)
            }
        }
        .padding(20)
        .frame(width: 420)
        .navigationTitle("用量监控")
        .onDisappear {
            commitDraft()
        }
    }

    private func validateAndRefresh() async {
        commitDraft()
        do {
            try await monitor.validateAndRefresh()
            validationStatus = "验证成功"
        } catch {
            validationStatus = monitor.lastError ?? "验证失败"
        }
    }

    private func commitDraft() {
        draft.commit(to: monitor)
    }
}
