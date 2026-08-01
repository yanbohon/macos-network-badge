import Combine
import Foundation

@MainActor
final class BarkNotificationManager: ObservableObject, ServiceStatusNotificationSinking {
    static let defaultServerURLText = "https://api.day.app"
    static let defaultGroup = "服务状态"

    enum DefaultsKey {
        static let deviceKey = "notification.bark.deviceKey"
        static let enabled = "notification.bark.enabled"
        static let serverURL = "notification.bark.serverURL"
        static let level = "notification.bark.level"
        static let criticalVolume = "notification.bark.criticalVolume"
        static let group = "notification.bark.group"
        static let sound = "notification.bark.sound"
        static let iconURL = "notification.bark.iconURL"
        static let clickURL = "notification.bark.clickURL"
    }

    @Published var deviceKey: String {
        didSet {
            configurationDidChange()
            let trimmedKey = deviceKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedKey.isEmpty {
                userDefaults.removeObject(forKey: DefaultsKey.deviceKey)
                if isEnabled {
                    isEnabled = false
                }
            } else {
                userDefaults.set(deviceKey, forKey: DefaultsKey.deviceKey)
            }
        }
    }

    @Published var isEnabled: Bool {
        didSet {
            configurationDidChange()
            if isEnabled && !hasDeviceKey {
                isEnabled = false
            }
            userDefaults.set(isEnabled, forKey: DefaultsKey.enabled)
        }
    }

    @Published var serverURLText: String {
        didSet {
            configurationDidChange()
            userDefaults.set(serverURLText, forKey: DefaultsKey.serverURL)
        }
    }

    @Published var level: BarkNotificationLevel {
        didSet {
            configurationDidChange()
            userDefaults.set(level.rawValue, forKey: DefaultsKey.level)
        }
    }

    @Published var criticalVolume: Int {
        didSet {
            configurationDidChange()
            let clampedVolume = min(max(criticalVolume, 0), 10)
            if criticalVolume != clampedVolume {
                criticalVolume = clampedVolume
            }
            userDefaults.set(criticalVolume, forKey: DefaultsKey.criticalVolume)
        }
    }

    @Published var group: String {
        didSet {
            configurationDidChange()
            userDefaults.set(group, forKey: DefaultsKey.group)
        }
    }

    @Published var sound: String {
        didSet {
            configurationDidChange()
            persistOptionalText(sound, forKey: DefaultsKey.sound)
        }
    }

    @Published var iconURLText: String {
        didSet {
            configurationDidChange()
            persistOptionalText(iconURLText, forKey: DefaultsKey.iconURL)
        }
    }

    @Published var clickURLText: String {
        didSet {
            configurationDidChange()
            persistOptionalText(clickURLText, forKey: DefaultsKey.clickURL)
        }
    }

    @Published private(set) var deliveryState: BarkNotificationDeliveryState = .idle

    var hasDeviceKey: Bool {
        !deviceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let userDefaults: UserDefaults
    private let client: BarkNotificationSending

    init(
        userDefaults: UserDefaults = .standard,
        client: BarkNotificationSending = BarkNotificationClient()
    ) {
        let savedKey = userDefaults.string(forKey: DefaultsKey.deviceKey) ?? ""
        let savedVolume = userDefaults.object(forKey: DefaultsKey.criticalVolume) as? Int ?? 5
        self.userDefaults = userDefaults
        self.client = client
        deviceKey = savedKey
        isEnabled = userDefaults.bool(forKey: DefaultsKey.enabled)
            && !savedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        serverURLText = userDefaults.string(forKey: DefaultsKey.serverURL)
            ?? Self.defaultServerURLText
        level = userDefaults.string(forKey: DefaultsKey.level)
            .flatMap(BarkNotificationLevel.init(rawValue:))
            ?? .active
        criticalVolume = min(max(savedVolume, 0), 10)
        group = userDefaults.string(forKey: DefaultsKey.group) ?? Self.defaultGroup
        sound = userDefaults.string(forKey: DefaultsKey.sound) ?? ""
        iconURLText = userDefaults.string(forKey: DefaultsKey.iconURL) ?? ""
        clickURLText = userDefaults.string(forKey: DefaultsKey.clickURL) ?? ""
    }

    func serviceStatusDidChange(_ change: ServiceStatusChange) {
        guard isEnabled else { return }
        guard let configuration = currentConfiguration else {
            deliveryState = .failure("Bark 服务地址无效")
            return
        }
        let message = message(for: change)
        Task { [weak self] in
            await self?.deliver(
                message,
                configuration: configuration,
                successMessage: "状态通知已发送"
            )
        }
    }

    func sendTestNotification() async {
        guard hasDeviceKey else {
            deliveryState = .failure("请先配置 Bark Key")
            return
        }
        guard let configuration = currentConfiguration else {
            deliveryState = .failure("Bark 服务地址无效")
            return
        }

        await deliver(
            BarkNotificationMessage(
                title: "用量监控 Bark 通知测试",
                body: "Bark 通知配置成功"
            ),
            configuration: configuration,
            successMessage: "测试通知已发送"
        )
    }

    private func deliver(
        _ message: BarkNotificationMessage,
        configuration: BarkNotificationConfiguration,
        successMessage: String
    ) async {
        deliveryState = .sending
        do {
            try await client.send(message, configuration: configuration)
            deliveryState = .success(successMessage)
        } catch let error as BarkNotificationClientError {
            deliveryState = .failure(error.userMessage)
        } catch {
            deliveryState = .failure("Bark 请求失败")
        }
    }

    private var currentConfiguration: BarkNotificationConfiguration? {
        let trimmedKey = deviceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, let serverURL = normalizedServerURL else { return nil }
        return BarkNotificationConfiguration(
            serverURL: serverURL,
            deviceKey: trimmedKey,
            level: level,
            volume: level == .critical ? criticalVolume : nil,
            group: normalizedOptionalText(group),
            sound: normalizedOptionalText(sound),
            iconURL: normalizedOptionalText(iconURLText),
            clickURL: normalizedOptionalText(clickURLText)
        )
    }

    private var normalizedServerURL: URL? {
        var text = serverURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") {
            text.removeLast()
        }
        guard
            let url = URL(string: text),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else {
            return nil
        }
        return url
    }

    private func message(for change: ServiceStatusChange) -> BarkNotificationMessage {
        switch change.availability {
        case .unavailable:
            var lines = ["当前状态：失败"]
            if let error = normalizedOptionalText(change.probe.error ?? "") {
                lines.append("错误：\(error)")
            }
            return BarkNotificationMessage(
                title: "\(change.model.rawValue) 服务不可用",
                body: lines.joined(separator: "\n")
            )
        case .available:
            let status = change.cellKind == .yellow ? "高延迟" : "正常"
            var lines = ["当前状态：\(status)"]
            if let latencyMS = change.probe.latencyMS {
                lines.append("延迟：\(latencyMS) ms")
            }
            return BarkNotificationMessage(
                title: "\(change.model.rawValue) 服务恢复可用",
                body: lines.joined(separator: "\n")
            )
        }
    }

    private func normalizedOptionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func configurationDidChange() {
        deliveryState = .idle
    }

    private func persistOptionalText(_ value: String, forKey key: String) {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userDefaults.removeObject(forKey: key)
        } else {
            userDefaults.set(value, forKey: key)
        }
    }
}
