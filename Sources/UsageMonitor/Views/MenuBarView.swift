import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: UsageSnapshotMonitor
    @ObservedObject var settingsWindowController: SettingsWindowController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

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
        .frame(width: 420)
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
