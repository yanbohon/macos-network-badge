import Combine
import Foundation

@MainActor
final class BarkNotificationManager: ObservableObject, ServiceStatusNotificationSinking {
    static let defaultServerURLText = "https://api.day.app"
    static let defaultGroup = "服务状态"
    static let defaultAvailableNotification = BarkNotificationTemplate(
        clickURLText: "",
        title: "服务状态",
        body: "{{model}} 服务恢复可用\n当前状态：{{status}}\n延迟：{{latency}} ms"
    )
    static let defaultUnavailableNotification = BarkNotificationTemplate(
        clickURLText: "",
        title: "服务状态",
        body: "{{model}} 服务不可用\n当前状态：失败\n错误：{{error}}"
    )

    enum DefaultsKey {
        static let deviceKey = "notification.bark.deviceKey"
        static let enabled = "notification.bark.enabled"
        static let serverURL = "notification.bark.serverURL"
        static let level = "notification.bark.level"
        static let criticalVolume = "notification.bark.criticalVolume"
        static let group = "notification.bark.group"
        static let iconURL = "notification.bark.iconURL"
        static let availableNotification = "notification.bark.availableNotification"
        static let unavailableNotification = "notification.bark.unavailableNotification"
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

    @Published var iconURLText: String {
        didSet {
            configurationDidChange()
            persistOptionalText(iconURLText, forKey: DefaultsKey.iconURL)
        }
    }

    @Published var unavailableNotification: BarkNotificationTemplate {
        didSet {
            configurationDidChange()
            persist(unavailableNotification, forKey: DefaultsKey.unavailableNotification)
        }
    }

    @Published var availableNotification: BarkNotificationTemplate {
        didSet {
            configurationDidChange()
            persist(availableNotification, forKey: DefaultsKey.availableNotification)
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
        iconURLText = userDefaults.string(forKey: DefaultsKey.iconURL) ?? ""
        unavailableNotification = Self.savedTemplate(
            forKey: DefaultsKey.unavailableNotification,
            in: userDefaults,
            defaultValue: Self.defaultUnavailableNotification
        )
        availableNotification = Self.savedTemplate(
            forKey: DefaultsKey.availableNotification,
            in: userDefaults,
            defaultValue: Self.defaultAvailableNotification
        )
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

    func sendTestNotification(
        for kind: BarkServiceNotificationKind,
        model: ServiceStatusModel,
        probe: ServiceStatusProbe?
    ) async {
        guard hasDeviceKey else {
            deliveryState = .failure("请先配置 Bark Key")
            return
        }
        guard let configuration = currentConfiguration else {
            deliveryState = .failure("Bark 服务地址无效")
            return
        }

        await deliver(
            message(for: previewChange(for: kind, model: model, probe: probe)),
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
            group: normalizedGroup,
            iconURL: normalizedOptionalText(iconURLText)
        )
    }

    private var normalizedGroup: String? {
        normalizedOptionalText(group)
    }

    private var notificationTitle: String {
        normalizedGroup ?? ""
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
            return message(from: unavailableNotification, for: change)
        case .available:
            return message(from: availableNotification, for: change)
        }
    }

    private func previewChange(
        for kind: BarkServiceNotificationKind,
        model: ServiceStatusModel,
        probe: ServiceStatusProbe?
    ) -> ServiceStatusChange {
        switch kind {
        case .available:
            let previewProbe: ServiceStatusProbe
            let cellKind = ServiceStatusCellKind.classify(probe)
            if let probe, cellKind == .green || cellKind == .yellow {
                previewProbe = probe
            } else {
                previewProbe = ServiceStatusProbe(
                    ts: nil,
                    ok: true,
                    latencyMS: 120,
                    error: nil
                )
            }
            return ServiceStatusChange(
                model: model,
                previousAvailability: .unavailable,
                availability: .available,
                cellKind: ServiceStatusCellKind.classify(previewProbe),
                probe: previewProbe
            )
        case .unavailable:
            let previewProbe: ServiceStatusProbe
            if let probe, ServiceStatusCellKind.classify(probe) == .red {
                previewProbe = probe
            } else {
                previewProbe = ServiceStatusProbe(
                    ts: nil,
                    ok: false,
                    latencyMS: nil,
                    error: "连接超时"
                )
            }
            return ServiceStatusChange(
                model: model,
                previousAvailability: .available,
                availability: .unavailable,
                cellKind: .red,
                probe: previewProbe
            )
        }
    }

    private func message(
        from template: BarkNotificationTemplate,
        for change: ServiceStatusChange
    ) -> BarkNotificationMessage {
        BarkNotificationMessage(
            title: render(template.title, for: change),
            body: render(template.body, for: change),
            clickURL: normalizedOptionalText(template.clickURLText)
        )
    }

    private func render(_ template: String, for change: ServiceStatusChange) -> String {
        let replacements: [(token: String, value: String?)] = [
            ("{{group}}", notificationTitle),
            ("{{model}}", change.model.rawValue),
            ("{{status}}", statusText(for: change.cellKind)),
            ("{{latency}}", change.probe.latencyMS.map(String.init)),
            ("{{error}}", normalizedOptionalText(change.probe.error ?? "")),
        ]

        return template
            .components(separatedBy: "\n")
            .filter { line in
                !replacements.contains { replacement in
                    replacement.value == nil && line.contains(replacement.token)
                }
            }
            .map { line in
                replacements.reduce(line) { rendered, replacement in
                    rendered.replacingOccurrences(
                        of: replacement.token,
                        with: replacement.value ?? ""
                    )
                }
            }
            .joined(separator: "\n")
    }

    private func statusText(for cellKind: ServiceStatusCellKind) -> String {
        switch cellKind {
        case .green:
            return "正常"
        case .yellow:
            return "高延迟"
        case .red:
            return "失败"
        case .gray:
            return "缺少数据"
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

    private func persist(_ template: BarkNotificationTemplate, forKey key: String) {
        guard let data = try? JSONEncoder().encode(template) else { return }
        userDefaults.set(data, forKey: key)
    }

    private static func savedTemplate(
        forKey key: String,
        in userDefaults: UserDefaults,
        defaultValue: BarkNotificationTemplate
    ) -> BarkNotificationTemplate {
        guard
            let data = userDefaults.data(forKey: key),
            let template = try? JSONDecoder().decode(BarkNotificationTemplate.self, from: data)
        else {
            return defaultValue
        }
        return template
    }
}
