import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: SubscriptionMonitor
    @ObservedObject var settingsWindowController: SettingsWindowController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if monitor.activeSubscriptions.isEmpty {
                Text(emptyStateText)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(monitor.activeSubscriptions) { subscription in
                        subscriptionRow(subscription)
                    }
                }
            }

            if monitor.catalog.inactiveCount > 0 {
                Text("另有 \(monitor.catalog.inactiveCount) 个非 active 套餐未显示")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let error = monitor.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(monitor.email.isEmpty ? "用量监控" : monitor.email)
                    .font(.headline)
                Text("余额 \(UsageFormatters.currency(monitor.user?.balance ?? 0))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(refreshText)
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        switch monitor.authState {
        case .notConfigured:
            return "未配置"
        case .needsLogin, .ready:
            return "未登录"
        case .authenticated:
            return "无套餐"
        case .error:
            return monitor.lastError == nil ? "刷新失败" : "保留上次成功数据"
        }
    }

    private func subscriptionRow(_ subscription: Sub2APISubscription) -> some View {
        Button {
            monitor.setSelectedSubscription(subscription.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: monitor.selectedSubscriptionID == subscription.id ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(monitor.selectedSubscriptionID == subscription.id ? .accentColor : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(subscription.group.name)
                            .font(.subheadline.bold())
                        Text(subscription.group.platform)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(UsageFormatters.dailyUsageText(
                            used: subscription.usedTodayUSD,
                            limit: subscription.group.dailyLimitUSD
                        ))
                        .font(.subheadline.monospacedDigit())
                    }

                    HStack {
                        Text("剩余 \(UsageFormatters.remainingText(used: subscription.usedTodayUSD, limit: subscription.group.dailyLimitUSD))")
                        Text(UsageFormatters.percentageText(
                            used: subscription.usedTodayUSD,
                            limit: subscription.group.dailyLimitUSD
                        ))
                        Text("周 \(UsageFormatters.currency(subscription.usedWeekUSD))")
                        Text("月 \(UsageFormatters.currency(subscription.usedMonthUSD))")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Text(UsageFormatters.expiryText(subscription.expiresAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(subscription.healthState.swiftUIColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private extension Sub2APISubscription {
    var healthState: UsageHealthState {
        UsageFormatters.healthState(used: usedTodayUSD, limit: group.dailyLimitUSD)
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
