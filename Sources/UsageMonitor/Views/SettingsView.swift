import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: UsageSnapshotMonitor
    @ObservedObject var serviceStatusMonitor: ServiceStatusMonitor
    private let backgroundUpdateCoordinator: BackgroundUpdateCoordinator
    @State private var draft: SettingsDraft
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var updateCheckResult: UpdateCheckResult?
    @State private var updateAlertInfo: UpdateReleaseInfo?
    @State private var isCheckingForUpdate = false
    @State private var selectedKeyID: String?
    @State private var selectedTab = SettingsTab.connection

    init(
        monitor: UsageSnapshotMonitor,
        serviceStatusMonitor: ServiceStatusMonitor,
        backgroundUpdateCoordinator: BackgroundUpdateCoordinator
    ) {
        self.monitor = monitor
        self.serviceStatusMonitor = serviceStatusMonitor
        self.backgroundUpdateCoordinator = backgroundUpdateCoordinator
        _draft = State(initialValue: Self.makeDraft(from: monitor))
        _selectedKeyID = State(initialValue: monitor.usageKeys.first?.id)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            connectionPage
                .tabItem {
                    Label("连接", systemImage: "key.horizontal")
                }
                .tag(SettingsTab.connection)

            displayPage
                .tabItem {
                    Label("菜单栏", systemImage: "menubar.rectangle")
                }
                .tag(SettingsTab.display)

            refreshPage
                .tabItem {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .tag(SettingsTab.refresh)

            aboutPage
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
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
            commitDraft()
        }
        .onChange(of: draft.keys) { _ in
            clearConnectionStatus()
            commitDraft()
        }
        .alert(item: $updateAlertInfo) { info in
            Alert(
                title: Text("发现新版本 \(info.versionText)"),
                message: Text("是否前往 GitHub 发布页面查看并下载更新？"),
                primaryButton: .default(Text("下载更新")) {
                    NSWorkspace.shared.open(info.releaseURL)
                },
                secondaryButton: .cancel(Text("稍后"))
            )
        }
    }

    private var connectionPage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    defaultServerSection
                    Divider()
                    keyListSection
                    Divider()

                    if selectedKeyIndex != nil {
                        selectedKeyEditor
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "key.horizontal")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text("没有 API Key")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 160)
                    }
                }
            }

            Divider()
            connectionActionBar
        }
    }

    private var defaultServerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("默认服务器")
                .font(.headline)

            formRow("Base URL") {
                nativeTextField(
                    placeholder: "https://example.com",
                    text: $draft.defaultBaseURL,
                    secure: false,
                    autoFocus: true
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var keyListSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("API Keys")
                    .font(.headline)
                Spacer()
                Text("\(draft.keys.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .frame(height: 40)

            Divider()

            List {
                ForEach(draft.keys) { key in
                    keyRowButton(for: key)
                }
            }
            .listStyle(.inset)
            .frame(height: keyListHeight)

            Divider()

            HStack(spacing: 2) {
                Button {
                    commitDraft()
                    let id = monitor.addKey()
                    syncDraftFromMonitor(selectedID: id)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("新增 Key")

                Button(role: .destructive) {
                    deleteSelectedKey()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .disabled(draft.keys.count <= 1)
                .help("删除所选 Key")

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var selectedKeyEditor: some View {
        VStack(alignment: .leading, spacing: 20) {
            selectedKeyHeader

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                formRow("名称") {
                    nativeTextField(
                        placeholder: "Key 名称",
                        text: selectedKeyBinding(\.name),
                        secure: false
                    )
                }

                formRow("SF Symbol") {
                    HStack(spacing: 8) {
                        nativeTextField(
                            placeholder: "key.fill",
                            text: selectedKeyBinding(\.symbolName),
                            secure: false
                        )

                        ColorPicker(
                            "SF Symbol 颜色",
                            selection: selectedKeySymbolColorBinding,
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        .help("SF Symbol 颜色")
                    }
                }

                formRow("颜色值") {
                    HStack(spacing: 10) {
                        nativeTextField(
                            placeholder: UsageKeyConfiguration.defaultSymbolColorHex,
                            text: selectedKeyBinding(\.symbolColorHex),
                            secure: false
                        )
                        Text("#RRGGBB")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                formRow("菜单栏") {
                    HStack {
                        Text("在菜单栏显示")
                        Spacer()
                        Toggle("在菜单栏显示", isOn: selectedKeyShowsInMenuBarBinding)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                formRow("API Key", alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        nativeTextField(
                            placeholder: "输入 API Key",
                            text: selectedKeyBinding(\.apiKey),
                            secure: true
                        )
                        Label("仅保存在本机应用偏好设置中", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                formRow("Base URL") {
                    Picker("Base URL", selection: selectedKeyBaseURLModeBinding) {
                        Text("使用默认").tag(UsageKeyBaseURLMode.inherited)
                        Text("自定义").tag(UsageKeyBaseURLMode.independent)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                if selectedKey?.baseURLMode == .independent {
                    formRow("自定义地址") {
                        nativeTextField(
                            placeholder: "https://example.com",
                            text: selectedKeyBinding(\.baseURLOverride),
                            secure: false
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var selectedKeyHeader: some View {
        let state = selectedKeyID.map(keyStatePresentation) ?? .unconfigured
        return HStack(spacing: 10) {
            Image(systemName: MenuBarTitleView.resolvedSymbolName(selectedKey?.symbolName ?? ""))
                .font(.system(size: 24))
                .foregroundStyle(
                    SymbolColor.swiftUIColor(
                        hex: selectedKey?.symbolColorHex ?? UsageKeyConfiguration.defaultSymbolColorHex
                    )
                )
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(selectedKeyDisplayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Label(state.text, systemImage: state.systemImage)
                    .font(.caption)
                    .foregroundStyle(state.color)
            }

            Spacer()
        }
    }

    private var connectionActionBar: some View {
        let status = connectionStatus.presentation
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()

                Button {
                    Task { await validateAndRefresh() }
                } label: {
                    HStack(spacing: 6) {
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(primaryButtonTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isBusy)
            }

            if let statusText = status.text {
                Label(statusText, systemImage: status.systemImage)
                    .font(.caption)
                    .foregroundStyle(status.color)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var displayPage: some View {
        DisplaySettingsPage(
            monitor: monitor,
            serviceStatusMonitor: serviceStatusMonitor
        )
    }

    private var refreshPage: some View {
        RefreshSettingsPage(monitor: monitor) {
            commitDraft()
            Task {
                await monitor.refreshAll()
            }
        }
    }

    private var aboutPage: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)

            VStack(spacing: 4) {
                Text("用量监控")
                    .font(.title2.weight(.semibold))
                Text(Self.versionText)
                    .foregroundStyle(.secondary)
            }

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
                    .multilineTextAlignment(.center)
            }

            if let releaseURL = updateCheckResult?.releaseURL {
                Button {
                    NSWorkspace.shared.open(releaseURL)
                } label: {
                    Label("前往发布页面", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func formRow<Content: View>(
        _ title: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: 12) {
            Text(title)
                .frame(width: 84, alignment: .trailing)
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func nativeTextField(
        placeholder: String,
        text: Binding<String>,
        secure: Bool,
        autoFocus: Bool = false
    ) -> some View {
        NativeTextInput(
            placeholder: placeholder,
            text: text,
            secure: secure,
            autoFocus: autoFocus
        )
        .frame(maxWidth: .infinity)
        .frame(height: 22)
    }

    private var selectedKeyDisplayName: String {
        let name = selectedKey?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "未命名 Key" : name
    }

    private var keyListHeight: CGFloat {
        min(CGFloat(max(draft.keys.count, 1)) * 52, 132)
    }

    private var primaryButtonTitle: String {
        isBusy ? "验证中…" : "验证并刷新"
    }

    private var isBusy: Bool {
        connectionStatus.isValidating
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

    private func keyRowButton(for key: SettingsDraft.KeyDraft) -> some View {
        let state = keyStatePresentation(for: key.id)
        return Button {
            selectedKeyID = key.id
            connectionStatus = .idle
        } label: {
            HStack(spacing: 9) {
                Image(systemName: MenuBarTitleView.resolvedSymbolName(key.symbolName))
                    .foregroundStyle(SymbolColor.swiftUIColor(hex: key.symbolColorHex))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(key.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名 Key" : key.name)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(state.text)
                            .font(.caption)
                            .foregroundStyle(state.color)
                    }
                    Text(keySummary(for: key))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .contentShape(Rectangle())
            .background(selectedKeyID == key.id ? Color.accentColor.opacity(0.16) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func keySummary(for key: SettingsDraft.KeyDraft) -> String {
        let baseURLText = key.baseURLMode == .inherited ? "继承全局 Base URL" : "独立 Base URL"
        return key.showsInMenuBar ? baseURLText : "\(baseURLText) · 菜单栏隐藏"
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

    private var selectedKeyShowsInMenuBarBinding: Binding<Bool> {
        Binding(
            get: {
                guard let selectedKeyIndex else { return true }
                return draft.keys[selectedKeyIndex].showsInMenuBar
            },
            set: { value in
                guard let selectedKeyIndex else { return }
                draft.keys[selectedKeyIndex].showsInMenuBar = value
            }
        )
    }

    private var selectedKeySymbolColorBinding: Binding<Color> {
        Binding(
            get: {
                guard let selectedKeyIndex else {
                    return SymbolColor.swiftUIColor(hex: UsageKeyConfiguration.defaultSymbolColorHex)
                }
                return SymbolColor.swiftUIColor(hex: draft.keys[selectedKeyIndex].symbolColorHex)
            },
            set: { value in
                guard let selectedKeyIndex else { return }
                draft.keys[selectedKeyIndex].symbolColorHex = SymbolColor.hexString(from: value)
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

    private func keyStatePresentation(for keyID: String) -> KeyStatePresentation {
        guard let entry = monitor.keyState(id: keyID) else { return .unconfigured }
        switch entry.snapshotFreshness {
        case .fresh:
            return KeyStatePresentation(text: "已刷新", systemImage: "checkmark.circle.fill", color: .green)
        case .stale:
            return KeyStatePresentation(text: "缓存", systemImage: "clock.badge.exclamationmark", color: .orange)
        case .configurationMismatch:
            return KeyStatePresentation(text: "未验证", systemImage: "exclamationmark.circle", color: .secondary)
        case .empty:
            if let failure = entry.lastFailureKind {
                return KeyStatePresentation(
                    text: failure.stateTextWithoutCache,
                    systemImage: "xmark.circle.fill",
                    color: .red
                )
            }
            return KeyStatePresentation(text: "未刷新", systemImage: "circle.dashed", color: .secondary)
        }
    }

    private func startUpdateCheck() {
        updateCheckResult = nil
        isCheckingForUpdate = true

        Task {
            let outcome = await backgroundUpdateCoordinator.checkManually()
            await MainActor.run {
                isCheckingForUpdate = false
                updateCheckResult = outcome.result
                updateAlertInfo = outcome.alertInfo
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

private enum SettingsTab: Hashable {
    case connection
    case display
    case refresh
    case about
}

private struct DisplaySettingsPage: View {
    @ObservedObject var monitor: UsageSnapshotMonitor
    @ObservedObject var serviceStatusMonitor: ServiceStatusMonitor

    var body: some View {
        SettingsPageLayout {
            SettingsSectionLayout("用量") {
                SettingsToggleRow("显示小数位", isOn: $monitor.showMenuBarDecimals)
            }

            SettingsSectionLayout("Key 图标") {
                SettingsToggleRow("显示 SF Symbol", isOn: showMenuBarSymbolsBinding)
            }

            SettingsSectionLayout("服务状态") {
                SettingsRow("菜单栏服务状态") {
                    Picker("菜单栏服务状态", selection: $serviceStatusMonitor.menuBarModel) {
                        ForEach(ServiceStatusMonitor.supportedModels) { model in
                            Text(model.rawValue).tag(model)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }
            }
        }
    }

    private var showMenuBarSymbolsBinding: Binding<Bool> {
        Binding(
            get: { !monitor.hideMenuBarSymbols },
            set: { monitor.hideMenuBarSymbols = !$0 }
        )
    }
}

private struct RefreshSettingsPage: View {
    @ObservedObject var monitor: UsageSnapshotMonitor
    let refreshAll: () -> Void

    var body: some View {
        SettingsPageLayout {
            SettingsSectionLayout("自动刷新") {
                SettingsRow("刷新间隔") {
                    Picker("刷新间隔", selection: $monitor.refreshIntervalSeconds) {
                        ForEach(UsageSnapshotMonitor.allowedRefreshIntervalSeconds, id: \.self) { seconds in
                            Text(refreshIntervalLabel(seconds: seconds)).tag(seconds)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
            }

            SettingsSectionLayout("手动刷新") {
                SettingsRow("所有 Key") {
                    Button(action: refreshAll) {
                        Label(refreshButtonTitle, systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(monitor.isRefreshing)
                }
            }
        }
    }

    private var refreshButtonTitle: String {
        monitor.isRefreshing ? "刷新中…" : "刷新全部"
    }

    private func refreshIntervalLabel(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) 秒"
        }
        return "\(seconds / 60) 分钟"
    }
}

private struct SettingsPageLayout<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                content
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SettingsSectionLayout<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            VStack(spacing: 10) {
                content
            }
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .frame(minHeight: 28)
    }
}

private struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
            Spacer(minLength: 20)
            content
        }
        .frame(minHeight: 28)
    }
}

private struct KeyStatePresentation {
    static let unconfigured = KeyStatePresentation(
        text: "未配置",
        systemImage: "questionmark.circle",
        color: Color.secondary
    )

    let text: String
    let systemImage: String
    let color: Color
}

private struct StatusPresentation {
    let text: String?
    let systemImage: String
    let color: Color
}

private enum ConnectionStatus: Equatable {
    case idle
    case validating
    case success(String)
    case failure(String)

    var presentation: StatusPresentation {
        switch self {
        case .idle:
            return StatusPresentation(text: nil, systemImage: "circle", color: .secondary)
        case .validating:
            return StatusPresentation(
                text: "正在验证并刷新…",
                systemImage: "arrow.triangle.2.circlepath",
                color: .secondary
            )
        case .success(let message):
            return StatusPresentation(text: message, systemImage: "checkmark.circle.fill", color: .green)
        case .failure(let message):
            return StatusPresentation(text: message, systemImage: "xmark.circle.fill", color: .red)
        }
    }

    var isValidating: Bool {
        if case .validating = self {
            return true
        }
        return false
    }
}
