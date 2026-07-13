import Foundation

enum ServiceStatusModel: String, CaseIterable, Identifiable {
    case gpt56Sol = "gpt-5.6-sol"
    case gpt56Terra = "gpt-5.6-terra"
    case gpt56Luna = "gpt-5.6-luna"
    case gpt55 = "gpt-5.5"

    var id: String { rawValue }
}

enum ServiceStatusMonitorError: Error, Equatable {
    case missingModel(String)

    var userMessage: String {
        switch self {
        case let .missingModel(model):
            return "未找到 \(model) 状态"
        }
    }
}

@MainActor
final class ServiceStatusMonitor: ObservableObject {
    private enum DefaultsKey {
        static let menuBarModel = "serviceStatus.menuBarModel"
    }

    static let supportedModels = ServiceStatusModel.allCases
    static let monitoredModels = supportedModels.map(\.rawValue)
    static let primaryModel = ServiceStatusModel.gpt56Sol
    static let defaultMenuBarModel = primaryModel
    static let popoverTimelineCellCount = 60
    static let refreshInterval: TimeInterval = 60

    @Published private(set) var response: ServiceStatusResponse?
    @Published private(set) var rawJSONText: String?
    @Published private(set) var lastSuccessfulRefresh: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published var menuBarModel: ServiceStatusModel {
        didSet {
            userDefaults.set(menuBarModel.rawValue, forKey: DefaultsKey.menuBarModel)
        }
    }

    private let userDefaults: UserDefaults
    private let client: ServiceStatusFetching
    private let timerFactory: RefreshTimerFactory
    private let now: () -> Date
    private var refreshTimer: RefreshTimer?
    private var refreshTask: Task<StatusAPIResult, Error>?
    private var isTimerRefreshInFlight = false
    private(set) var activeTimerRefreshCount = 0
    private(set) var peakTimerRefreshCount = 0
    private var hasStarted = false

    init(
        userDefaults: UserDefaults = .standard,
        client: ServiceStatusFetching = StatusAPIClient(),
        timerFactory: RefreshTimerFactory = FoundationRefreshTimerFactory(),
        now: @escaping () -> Date = Date.init
    ) {
        self.userDefaults = userDefaults
        self.client = client
        self.timerFactory = timerFactory
        self.now = now
        menuBarModel = userDefaults.string(forKey: DefaultsKey.menuBarModel)
            .flatMap(ServiceStatusModel.init(rawValue:))
            ?? Self.defaultMenuBarModel
    }

    var selectedService: ServiceStatusService? {
        response?.service(model: menuBarModel.rawValue)
    }

    var displayCells: [ServiceStatusDisplayCell] {
        selectedService?.latestDisplayCells(count: 8)
            ?? Array(repeating: ServiceStatusDisplayCell(kind: .gray, probe: nil), count: 8)
    }

    var timelineRows: [ServiceStatusTimelineRow] {
        if let response {
            return response.timelineRows(
                for: Self.monitoredModels,
                count: Self.popoverTimelineCellCount
            )
        }

        return Self.monitoredModels.map {
            ServiceStatusTimelineRow(
                model: $0,
                service: nil,
                count: Self.popoverTimelineCellCount
            )
        }
    }

    var isStaleAfterFailure: Bool {
        lastError != nil && selectedService != nil
    }

    var currentStatusText: String {
        if isStaleAfterFailure {
            return "刷新失败（显示上次成功状态）"
        }
        if lastError != nil && selectedService == nil {
            return "刷新失败"
        }
        guard let probe = selectedService?.last else {
            return "缺少数据"
        }
        switch ServiceStatusCellKind.classify(probe) {
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

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        scheduleTimer()
        Task { [weak self] in
            await self?.refreshOnLaunch()
        }
    }

    func refreshNow() async {
        do {
            try await performRefresh()
        } catch {
            // Published state already contains the user-facing failure.
        }
    }

    private func refreshOnLaunch() async {
        do {
            try await performRefresh()
        } catch {
            // Launch failures are reflected in published state.
        }
    }

    private func refreshFromTimer() async {
        guard !isTimerRefreshInFlight else { return }
        isTimerRefreshInFlight = true
        activeTimerRefreshCount += 1
        peakTimerRefreshCount = max(peakTimerRefreshCount, activeTimerRefreshCount)
        defer {
            activeTimerRefreshCount -= 1
            isTimerRefreshInFlight = false
        }
        do {
            try await performRefresh()
        } catch {
            // Timer failures are reflected in published state.
        }
    }

    private func performRefresh() async throws {
        if let refreshTask {
            _ = try await refreshTask.value
            return
        }

        let task: Task<StatusAPIResult, Error> = Task { [client] in
            try await client.fetchStatus()
        }
        refreshTask = task
        isRefreshing = true

        defer {
            refreshTask = nil
            isRefreshing = false
        }

        do {
            let result = try await task.value
            try applySuccessfulRefresh(result)
        } catch {
            applyRefreshFailure(error)
            throw error
        }
    }

    private func applySuccessfulRefresh(_ result: StatusAPIResult) throws {
        guard result.response.service(model: Self.primaryModel.rawValue) != nil else {
            let error = ServiceStatusMonitorError.missingModel(Self.primaryModel.rawValue)
            applyRefreshFailure(error)
            throw error
        }

        response = result.response
        rawJSONText = result.prettyRawJSON
        lastSuccessfulRefresh = now()
        lastError = nil
    }

    private func applyRefreshFailure(_ error: Error) {
        if let error = error as? StatusAPIClientError {
            lastError = error.userMessage
        } else if let error = error as? ServiceStatusMonitorError {
            lastError = error.userMessage
        } else {
            lastError = "状态请求失败"
        }
    }

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        refreshTimer = timerFactory.schedule(interval: Self.refreshInterval) { [weak self] in
            guard let monitor = self else { return }
            Task { @MainActor in
                await monitor.refreshFromTimer()
            }
        }
    }
}
