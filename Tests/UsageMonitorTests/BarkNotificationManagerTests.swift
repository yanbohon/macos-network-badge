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
        manager.testContent = "保留的测试内容"

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
        XCTAssertEqual(restored.testContent, "保留的测试内容")
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
                    title: "gpt-5.6-sol 服务不可用",
                    body: "当前状态：失败\n错误：timeout"
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
                title: "gpt-5.5 服务恢复可用",
                body: "当前状态：高延迟\n延迟：3500 ms"
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

    func testSendingTestNotificationReportsSuccess() async {
        let sender = RecordingBarkNotificationSender()
        let manager = BarkNotificationManager(
            userDefaults: Self.makeDefaults(),
            client: sender
        )
        manager.deviceKey = "device-key"

        await manager.sendTestNotification()

        let deliveries = await sender.deliveries()
        XCTAssertEqual(deliveries.map(\.message), [
            BarkNotificationMessage(
                title: "用量监控 Bark 通知测试",
                body: "Bark 通知配置成功"
            ),
        ])
        XCTAssertEqual(manager.deliveryState, .success("测试通知已发送"))
    }

    func testSendingTestNotificationUsesCustomContent() async {
        let sender = RecordingBarkNotificationSender()
        let manager = BarkNotificationManager(
            userDefaults: Self.makeDefaults(),
            client: sender
        )
        manager.deviceKey = "device-key"
        manager.testContent = "自定义 Bark 测试内容"

        await manager.sendTestNotification()

        let deliveries = await sender.deliveries()
        XCTAssertEqual(deliveries.map(\.message), [
            BarkNotificationMessage(
                title: "用量监控 Bark 通知测试",
                body: "自定义 Bark 测试内容"
            ),
        ])
    }

    func testEditingConfigurationClearsPreviousDeliveryResult() async {
        let manager = BarkNotificationManager(
            userDefaults: Self.makeDefaults(),
            client: RecordingBarkNotificationSender()
        )
        manager.deviceKey = "device-key"
        await manager.sendTestNotification()
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
