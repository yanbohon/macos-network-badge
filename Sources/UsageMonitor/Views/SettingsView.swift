import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: UsageSnapshotMonitor
    private let updateDefaults: UserDefaults
    private let updateChecker: UpdateChecker
    @State private var draft: SettingsDraft
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var includeBetaUpdates: Bool
    @State private var updateCheckResult: UpdateCheckResult?
    @State private var isCheckingForUpdate = false
    @State private var updateCheckGeneration = 0

    init(
        monitor: UsageSnapshotMonitor,
        updateDefaults: UserDefaults = .standard,
        updateChecker: UpdateChecker = UpdateChecker()
    ) {
        self.monitor = monitor
        self.updateDefaults = updateDefaults
        self.updateChecker = updateChecker
        _draft = State(initialValue: SettingsDraft(baseURL: monitor.baseURLText, apiKey: monitor.apiKey))
        let savedIncludeBetaUpdates = updateDefaults.object(forKey: UpdateDefaultsKey.includeBetaUpdates) as? Bool ?? false
        _includeBetaUpdates = State(initialValue: savedIncludeBetaUpdates)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                connectionSection
                displaySection
                refreshSection
                aboutSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            syncDraftFromMonitor()
        }
        .onDisappear {
            commitDraft()
        }
        .onChange(of: draft.baseURL) { _ in
            clearConnectionStatus()
        }
        .onChange(of: draft.apiKey) { _ in
            clearConnectionStatus()
        }
        .onChange(of: includeBetaUpdates) { newValue in
            updateDefaults.set(newValue, forKey: UpdateDefaultsKey.includeBetaUpdates)
            updateCheckGeneration += 1
            updateCheckResult = nil
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("用量监控")
                .font(.title3.weight(.semibold))
            Text("Base URL 和 API Key 保存在本机，验证后立即刷新。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("连接")

            labeledInput(
                title: "Base URL",
                placeholder: "https://example.com",
                text: $draft.baseURL,
                secure: false,
                autoFocus: true
            )

            labeledInput(
                title: "API Key",
                placeholder: "输入 API Key",
                text: $draft.apiKey,
                secure: true,
                helper: "API Key 仅保存在本机应用偏好设置中。"
            )

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    Task { await validateAndRefresh() }
                } label: {
                    Text(primaryButtonTitle)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)

                if let statusText = connectionStatus.message {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(connectionStatus.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("显示")

            Toggle("菜单栏显示小数点", isOn: $monitor.showMenuBarDecimals)
        }
    }

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("刷新")

            HStack(alignment: .firstTextBaseline) {
                Text("刷新间隔")
                Spacer(minLength: 12)
                Picker("刷新间隔", selection: $monitor.refreshIntervalMinutes) {
                    ForEach(UsageSnapshotMonitor.allowedRefreshIntervals, id: \.self) { minutes in
                        Text("\(minutes) 分钟").tag(minutes)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Button {
                commitDraft()
                Task { await monitor.refreshNow() }
            } label: {
                Text(manualRefreshButtonTitle)
            }
            .buttonStyle(.bordered)
            .disabled(monitor.isRefreshing)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("关于")

            LabeledContent("版本") {
                Text(Self.versionText)
                    .foregroundStyle(.secondary)
            }

            Toggle("包含测试版更新", isOn: $includeBetaUpdates)

            Button {
                startUpdateCheck()
            } label: {
                Label(updateCheckButtonTitle, systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isCheckingForUpdate)

            if let statusText = updateStatusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(updateStatusColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let downloadURL = updateCheckResult?.downloadURL {
                Button {
                    NSWorkspace.shared.open(downloadURL)
                } label: {
                    Label("下载更新", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var primaryButtonTitle: String {
        isBusy ? "验证中…" : "验证并刷新"
    }

    private var manualRefreshButtonTitle: String {
        monitor.isRefreshing ? "刷新中…" : "手动刷新"
    }

    private var isBusy: Bool {
        connectionStatus.isValidating || monitor.isRefreshing
    }

    private var updateCheckButtonTitle: String {
        isCheckingForUpdate ? "检查中..." : "检查更新"
    }

    private var updateStatusText: String? {
        if isCheckingForUpdate {
            return "检查中..."
        }
        return updateCheckResult?.statusText
    }

    private var updateStatusColor: Color {
        if isCheckingForUpdate {
            return .secondary
        }

        guard let updateCheckResult else {
            return .secondary
        }

        switch updateCheckResult {
        case .upToDate:
            return .secondary
        case .updateAvailable:
            return .green
        case .failure:
            return .red
        }
    }

    private func labeledInput(
        title: String,
        placeholder: String,
        text: Binding<String>,
        secure: Bool,
        autoFocus: Bool = false,
        helper: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout.weight(.semibold))

            NativeTextInput(
                placeholder: placeholder,
                text: text,
                secure: secure,
                autoFocus: autoFocus
            )
            .frame(maxWidth: .infinity)

            if let helper {
                Text(helper)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private func validateAndRefresh() async {
        commitDraft()
        connectionStatus = .validating

        do {
            try await monitor.validateAndRefresh()
            connectionStatus = .success("验证成功")
        } catch {
            connectionStatus = .failure(monitor.lastError ?? "验证失败")
        }
    }

    private func commitDraft() {
        draft.commit(to: monitor)
    }

    private func syncDraftFromMonitor() {
        draft = SettingsDraft(baseURL: monitor.baseURLText, apiKey: monitor.apiKey)
        connectionStatus = .idle
    }

    private func startUpdateCheck() {
        updateCheckGeneration += 1
        let requestGeneration = updateCheckGeneration
        let includePrereleases = includeBetaUpdates
        updateCheckResult = nil
        isCheckingForUpdate = true

        Task {
            let result = await updateChecker.checkForUpdate(includePrereleases: includePrereleases)
            await MainActor.run {
                guard requestGeneration == updateCheckGeneration else {
                    isCheckingForUpdate = false
                    return
                }
                isCheckingForUpdate = false
                updateCheckResult = result
            }
        }
    }

    private func clearConnectionStatus() {
        guard case .validating = connectionStatus else {
            connectionStatus = .idle
            return
        }
    }

    private static var versionText: String {
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        if let parsedVersion = bundleVersion.flatMap({ AppVersion.parse($0) }) {
            return parsedVersion.displayText
        }
        let version = bundleVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let version, !version.isEmpty else {
            return "v0.0.1"
        }
        return version.hasPrefix("v") ? version : "v\(version)"
    }
}

private enum UpdateDefaultsKey {
    static let includeBetaUpdates = "githubRelease.includeBetaUpdates"
}

private enum ConnectionStatus: Equatable {
    case idle
    case validating
    case success(String)
    case failure(String)

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .validating:
            return "正在验证并刷新…"
        case .success(let message), .failure(let message):
            return message
        }
    }

    var color: Color {
        switch self {
        case .idle, .validating:
            return .secondary
        case .success:
            return .green
        case .failure:
            return .red
        }
    }

    var isValidating: Bool {
        if case .validating = self {
            return true
        }
        return false
    }
}
