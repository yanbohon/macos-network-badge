import AppKit
import SwiftUI

struct CursorSettingsPage: View {
    @ObservedObject var monitor: CursorUsageMonitor
    @State private var selectedAccountID: String?
    @State private var connectionStatus: CursorConnectionStatus = .idle

    init(monitor: CursorUsageMonitor) {
        self.monitor = monitor
        _selectedAccountID = State(initialValue: monitor.selectedAccountID ?? monitor.accounts.first?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    accountListSection
                    Divider()

                    if selectedAccount != nil {
                        selectedAccountEditor
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "circle.dotted")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text("没有 Cursor 账号")
                                .font(.headline)
                            Text("粘贴 Access Token 后即可在菜单栏显示 Auto 和 Grok 用量。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 160)
                        .padding(.horizontal, 24)
                    }
                }
            }

            Divider()
            actionBar
        }
        .onAppear {
            if selectedAccountID == nil {
                selectedAccountID = monitor.selectedAccountID ?? monitor.accounts.first?.id
            }
        }
    }

    private var accountListSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Cursor 账号")
                    .font(.headline)
                Spacer()
                Text("\(monitor.accounts.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .frame(height: 40)

            Divider()

            List {
                ForEach(monitor.accounts) { account in
                    accountRowButton(for: account)
                }
            }
            .listStyle(.inset)
            .frame(height: accountListHeight)

            Divider()

            HStack(spacing: 2) {
                Button {
                    let id = monitor.addAccount()
                    selectedAccountID = id
                    connectionStatus = .idle
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help("新增账号")

                Button(role: .destructive) {
                    deleteSelectedAccount()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .disabled(monitor.accounts.isEmpty)
                .help("删除所选账号")

                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var selectedAccountEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(selectedAccount?.displayName ?? "未验证账号")
                    .font(.headline)
                Spacer()
                if selectedAccount?.showsInMenuBar == true {
                    Text("菜单栏")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("在菜单栏显示", isOn: showsInMenuBarBinding)
                .toggleStyle(.switch)

            formRow("SF Symbol") {
                HStack(spacing: 8) {
                    nativeTextField(
                        placeholder: CursorAccountRecord.defaultSymbolName,
                        text: symbolNameBinding,
                        secure: false
                    )
                    ColorPicker(
                        "SF Symbol 颜色",
                        selection: ringColorBinding,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .help("SF Symbol 颜色")
                    Text(selectedAccount?.ringColorHex ?? CursorAccountRecord.defaultRingColorHex)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            formRow("Access Token", alignment: .top) {
                nativeTextField(
                    placeholder: "粘贴 Cursor Access Token",
                    text: accessTokenBinding,
                    secure: true
                )
            }

            formRow("Refresh Token", alignment: .top) {
                nativeTextField(
                    placeholder: "可选，过期后自动刷新",
                    text: refreshTokenBinding,
                    secure: true
                )
            }

            if let error = selectedAccount?.lastError, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            if let presentation = connectionStatus.presentationText {
                Image(systemName: connectionStatus.systemImage)
                    .foregroundStyle(connectionStatus.color)
                Text(presentation)
                    .font(.caption)
                    .foregroundStyle(connectionStatus.color)
            } else if let refresh = selectedAccount?.lastSuccessfulRefresh {
                Text("上次成功刷新 \(refresh.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await validateAndRefresh() }
            } label: {
                Text(connectionStatus.isValidating ? "验证中…" : "验证并刷新")
            }
            .disabled(selectedAccount == nil || connectionStatus.isValidating)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var selectedAccount: CursorAccountRecord? {
        guard let selectedAccountID else { return nil }
        return monitor.accounts.first { $0.id == selectedAccountID }
    }

    private var accountListHeight: CGFloat {
        min(CGFloat(max(monitor.accounts.count, 1)) * 52, 132)
    }

    private var showsInMenuBarBinding: Binding<Bool> {
        Binding(
            get: { selectedAccount?.showsInMenuBar ?? false },
            set: { isOn in
                guard let selectedAccountID else { return }
                monitor.setShowsInMenuBar(id: selectedAccountID, shows: isOn)
            }
        )
    }

    private var ringColorBinding: Binding<Color> {
        Binding(
            get: {
                SymbolColor.swiftUIColor(
                    hex: selectedAccount?.ringColorHex ?? CursorAccountRecord.defaultRingColorHex
                )
            },
            set: { value in
                guard let selectedAccountID else { return }
                monitor.updateRingColor(id: selectedAccountID, hex: SymbolColor.hexString(from: value))
            }
        )
    }

    private var symbolNameBinding: Binding<String> {
        Binding(
            get: { selectedAccount?.symbolName ?? CursorAccountRecord.defaultSymbolName },
            set: { value in
                guard let selectedAccountID else { return }
                monitor.updateSymbolName(id: selectedAccountID, symbolName: value)
            }
        )
    }

    private var accessTokenBinding: Binding<String> {
        Binding(
            get: { selectedAccount?.accessToken ?? "" },
            set: { value in
                guard let account = selectedAccount else { return }
                monitor.updateAccount(id: account.id, accessToken: value, refreshToken: account.refreshToken)
            }
        )
    }

    private var refreshTokenBinding: Binding<String> {
        Binding(
            get: { selectedAccount?.refreshToken ?? "" },
            set: { value in
                guard let account = selectedAccount else { return }
                monitor.updateAccount(id: account.id, accessToken: account.accessToken, refreshToken: value)
            }
        )
    }

    private func accountRowButton(for account: CursorAccountRecord) -> some View {
        Button {
            selectedAccountID = account.id
            connectionStatus = .idle
        } label: {
            HStack(spacing: 9) {
                Image(systemName: MenuBarTitleView.resolvedSymbolName(account.symbolName))
                    .foregroundStyle(SymbolColor.swiftUIColor(hex: account.ringColorHex))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(account.displayName)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(accountStatusText(for: account))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(accountListSummary(for: account))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .contentShape(Rectangle())
            .background(selectedAccountID == account.id ? Color.accentColor.opacity(0.16) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private func accountListSummary(for account: CursorAccountRecord) -> String {
        if account.autoPercentUsed == nil && !account.showsSandRing {
            return "尚未刷新"
        }
        var parts = ["Auto \(account.autoUsageText)"]
        if account.showsSandRing {
            parts.append("\(account.sandDisplayName) \(account.sandUsageText)")
        }
        return parts.joined(separator: " · ")
    }

    private func accountStatusText(for account: CursorAccountRecord) -> String {
        if account.showsInMenuBar {
            return "菜单栏"
        }
        if !account.hasAccessToken {
            return "未配置"
        }
        return ""
    }

    private func deleteSelectedAccount() {
        guard let selectedAccountID else { return }
        monitor.deleteAccount(id: selectedAccountID)
        self.selectedAccountID = monitor.selectedAccountID ?? monitor.accounts.first?.id
        connectionStatus = .idle
    }

    private func validateAndRefresh() async {
        guard let selectedAccountID else { return }
        connectionStatus = .validating
        await monitor.refreshAccount(id: selectedAccountID)
        if let error = monitor.accounts.first(where: { $0.id == selectedAccountID })?.lastError, !error.isEmpty {
            connectionStatus = .failure(error)
        } else {
            connectionStatus = .success("验证成功")
        }
    }

    private func formRow<Content: View>(
        _ title: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: 12) {
            Text(title)
                .frame(width: 96, alignment: .trailing)
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func nativeTextField(
        placeholder: String,
        text: Binding<String>,
        secure: Bool
    ) -> some View {
        NativeTextInput(
            placeholder: placeholder,
            text: text,
            secure: secure
        )
        .frame(maxWidth: .infinity)
        .frame(height: 22)
    }
}

private enum CursorConnectionStatus: Equatable {
    case idle
    case validating
    case success(String)
    case failure(String)

    var isValidating: Bool {
        if case .validating = self { return true }
        return false
    }

    var presentationText: String? {
        switch self {
        case .idle:
            return nil
        case .validating:
            return "正在验证并刷新…"
        case let .success(message), let .failure(message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "circle"
        case .validating:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "xmark.circle.fill"
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
}
