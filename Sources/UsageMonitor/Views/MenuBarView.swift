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
    @ObservedObject var settingsWindowController: SettingsWindowController
    @State private var selectedKeyIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            serviceStatusSection
            keyPager

            if let entry = currentEntry {
                currentKeyDetail(entry)
            } else {
                Text("未配置")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let entry = currentEntry, !(entry.thresholdAlertState?.messages ?? []).isEmpty {
                alertSection(entry)
            }
        }
        .padding(16)
        .frame(width: 440)
        .onChange(of: monitor.usageKeys.count) { newValue in
            selectedKeyIndex = UsageKeyPager.clampedSelection(
                currentIndex: selectedKeyIndex,
                keyCount: newValue
            )
        }
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
                if let id = currentEntry?.id {
                    Task { await monitor.refreshCurrentKey(id: id) }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("刷新当前 Key")

            Button {
                Task { await monitor.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise.circle")
            }
            .help("全部刷新")

            Button {
                settingsWindowController.showWindow(monitor: monitor)
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

    private var currentEntry: UsageKeyEntry? {
        UsageKeyPager.selectedEntry(in: monitor.usageKeys, selectedIndex: selectedKeyIndex)
    }

    private var keyPager: some View {
        HStack(spacing: 10) {
            Button {
                selectedKeyIndex = UsageKeyPager.clampedSelection(
                    currentIndex: selectedKeyIndex - 1,
                    keyCount: monitor.usageKeys.count
                )
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(selectedKeyIndex <= 0)
            .help("上一个 Key")

            Spacer()

            if let entry = currentEntry {
                VStack(spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: MenuBarTitleView.resolvedSymbolName(entry.configuration.symbolName))
                            .foregroundStyle(SymbolColor.swiftUIColor(hex: entry.configuration.symbolColorHex))
                        Text(entry.configuration.name)
                            .font(.subheadline.bold())
                    }
                    Text("第 \(UsageKeyPager.clampedSelection(currentIndex: selectedKeyIndex, keyCount: monitor.usageKeys.count) + 1) / \(max(1, monitor.usageKeys.count)) 个")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                selectedKeyIndex = UsageKeyPager.clampedSelection(
                    currentIndex: selectedKeyIndex + 1,
                    keyCount: monitor.usageKeys.count
                )
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(selectedKeyIndex >= monitor.usageKeys.count - 1)
            .help("下一个 Key")
        }
    }

    private func alertSection(_ entry: UsageKeyEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("提醒")
                .font(.caption.bold())
            ForEach(Array((entry.thresholdAlertState?.messages ?? []).enumerated()), id: \.offset) { _, message in
                Text(message)
                    .font(.caption)
                    .foregroundColor(alertColor(for: entry))
            }
        }
    }

    private func alertColor(for entry: UsageKeyEntry) -> Color {
        if let alert = entry.thresholdAlertState,
           alert.kinds.contains(.dailyUsage95) || alert.kinds.contains(.subscriptionExpired) {
            return .red
        }
        return .orange
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

            ForEach(serviceStatusMonitor.timelineRows) { row in
                serviceTimelineRow(row)
            }

            serviceStatusFooter
        }
        .padding(.vertical, 2)
    }

    private func serviceTimelineRow(_ row: ServiceStatusTimelineRow) -> some View {
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

    private func currentKeyDetail(_ entry: UsageKeyEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            keySummary(entry)
            if let snapshot = entry.snapshot, entry.canShowSnapshotData {
                usageSnapshot(snapshot)
            } else {
                Text(statusLineText(for: entry))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func keySummary(_ entry: UsageKeyEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: MenuBarTitleView.resolvedSymbolName(entry.configuration.symbolName))
                    .foregroundStyle(SymbolColor.swiftUIColor(hex: entry.configuration.symbolColorHex))
                Text(entry.configuration.name)
                    .font(.caption.bold())
                Spacer()
                Text("余额 \(balanceText(for: entry))")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Text(baseURLSourceText(for: entry.configuration))
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(statusLineText(for: entry))
                .font(.caption)
                .foregroundColor(.secondary)
            if let date = entry.lastSuccessfulRefresh {
                Text("上次成功刷新 \(date.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let detail = entry.lastError {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func usageSnapshot(_ snapshot: UsageResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            planSection(snapshot)
            subscriptionSection(snapshot.subscription)
            usageSection(snapshot.usage)
            modelStatsSection(snapshot.modelStats)
        }
    }

    private func planSection(_ snapshot: UsageResponse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snapshot.planName)
                    .font(.subheadline.bold())
                Spacer()
                Text(snapshot.isValid ? "有效" : "无效")
                    .font(.caption)
                    .foregroundColor(snapshot.isValid ? .green : .red)
            }
        }
    }

    private func subscriptionSection(_ subscription: UsageSubscription) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("订阅")
                .font(.caption.bold())
            metricRow(
                title: "今日",
                value: UsageFormatters.usageLimitText(
                    used: subscription.dailyUsageUSD,
                    limit: subscription.dailyLimitUSD
                ),
                trailing: UsageFormatters.percentageText(
                    used: subscription.dailyUsageUSD,
                    limit: subscription.dailyLimitUSD
                )
            )
            metricRow(
                title: "本周",
                value: UsageFormatters.usageLimitText(
                    used: subscription.weeklyUsageUSD,
                    limit: subscription.weeklyLimitUSD
                )
            )
            metricRow(
                title: "本月",
                value: UsageFormatters.usageLimitText(
                    used: subscription.monthlyUsageUSD,
                    limit: subscription.monthlyLimitUSD
                )
            )
            Text(UsageFormatters.expiryText(subscription.expiresAt))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func usageSection(_ usage: UsageUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("请求")
                .font(.caption.bold())
            metricRow(title: "今日", value: UsageFormatters.bucketText(usage.today))
            metricRow(title: "总计", value: UsageFormatters.bucketText(usage.total))
            Text(UsageFormatters.rateText(rpm: usage.rpm, tpm: usage.tpm))
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: "平均耗时 %.1f ms", usage.averageDurationMS))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func modelStatsSection(_ modelStats: [UsageModelStat]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("模型")
                .font(.caption.bold())
            if modelStats.isEmpty {
                Text("暂无模型用量")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(modelStats.enumerated()), id: \.offset) { _, stat in
                    modelStatRow(stat)
                }
            }
        }
    }

    private func modelStatRow(_ stat: UsageModelStat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(stat.modelName)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text("\(stat.requestCount) 次")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Text("\(stat.totalTokens) tokens · \(UsageFormatters.tokenBreakdownText(input: stat.inputTokens, output: stat.outputTokens))")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("成本 \(UsageFormatters.currency(stat.totalCostUSD)) · \(UsageFormatters.costBreakdownText(input: stat.inputCostUSD, output: stat.outputCostUSD))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func metricRow(title: String, value: String, trailing: String? = nil) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Text(value)
                .monospacedDigit()
            Spacer()
            if let trailing {
                Text(trailing)
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption)
    }

    private func balanceText(for entry: UsageKeyEntry) -> String {
        guard entry.canShowSnapshotData, let snapshot = entry.snapshot else { return "--" }
        return UsageFormatters.balanceText(snapshot.remaining)
    }

    private func baseURLSourceText(for configuration: UsageKeyConfiguration) -> String {
        switch configuration.baseURLMode {
        case .inherited:
            return "Base URL：继承 \(monitor.defaultBaseURLText)"
        case .independent:
            return "Base URL：独立 \(configuration.baseURLOverride)"
        }
    }

    private func statusLineText(for entry: UsageKeyEntry) -> String {
        if entry.isRefreshing {
            return "正在刷新"
        }

        switch entry.snapshotFreshness {
        case .fresh:
            return "数据已刷新"
        case .stale:
            if let lastFailureKind = entry.lastFailureKind {
                return lastFailureKind.stateTextWhenCached
            }
            return "缓存数据（等待刷新）"
        case .configurationMismatch:
            return "配置已变更，未验证"
        case .empty:
            if entry.configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "未配置"
            }
            if let lastFailureKind = entry.lastFailureKind {
                return lastFailureKind.stateTextWithoutCache
            }
            return "未刷新"
        }
    }
}

extension UsageHealthState {
    var swiftUIColor: Color {
        switch self {
        case .normal:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}
