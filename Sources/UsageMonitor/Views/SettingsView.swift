import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: SubscriptionMonitor
    @StateObject private var webLoginWindowController = WebLoginWindowController()
    @State private var baseURL: String
    @State private var email: String
    @State private var password: String
    @State private var validationStatus: String?

    init(monitor: SubscriptionMonitor) {
        self.monitor = monitor
        _baseURL = State(initialValue: monitor.baseURLText)
        _email = State(initialValue: monitor.email)
        _password = State(initialValue: monitor.password)
    }

    var body: some View {
        Form {
            Section("账号") {
                TextField("Base URL", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                TextField("邮箱", text: $email)
                    .textFieldStyle(.roundedBorder)
                SecureField("密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                Text("密码和 token 存储在 macOS Keychain 中。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("登录/验证") {
                    Task { await login() }
                }
                .disabled(monitor.isRefreshing)
                Button("网页登录") {
                    openWebLogin()
                }
                .disabled(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let validationStatus {
                    Text(validationStatus)
                        .font(.caption)
                        .foregroundColor(validationStatus == "验证成功" ? .green : .orange)
                }
            }

            Section("显示") {
                Picker("菜单栏套餐", selection: Binding(
                    get: { monitor.selectedSubscriptionID ?? "" },
                    set: { monitor.setSelectedSubscription($0) }
                )) {
                    ForEach(monitor.activeSubscriptions) { subscription in
                        Text("\(subscription.group.name) · \(subscription.group.platform)")
                            .tag(subscription.id)
                    }
                }
            }

            Section("刷新") {
                Picker("刷新间隔", selection: $monitor.refreshIntervalMinutes) {
                    ForEach(SubscriptionMonitor.allowedRefreshIntervals, id: \.self) { minutes in
                        Text("\(minutes) 分钟").tag(minutes)
                    }
                }
                Button("手动刷新") {
                    Task { await monitor.refreshNow() }
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .navigationTitle("用量监控")
    }

    private func login() async {
        monitor.updateBaseURL(baseURL)
        monitor.updateEmail(email)
        monitor.updatePassword(password)
        do {
            try await monitor.loginAndRefresh()
            validationStatus = "验证成功"
        } catch {
            validationStatus = monitor.lastError ?? "验证失败"
        }
    }

    private func openWebLogin() {
        monitor.updateBaseURL(baseURL)
        if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            monitor.updateEmail(email)
        }
        webLoginWindowController.showWindow(monitor: monitor)
    }
}
