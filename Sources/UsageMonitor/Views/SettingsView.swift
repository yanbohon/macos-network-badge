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
    @State private var selectedKeyID: String?

    init(
        monitor: UsageSnapshotMonitor,
        updateDefaults: UserDefaults = .standard,
        updateChecker: UpdateChecker = UpdateChecker()
    ) {
        self.monitor = monitor
        self.updateDefaults = updateDefaults
        self.updateChecker = updateChecker
        _draft = State(initialValue: Self.makeDraft(from: monitor))
        _selectedKeyID = State(initialValue: monitor.usageKeys.first?.id)
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
        .onChange(of: draft.defaultBaseURL) { _ in
            clearConnectionStatus()
        }
        .onChange(of: draft.keys) { _ in
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
                text: $draft.defaultBaseURL,
                secure: false,
                autoFocus: true
            )

            keyList

            if selectedKeyIndex != nil {
                selectedKeyEditor
            }

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

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("刷新")

            HStack(alignment: .firstTextBaseline) {
                Text("刷新间隔")
                Spacer(minLength: 12)
                Picker("刷新间隔", selection: $monitor.refreshIntervalSeconds) {
                    ForEach(UsageSnapshotMonitor.allowedRefreshIntervalSeconds, id: \.self) { seconds in
                        Text(refreshIntervalLabel(seconds: seconds)).tag(seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Button {
                commitDraft()
                Task { await monitor.refreshAll() }
            } label: {
                Text(manualRefreshButtonTitle)
            }
            .buttonStyle(.bordered)
            .disabled(monitor.isRefreshing)
        }
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("显示")

            Toggle("菜单栏显示小数点", isOn: $monitor.showMenuBarDecimals)
            Toggle("菜单栏隐藏 SF Symbol", isOn: $monitor.hideMenuBarSymbols)
        }
    }

    private var keyList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Key")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button {
                    commitDraft()
                    let id = monitor.addKey()
                    syncDraftFromMonitor(selectedID: id)
                } label: {
                    Label("新增 Key", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            ForEach(draft.keys) { key in
                Button {
                    selectedKeyID = key.id
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: MenuBarTitleView.resolvedSymbolName(key.symbolName))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(key.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名 Key" : key.name)
                            Text(key.baseURLMode == .inherited ? "继承全局 Base URL" : "独立 Base URL")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(stateSummary(for: key.id))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.horizontal, 7)
                .contentShape(Rectangle())
                .background(selectedKeyID == key.id ? Color.accentColor.opacity(0.14) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var selectedKeyEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeledInput(
                title: "名称",
                placeholder: "Key 名称",
                text: selectedKeyBinding(\.name),
                secure: false
            )
            labeledInput(
                title: "SF Symbol",
                placeholder: "key.fill",
                text: selectedKeyBinding(\.symbolName),
                secure: false,
                helper: "无效名称会显示默认 key.fill。"
            )
            labeledInput(
                title: "API Key",
                placeholder: "输入 API Key",
                text: selectedKeyBinding(\.apiKey),
                secure: true,
                helper: "API Key 仅保存在本机应用偏好设置中。"
            )

            Picker("Base URL 模式", selection: selectedKeyBaseURLModeBinding) {
                ForEach(UsageKeyBaseURLMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if selectedKey?.baseURLMode == .independent {
                labeledInput(
                    title: "独立 Base URL",
                    placeholder: "https://example.com",
                    text: selectedKeyBinding(\.baseURLOverride),
                    secure: false
                )
            }

            HStack {
                Button {
                    Task { await validateSelectedKey() }
                } label: {
                    Text(primaryButtonTitle)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)

                Button {
                    commitDraft()
                    Task { await monitor.refreshAll() }
                } label: {
                    Text("刷新全部")
                }
                .buttonStyle(.bordered)
                .disabled(monitor.isRefreshing)

                Spacer()

                Button(role: .destructive) {
                    deleteSelectedKey()
                } label: {
                    Text("删除 Key")
                }
                .buttonStyle(.bordered)
                .disabled(draft.keys.count <= 1)
            }
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
        monitor.isRefreshing ? "刷新中…" : "刷新全部"
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

    private func refreshIntervalLabel(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) 秒"
        }
        return "\(seconds / 60) 分钟"
    }

    private func validateAndRefresh() async {
        await validateSelectedKey()
    }

    private func validateSelectedKey() async {
        commitDraft()
        connectionStatus = .validating

        do {
            let id = selectedKeyID ?? monitor.usageKeys.first?.id
            if let id {
                try await monitor.validateAndRefreshKey(id: id)
            } else {
                try await monitor.validateAndRefresh()
            }
            connectionStatus = .success("验证成功")
        } catch {
            let id = selectedKeyID ?? monitor.usageKeys.first?.id
            connectionStatus = .failure(id.flatMap { monitor.keyState(id: $0)?.lastError } ?? "验证失败")
        }
    }

    private func commitDraft() {
        draft.commit(to: monitor)
    }

    private func syncDraftFromMonitor() {
        syncDraftFromMonitor(selectedID: selectedKeyID)
    }

    private func syncDraftFromMonitor(selectedID: String?) {
        draft = Self.makeDraft(from: monitor)
        selectedKeyID = selectedID ?? monitor.usageKeys.first?.id
        if !draft.keys.contains(where: { $0.id == selectedKeyID }) {
            selectedKeyID = draft.keys.first?.id
        }
        connectionStatus = .idle
    }

    private static func makeDraft(from monitor: UsageSnapshotMonitor) -> SettingsDraft {
        SettingsDraft(
            defaultBaseURL: monitor.defaultBaseURLText,
            keys: monitor.usageKeys.map { SettingsDraft.KeyDraft(configuration: $0.configuration) }
        )
    }

    private var selectedKeyIndex: Int? {
        guard let selectedKeyID else { return draft.keys.indices.first }
        return draft.keys.firstIndex { $0.id == selectedKeyID }
    }

    private var selectedKey: SettingsDraft.KeyDraft? {
        guard let selectedKeyIndex else { return nil }
        return draft.keys[selectedKeyIndex]
    }

    private func selectedKeyBinding(_ keyPath: WritableKeyPath<SettingsDraft.KeyDraft, String>) -> Binding<String> {
        Binding(
            get: {
                guard let selectedKeyIndex else { return "" }
                return draft.keys[selectedKeyIndex][keyPath: keyPath]
            },
            set: { value in
                guard let selectedKeyIndex else { return }
                draft.keys[selectedKeyIndex][keyPath: keyPath] = value
            }
        )
    }

    private var selectedKeyBaseURLModeBinding: Binding<UsageKeyBaseURLMode> {
        Binding(
            get: {
                guard let selectedKeyIndex else { return .inherited }
                return draft.keys[selectedKeyIndex].baseURLMode
            },
            set: { value in
                guard let selectedKeyIndex else { return }
                draft.keys[selectedKeyIndex].baseURLMode = value
            }
        )
    }

    private func deleteSelectedKey() {
        guard let selectedKeyID, draft.keys.count > 1 else { return }
        monitor.deleteKey(id: selectedKeyID)
        syncDraftFromMonitor(selectedID: monitor.usageKeys.first?.id)
    }

    private func stateSummary(for keyID: String) -> String {
        guard let entry = monitor.keyState(id: keyID) else { return "未配置" }
        switch entry.snapshotFreshness {
        case .fresh:
            return "已刷新"
        case .stale:
            return "缓存"
        case .configurationMismatch:
            return "未验证"
        case .empty:
            return entry.lastFailureKind?.stateTextWithoutCache ?? "未刷新"
        }
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
