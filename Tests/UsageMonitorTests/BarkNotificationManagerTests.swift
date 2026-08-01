import Foundation
import XCTest
@testable import UsageMonitor

@MainActor
final class BarkNotificationManagerTests: XCTestCase {
    func testNotificationCannotStayEnabledWithoutKey() {
        let manager = BarkNotificationManager(
            userDefaults: Self.makeDefaults(),
            client: RecordingBarkNotificationSender()
        )

        manager.isEnabled = true
        XCTAssertFalse(manager.isEnabled)

        manager.deviceKey = " device-key "
        manager.isEnabled = true
        XCTAssertTrue(manager.isEnabled)

        manager.deviceKey = "  "
        XCTAssertFalse(manager.isEnabled)
    }

    func testRequestParametersPersistAcrossManagerInstances() {
        let defaults = Self.makeDefaults()
        let manager = BarkNotificationManager(
            userDefaults: defaults,
            client: RecordingBarkNotificationSender()
        )
        manager.deviceKey = "device-key"
        manager.isEnabled = true
        manager.serverURLText = "https://push.example.com/base"
        manager.level = .critical
        manager.criticalVolume = 8
        manager.group = "模型监控"
        manager.iconURLText = "https://example.com/icon.png"
        manager.availableNotification = BarkNotificationTemplate(
            clickURLText: "https://status.example.com/recovery",
            title: "恢复标题",
            body: "恢复内容"
        )
        manager.unavailableNotification = BarkNotificationTemplate(
            clickURLText: "https://status.example.com/outage",
            title: "中断标题",
            body: "中断内容"
        )

        let restored = BarkNotificationManager(
            userDefaults: defaults,
            client: RecordingBarkNotificationSender()
        )

        XCTAssertEqual(restored.deviceKey, "device-key")
        XCTAssertTrue(restored.isEnabled)
        XCTAssertEqual(restored.serverURLText, "https://push.example.com/base")
        XCTAssertEqual(restored.level, .critical)
        XCTAssertEqual(restored.criticalVolume, 8)
        XCTAssertEqual(restored.group, "模型监控")
        XCTAssertEqual(restored.iconURLText, "https://example.com/icon.png")
        XCTAssertEqual(restored.availableNotification, manager.availableNotification)
        XCTAssertEqual(restored.unavailableNotification, manager.unavailableNotification)
    }

    func testClearedDefaultGroupRemainsEmptyAfterRestart() {
        let defaults = Self.makeDefaults()
        let manager = BarkNotificationManager(
            userDefaults: defaults,
            client: RecordingBarkNotificationSender()
        )
        XCTAssertEqual(manager.group, "服务状态")

        manager.group = ""

        let restored = BarkNotificationManager(
            userDefaults: defaults,
            client: RecordingBarkNotificationSender()
        )
        XCTAssertEqual(restored.group, "")
    }

    func testUnavailableStatusChangeSendsBarkNotificationWithCurrentConfiguration() async {
        let sender = RecordingBarkNotificationSender()
        let manager = BarkNotificationManager(
            userDefaults: Self.makeDefaults(),
            client: sender
        )
        manager.deviceKey = " device-key "
        manager.serverURLText = " https://push.example.com/base/ "
        manager.level = .critical
        manager.criticalVolume = 8
        manager.group = "模型监控"
        manager.iconURLText = "https://example.com/icon.png"
        manager.unavailableNotification = BarkNotificationTemplate(
            clickURLText: " https://status.example.com/incidents/42 ",
            title: "模型服务中断",
            body: "{{model}} 已中断\n错误：{{error}}"
        )
        manager.isEnabled = true

        manager.serviceStatusDidChange(
            ServiceStatusChange(
                model: .gpt56Sol,
                previousAvailability: .available,
                availability: .unavailable,
                cellKind: .red,
                probe: ServiceStatusProbe(
                    ts: 11,
                    ok: false,
                    latencyMS: nil,
                    error: "timeout"
                )
            )
        )

        while await sender.deliveries().isEmpty {
            await Task.yield()
        }

        let deliveries = await sender.deliveries()
        XCTAssertEqual(deliveries, [
            RecordedBarkDelivery(
                message: BarkNotificationMessage(
                    title: "模型服务中断",
                    body: "gpt-5.6-sol 已中断\n错误：timeout",
                    clickURL: "https://status.example.com/incidents/42"
                ),
                configuration: BarkNotificationConfiguration(
                    serverURL: URL(string: "https://push.example.com/base")!,
                    deviceKey: "device-key",
                    level: .critical,
                    volume: 8,
                    group: "模型监控",
                    iconURL: "https://example.com/icon.png"
                )
            ),
        ])
    }

    func testRecoveryToYellowSendsAvailableNotification() async {
        let sender = RecordingBarkNotificationSender()
        let manager = BarkNotificationManager(
            userDefaults: Self.makeDefaults(),
            client: sender
        )
        manager.deviceKey = "device-key"
        manager.availableNotification = BarkNotificationTemplate(
            clickURLText: "https://status.example.com",
            title: "模型服务恢复",
            body: "{{model}} 已恢复\n状态：{{status}}\n耗时：{{latency}} ms"
        )
        manager.isEnabled = true

        manager.serviceStatusDidChange(
            ServiceStatusChange(
                model: .gpt55,
                previousAvailability: .unavailable,
                availability: .available,
                cellKind: .yellow,
                probe: ServiceStatusProbe(
                    ts: 12,
                    ok: true,
                    latencyMS: 3_500,
                    error: nil
                )
            )
        )

        while await sender.deliveries().isEmpty {
            await Task.yield()
        }
        let deliveries = await sender.deliveries()
        XCTAssertEqual(deliveries.map(\.message), [
            BarkNotificationMessage(
                title: "模型服务恢复",
                body: "gpt-5.5 已恢复\n状态：高延迟\n耗时：3500 ms",
                clickURL: "https://status.example.com"
            ),
        ])
    }

    func testDefaultUnavailableNotificationOmitsMissingErrorLine() async {
        let sender = RecordingBarkNotificationSender()
        let manager = BarkNotificationManager(
            userDefaults: Self.makeDefaults(),
            client: sender
        )
        manager.deviceKey = "device-key"
        manager.isEnabled = true

        manager.serviceStatusDidChange(
            ServiceStatusChange(
                model: .gpt55,
                previousAvailability: .available,
                availability: .unavailable,
                cellKind: .red,
                probe: ServiceStatusProbe(
                    ts: 14,
                    ok: false,
                    latencyMS: nil,
                    error: nil
                )
            )
        )

        while await sender.deliveries().isEmpty {
            await Task.yield()
        }
        let deliveries = await sender.deliveries()
        XCTAssertEqual(deliveries.map(\.message), [
            BarkNotificationMessage(
                title: "服务状态",
                body: "gpt-5.5 服务不可用\n当前状态：失败"
            ),
        ])
    }

    func testDisabledNotificationDoesNotSendStatusChange() async {
        let sender = RecordingBarkNotificationSender()
        let manager = BarkNotificationManager(
            userDefaults: Self.makeDefaults(),
            client: sender
        )
        manager.deviceKey = "device-key"

        manager.serviceStatusDidChange(
            ServiceStatusChange(
                model: .gpt55,
                previousAvailability: .available,
                availability: .unavailable,
                cellKind: .red,
                probe: ServiceStatusProbe(ts: 12, ok: false, latencyMS: nil, error: nil)
            )
        )

        let deliveries = await sender.deliveries()
        XCTAssertEqual(deliveries, [])
    }

    func testEnabledNotificationReportsInvalidServerWithoutSending() async {
        let sender = RecordingBarkNotificationSender()
        let manager = BarkNotificationManager(
            userDefaults: Self.makeDefaults(),
            client: sender
        )
        manager.deviceKey = "device-key"
        manager.isEnabled = true
        manager.serverURLText = "not-a-url"

        manager.serviceStatusDidChange(
            ServiceStatusChange(
                model: .gpt55,
                previousAvailability: .available,
                availability: .unavailable,
                cellKind: .red,
                probe: ServiceStatusProbe(ts: 12, ok: false, latencyMS: nil, error: nil)
            )
        )

        let deliveries = await sender.deliveries()
        XCTAssertEqual(deliveries, [])
        XCTAssertEqual(manager.deliveryState, .failure("Bark 服务地址无效"))
    }

    func testSendingAvailableNotificationUsesFinalConfiguredMessage() async {
        let sender = RecordingBarkNotificationSender()
        let manager = BarkNotificationManager(
            userDefaults: Self.makeDefaults(),
            client: sender
        )
        manager.deviceKey = "device-key"
        manager.availableNotification = BarkNotificationTemplate(
            clickURLText: "https://status.example.com/recovered",
            title: "服务恢复",
            body: "{{model}}：{{status}}（{{latency}} ms）"
        )

        await manager.sendTestNotification(
            for: .available,
            model: .gpt55,
            probe: ServiceStatusProbe(
                ts: 13,
                ok: true,
                latencyMS: 3_500,
                error: nil
            )
        )

        let deliveries = await sender.deliveries()
        XCTAssertEqual(deliveries.map(\.message), [
            BarkNotificationMessage(
                title: "服务恢复",
                body: "gpt-5.5：高延迟（3500 ms）",
                clickURL: "https://status.example.com/recovered"
            ),
        ])
        XCTAssertEqual(manager.deliveryState, .success("测试通知已发送"))
    }

    func testSendingUnavailableNotificationUsesFinalConfiguredMessage() async {
        let sender = RecordingBarkNotificationSender()
        let manager = BarkNotificationManager(
            userDefaults: Self.makeDefaults(),
            client: sender
        )
        manager.deviceKey = "device-key"
        manager.unavailableNotification = BarkNotificationTemplate(
            clickURLText: "https://status.example.com/outage",
            title: "服务中断",
            body: "{{model}}：{{status}}\n{{error}}"
        )

        await manager.sendTestNotification(
            for: .unavailable,
            model: .gpt56Terra,
            probe: nil
        )

        let deliveries = await sender.deliveries()
        XCTAssertEqual(deliveries.map(\.message), [
            BarkNotificationMessage(
                title: "服务中断",
                body: "gpt-5.6-terra：失败\n连接超时",
                clickURL: "https://status.example.com/outage"
            ),
        ])
    }

    func testEditingConfigurationClearsPreviousDeliveryResult() async {
        let manager = BarkNotificationManager(
            userDefaults: Self.makeDefaults(),
            client: RecordingBarkNotificationSender()
        )
        manager.deviceKey = "device-key"
        await manager.sendTestNotification(
            for: .available,
            model: .gpt56Sol,
            probe: nil
        )
        XCTAssertEqual(manager.deliveryState, .success("测试通知已发送"))

        manager.deviceKey = "new-device-key"

        XCTAssertEqual(manager.deliveryState, .idle)
    }

    private static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "BarkNotificationManagerTests.\(UUID().uuidString)")!
    }
}

struct RecordedBarkDelivery: Equatable {
    let message: BarkNotificationMessage
    let configuration: BarkNotificationConfiguration
}

actor RecordingBarkNotificationSender: BarkNotificationSending {
    private var recordedDeliveries: [RecordedBarkDelivery] = []

    func send(
        _ message: BarkNotificationMessage,
        configuration: BarkNotificationConfiguration
    ) async throws {
        recordedDeliveries.append(
            RecordedBarkDelivery(message: message, configuration: configuration)
        )
    }

    func deliveries() -> [RecordedBarkDelivery] {
        recordedDeliveries
    }
}
