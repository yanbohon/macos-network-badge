import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: UsageSnapshotMonitor
    @ObservedObject var serviceStatusMonitor: ServiceStatusMonitor
    @ObservedObject var settingsWindowController: SettingsWindowController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            serviceStatusSection

            if let snapshot = monitor.snapshot, monitor.canShowSnapshotData {
                usageSnapshot(snapshot)
            } else {
                Text(emptyStateText)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !monitor.alertMessages.isEmpty {
                alertSection
            }
        }
        .padding(16)
        .frame(width: 440)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("用量监控")
                    .font(.headline)
                Text("余额 \(monitor.balanceText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(refreshText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(monitor.statusLineText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let detail = monitor.statusDetailText {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Button {
                Task { await monitor.refreshNow() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("手动刷新")

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
        if let date = monitor.lastSuccessfulRefresh {
            return "上次成功刷新 \(date.formatted(date: .omitted, time: .shortened))"
        }
        return "尚未成功刷新"
    }

    private var emptyStateText: String {
        monitor.statusLineText
    }

    private var alertSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("提醒")
                .font(.caption.bold())
            ForEach(Array(monitor.alertMessages.enumerated()), id: \.offset) { _, message in
                Text(message)
                    .font(.caption)
                    .foregroundColor(alertColor)
            }
        }
    }

    private var alertColor: Color {
        if let alert = monitor.thresholdAlertState,
           alert.kinds.contains(.dailyUsage95) || alert.kinds.contains(.subscriptionExpired) {
            return .red
        }
        return .orange
    }

    private var serviceStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("服务状态")
                    .font(.caption.bold())
                Spacer()
                Text(ServiceStatusMonitor.targetModel)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Text(serviceStatusMonitor.currentStatusText)
                    .font(.subheadline.bold())
                    .foregroundColor(serviceStatusColor)
                Spacer()
                serviceStatusCells(serviceStatusMonitor.displayCells)
                    .opacity(serviceStatusMonitor.isStaleAfterFailure ? 0.55 : 1)
            }

            if let detail = serviceStatusMonitor.lastError {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            serviceStatusMetadata

            if let service = serviceStatusMonitor.selectedService {
                serviceHistoryList(service.history.suffix(8))
            }

            if let rawJSONText = serviceStatusMonitor.rawJSONText {
                DisclosureGroup("原始响应 JSON") {
                    ScrollView {
                        Text(rawJSONText)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    private var serviceStatusColor: Color {
        if serviceStatusMonitor.lastError != nil && serviceStatusMonitor.selectedService == nil {
            return .orange
        }
        switch ServiceStatusCellKind.classify(serviceStatusMonitor.selectedService?.last) {
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

    private var serviceStatusMetadata: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let service = serviceStatusMonitor.selectedService {
                metricRow(title: "可用率", value: service.uptimePct.map { String(format: "%.2f%%", $0) } ?? "--")
                metricRow(title: "最近探测", value: formattedProbeTime(service.last?.ts))
                metricRow(title: "最近延迟", value: formattedLatency(service.last?.latencyMS))
                if let error = service.last?.error, !error.isEmpty {
                    metricRow(title: "最近错误", value: error)
                }
            }

            if let generatedAt = serviceStatusMonitor.response?.generatedAt {
                metricRow(title: "接口生成", value: formattedTimestamp(generatedAt))
            }
            if let refreshedAt = serviceStatusMonitor.lastSuccessfulRefresh {
                metricRow(title: "状态刷新", value: refreshedAt.formatted(date: .omitted, time: .standard))
            }
        }
    }

    private func serviceStatusCells(_ cells: [ServiceStatusDisplayCell]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(cell.kind.swiftUIColor)
                    .frame(width: 8, height: 10)
                    .opacity(cell.kind == .gray ? 0.45 : 1)
                    .help(cell.helpText)
            }
        }
        .accessibilityLabel("gpt-5.5 最近八次状态")
    }

    private func serviceHistoryList(_ history: ArraySlice<ServiceStatusProbe>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("最近记录")
                .font(.caption.bold())
            if history.isEmpty {
                Text("暂无历史状态")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(history.enumerated()), id: \.offset) { _, probe in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(ServiceStatusCellKind.classify(probe).swiftUIColor)
                            .frame(width: 7, height: 7)
                        Text(formattedProbeTime(probe.ts))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                        Text(formattedLatency(probe.latencyMS))
                            .font(.caption.monospacedDigit())
                        if let error = probe.error, !error.isEmpty {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func formattedProbeTime(_ timestamp: TimeInterval?) -> String {
        guard let timestamp else { return "--" }
        return formattedTimestamp(timestamp)
    }

    private func formattedTimestamp(_ timestamp: TimeInterval) -> String {
        Date(timeIntervalSince1970: timestamp).formatted(date: .omitted, time: .standard)
    }

    private func formattedLatency(_ latencyMS: Int?) -> String {
        guard let latencyMS else { return "--" }
        return "\(latencyMS) ms"
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
