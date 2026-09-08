import SwiftUI

enum UsageKeyPager {
    static func clampedSelection(currentIndex: Int, keyCount: Int) -> Int {
        guard keyCount > 0 else { return 0 }
        return min(max(0, currentIndex), keyCount - 1)
    }

    static func selectedEntry(in entries: [UsageKeyEntry], selectedIndex: Int) -> UsageKeyEntry? {
        guard !entries.isEmpty else { return nil }
        return entries[clampedSelection(currentIndex: selectedIndex, keyCount: entries.count)]
    }
}

struct MenuBarView: View {
    private static let serviceTimelineCellWidth: CGFloat = 4.8
    private static let serviceTimelineCellHeight: CGFloat = 16
    private static let serviceTimelineCellSpacing: CGFloat = 2

    @ObservedObject var monitor: UsageSnapshotMonitor
    @ObservedObject var serviceStatusMonitor: ServiceStatusMonitor
    @ObservedObject var cursorMonitor: CursorUsageMonitor
    @ObservedObject var settingsWindowController: SettingsWindowController
    @State private var showsAllServiceStatuses = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            serviceStatusSection
            cursorSection
            keysSection
        }
        .padding(16)
        .frame(width: 440)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("用量监控")
                    .font(.headline)
                Text("\(monitor.usageKeys.count) 个 Key")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(refreshText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                Task { await monitor.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("刷新 Key")

            Button {
                settingsWindowController.showWindow(
                    monitor: monitor,
                    serviceStatusMonitor: serviceStatusMonitor,
                    cursorMonitor: cursorMonitor
                )
            } label: {
                Image(systemName: "gearshape")
            }
            .help("设置")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("退出")
        }
    }

    private var refreshText: String {
        if monitor.isRefreshing {
            return "正在刷新"
        }
        if let date = monitor.usageKeys.compactMap(\.lastSuccessfulRefresh).max() {
            return "上次成功刷新 \(date.formatted(date: .omitted, time: .shortened))"
        }
        return "尚未成功刷新"
    }

    private var cursorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cursor")
                    .font(.caption.bold())
                Spacer()
                Button {
                    Task { await cursorMonitor.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新 Cursor")
                .disabled(cursorMonitor.accounts.isEmpty || cursorMonitor.isRefreshing)
            }

            if cursorMonitor.accounts.isEmpty {
                Text("未配置 Cursor 账号")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(cursorMonitor.accounts) { account in
                    cursorAccountRow(account)
                }
            }
        }
    }

    private func cursorAccountRow(_ account: CursorAccountRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: MenuBarTitleView.resolvedSymbolName(account.symbolName))
                    .foregroundStyle(SymbolColor.swiftUIColor(hex: account.ringColorHex))
                    .frame(width: 10, height: 10)
                Text(account.displayName)
                    .lineLimit(1)
                if let plan = account.membershipDisplayName {
                    Text(plan)
                        .fontWeight(.semibold)
                        .foregroundStyle(membershipColor(for: account))
                }
                Spacer()
                Text("Auto \(account.autoUsageText)")
                    .monospacedDigit()
                Text("API \(account.apiUsageText)")
                    .monospacedDigit()
                if account.showsSandRing {
                    Text("\(account.sandDisplayName) \(account.sandUsageText)")
                        .monospacedDigit()
                }
            }
            .font(.caption)

            Text(cursorStatusLine(for: account))
                .font(.caption)
                .foregroundColor(.secondary)

            if let error = account.lastError, !error.isEmpty, account.autoPercentUsed != nil {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func cursorStatusLine(for account: CursorAccountRecord) -> String {
        [cursorMonitor.refreshText(for: account), account.billingCycleEndText]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func membershipColor(for account: CursorAccountRecord) -> Color {
        guard let hex = account.membershipColorHex else {
            return .secondary
        }
        return SymbolColor.swiftUIColor(hex: hex)
    }

    private var keysSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Key")
                    .font(.caption.bold())
                Spacer()
                Button {
                    Task { await monitor.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新 Key")
                .disabled(monitor.usageKeys.isEmpty || monitor.isRefreshing)
            }

            if monitor.usageKeys.isEmpty {
                Text("未配置 Key")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(monitor.usageKeys) { entry in
                    keyAccountRow(entry)
                }
            }
        }
    }

    private func keyAccountRow(_ entry: UsageKeyEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: MenuBarTitleView.resolvedSymbolName(entry.configuration.symbolName))
                    .foregroundStyle(SymbolColor.swiftUIColor(hex: entry.configuration.symbolColorHex))
                    .frame(width: 10, height: 10)
                Text(entry.configuration.name)
                    .lineLimit(1)
                Spacer()
                Text("今日 \(todayBalanceText(for: entry))")
                    .monospacedDigit()
            }
            .font(.caption)

            Text(refreshText(for: entry))
                .font(.caption)
                .foregroundColor(.secondary)

            if let error = entry.lastError, !error.isEmpty, entry.canShowSnapshotData {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func todayBalanceText(for entry: UsageKeyEntry) -> String {
        guard entry.canShowSnapshotData, let subscription = entry.snapshot?.subscription else {
            return "—"
        }
        if subscription.dailyLimitUSD == 0 {
            return "不限量"
        }
        return UsageFormatters.balanceText(max(0, subscription.dailyLimitUSD - subscription.dailyUsageUSD))
    }

    private func refreshText(for entry: UsageKeyEntry) -> String {
        if monitor.isRefreshing || entry.isRefreshing {
            return "正在刷新"
        }
        if let date = entry.lastSuccessfulRefresh {
            return "上次成功刷新 \(date.formatted(date: .omitted, time: .shortened))"
        }
        if let error = entry.lastError, !error.isEmpty {
            return error
        }
        return "尚未成功刷新"
    }

    private var serviceStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("服务状态")
                    .font(.caption.bold())
                Spacer()
                Text("\(ServiceStatusMonitor.monitoredModels.count) models")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            if let detail = serviceStatusMonitor.lastError {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let primaryRow = serviceStatusMonitor.timelineRows.first {
                serviceTimelineRow(primaryRow, showsDisclosure: true)
            }

            if showsAllServiceStatuses {
                ForEach(Array(serviceStatusMonitor.timelineRows.dropFirst())) { row in
                    serviceTimelineRow(row)
                }
            }

            serviceStatusFooter
        }
        .padding(.vertical, 2)
    }

    private func serviceTimelineRow(
        _ row: ServiceStatusTimelineRow,
        showsDisclosure: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(row.model)
                    .font(.caption.bold().monospaced())
                    .lineLimit(1)
                Circle()
                    .fill(row.latestKind.swiftUIColor)
                    .frame(width: 7, height: 7)
                    .opacity(row.latestKind == .gray ? 0.45 : 1)
                Text(row.statusText)
                    .font(.caption.monospaced())
                    .foregroundColor(statusColor(for: row.latestKind))
                if showsDisclosure {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showsAllServiceStatuses.toggle()
                        }
                    } label: {
                        Image(systemName: showsAllServiceStatuses ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(showsAllServiceStatuses ? "收起其他模型状态" : "展开其他模型状态")
                    .accessibilityLabel(showsAllServiceStatuses ? "收起其他模型状态" : "展开其他模型状态")
                }
                Spacer()
            }

            HStack(spacing: 16) {
                Text("可用率")
                    .foregroundColor(.secondary)
                Text(row.uptimeText)
                    .foregroundColor(uptimeColor(for: row))
                Text("样本")
                    .foregroundColor(.secondary)
                Text(row.samplesText)
                Spacer()
            }
            .font(.caption.monospacedDigit())

            HStack(spacing: Self.serviceTimelineCellSpacing) {
                ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(cell.kind.swiftUIColor)
                        .frame(
                            width: Self.serviceTimelineCellWidth,
                            height: Self.serviceTimelineCellHeight
                        )
                        .opacity(cell.kind == .gray ? 0.35 : 1)
                        .help(timelineCellHelp(row: row, cell: cell))
                }
            }
            .opacity(serviceStatusMonitor.isStaleAfterFailure ? 0.55 : 1)
            .accessibilityLabel("\(row.model) 最近六十次状态")

            HStack {
                Text("-60m")
                Spacer()
                Text("-45m")
                Spacer()
                Text("-30m")
                Spacer()
                Text("-15m")
                Spacer()
                Text("现在")
            }
            .font(.caption2.monospacedDigit())
            .foregroundColor(.secondary)
        }
    }

    private var serviceStatusFooter: some View {
        HStack(spacing: 10) {
            if let generatedAt = serviceStatusMonitor.response?.generatedAt {
                Text("接口生成 \(formattedTimestamp(generatedAt))")
            }
            if let refreshedAt = serviceStatusMonitor.lastSuccessfulRefresh {
                Text("状态刷新 \(refreshedAt.formatted(date: .omitted, time: .standard))")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private func timelineCellHelp(row: ServiceStatusTimelineRow, cell: ServiceStatusDisplayCell) -> String {
        var lines = [row.model]
        if let timestamp = cell.probe?.ts {
            lines.append(formattedTimestamp(timestamp))
        }
        lines.append("状态 \(cellStatusText(for: cell.kind))")
        if let latencyMS = cell.probe?.latencyMS {
            lines.append("延迟 \(formattedLatency(latencyMS))")
        }
        if let error = cell.probe?.error, !error.isEmpty {
            lines.append("错误 \(error)")
        }
        return lines.joined(separator: "\n")
    }

    private func cellStatusText(for kind: ServiceStatusCellKind) -> String {
        switch kind {
        case .green:
            return "正常"
        case .yellow:
            return "高延迟"
        case .red:
            return "失败"
        case .gray:
            return "未知"
        }
    }

    private func statusColor(for kind: ServiceStatusCellKind) -> Color {
        switch kind {
        case .green:
            return .green
        case .yellow:
            return .orange
        case .red:
            return .red
        case .gray:
            return .secondary
        }
    }

    private func uptimeColor(for row: ServiceStatusTimelineRow) -> Color {
        guard let uptime = row.service?.uptimePct else {
            return .secondary
        }
        if uptime >= 95 {
            return .green
        }
        if uptime >= 80 {
            return .orange
        }
        return .red
    }

    private func formattedTimestamp(_ timestamp: TimeInterval) -> String {
        Date(timeIntervalSince1970: timestamp).formatted(date: .omitted, time: .standard)
    }

    private func formattedLatency(_ latencyMS: Int?) -> String {
        guard let latencyMS else { return "--" }
        return "\(latencyMS) ms"
    }
}
