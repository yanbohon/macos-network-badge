import Foundation

enum CursorAccountKind: String, Codable, CaseIterable, Identifiable {
    case personal
    case team

    var id: String { rawValue }

    var settingsTitle: String {
        switch self {
        case .personal:
            return "个人"
        case .team:
            return "Team"
        }
    }
}

struct CursorAccountRecord: Equatable, Identifiable, Codable {
    static let defaultSymbolName = "sparkles"
    static let defaultRingColorHex = "#38BDF8"
    static let ringColorPalette = [
        "#38BDF8",
        "#A78BFA",
        "#34D399",
        "#F472B6",
        "#FBBF24",
        "#FB7185",
    ]

    var id: String
    var kind: CursorAccountKind
    var email: String
    var accessToken: String
    var refreshToken: String
    var autoPercentUsed: Double?
    var apiPercentUsed: Double?
    var membershipType: String?
    var billingCycleEnd: Date?
    var sandPercentUsed: Double?
    var sandHasAllowance: Bool
    var sandPlanLabel: String?
    var sandResetAt: Date?
    var lastSuccessfulRefresh: Date?
    var lastError: String?
    var showsInMenuBar: Bool
    var symbolName: String
    var ringColorHex: String

    var displayName: String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未验证账号" : trimmed
    }

    var hasAccessToken: Bool {
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var cardSession: String {
        accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var membershipDisplayName: String? {
        CursorUsageSummary.membershipDisplayName(from: membershipType)
    }

    var membershipColorHex: String? {
        CursorUsageSummary.membershipColorHex(from: membershipType)
    }

    var billingCycleEndText: String? {
        CursorUsageSummary.billingCycleEndText(from: billingCycleEnd)
    }

    var autoUsageText: String {
        percentText(autoPercentUsed)
    }

    var apiUsageText: String {
        percentText(apiPercentUsed)
    }

    var sandUsageText: String {
        percentText(sandPercentUsed)
    }

    var sandDisplayName: String {
        let label = sandPlanLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if label.isEmpty { return "Grok" }
        if label.localizedCaseInsensitiveContains("grok") { return "Grok" }
        return label
    }

    var showsSandRing: Bool {
        sandHasAllowance && sandPercentUsed != nil
    }

    private func percentText(_ raw: Double?) -> String {
        guard let raw else { return "—" }
        return "\(CursorUsageSummary.displayPercent(from: raw))%"
    }

    init(
        id: String,
        kind: CursorAccountKind = .personal,
        email: String,
        accessToken: String,
        refreshToken: String,
        autoPercentUsed: Double? = nil,
        apiPercentUsed: Double? = nil,
        membershipType: String? = nil,
        billingCycleEnd: Date? = nil,
        sandPercentUsed: Double? = nil,
        sandHasAllowance: Bool = false,
        sandPlanLabel: String? = nil,
        sandResetAt: Date? = nil,
        lastSuccessfulRefresh: Date? = nil,
        lastError: String? = nil,
        showsInMenuBar: Bool = true,
        symbolName: String = Self.defaultSymbolName,
        ringColorHex: String = Self.defaultRingColorHex
    ) {
        self.id = id
        self.kind = kind
        self.email = email
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.autoPercentUsed = autoPercentUsed
        self.apiPercentUsed = apiPercentUsed
        self.membershipType = membershipType
        self.billingCycleEnd = billingCycleEnd
        self.sandPercentUsed = sandPercentUsed
        self.sandHasAllowance = sandHasAllowance
        self.sandPlanLabel = sandPlanLabel
        self.sandResetAt = sandResetAt
        self.lastSuccessfulRefresh = lastSuccessfulRefresh
        self.lastError = lastError
        self.showsInMenuBar = showsInMenuBar
        self.symbolName = Self.normalizedSymbolName(symbolName)
        self.ringColorHex = Self.normalizedRingColorHex(ringColorHex)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decodeIfPresent(CursorAccountKind.self, forKey: .kind) ?? .personal
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken) ?? ""
        autoPercentUsed = try container.decodeIfPresent(Double.self, forKey: .autoPercentUsed)
        apiPercentUsed = try container.decodeIfPresent(Double.self, forKey: .apiPercentUsed)
        membershipType = try container.decodeIfPresent(String.self, forKey: .membershipType)
        billingCycleEnd = try container.decodeIfPresent(Date.self, forKey: .billingCycleEnd)
        sandPercentUsed = try container.decodeIfPresent(Double.self, forKey: .sandPercentUsed)
        sandHasAllowance = try container.decodeIfPresent(Bool.self, forKey: .sandHasAllowance) ?? false
        sandPlanLabel = try container.decodeIfPresent(String.self, forKey: .sandPlanLabel)
        sandResetAt = try container.decodeIfPresent(Date.self, forKey: .sandResetAt)
        lastSuccessfulRefresh = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulRefresh)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        showsInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showsInMenuBar) ?? true
        symbolName = Self.normalizedSymbolName(
            try container.decodeIfPresent(String.self, forKey: .symbolName) ?? Self.defaultSymbolName
        )
        ringColorHex = Self.normalizedRingColorHex(
            try container.decodeIfPresent(String.self, forKey: .ringColorHex) ?? Self.defaultRingColorHex
        )
    }

    static func normalizedSymbolName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultSymbolName : trimmed
    }

    static func normalizedRingColorHex(_ hex: String) -> String {
        UsageKeyConfiguration.normalizedSymbolColorHex(hex)
    }

    func menuBarRows() -> [MenuBarKeyDisplayRow] {
        var rows = [
            MenuBarKeyDisplayRow(
                id: "\(id)-auto",
                name: "\(displayName) Auto",
                symbolName: symbolName,
                symbolColorHex: ringColorHex,
                text: autoUsageText
            ),
        ]
        if showsSandRing {
            rows.append(
                MenuBarKeyDisplayRow(
                    id: "\(id)-sand",
                    name: "\(displayName) \(sandDisplayName)",
                    symbolName: symbolName,
                    symbolColorHex: ringColorHex,
                    text: sandUsageText
                )
            )
        }
        return rows
    }

    static func nextRingColorHex(after existing: [CursorAccountRecord]) -> String {
        ringColorPalette[existing.count % ringColorPalette.count]
    }
}

@MainActor
final class CursorUsageMonitor: ObservableObject {
    enum DefaultsKey {
        static let accounts = "cursor.accounts"
        static let selectedAccountID = "cursor.selectedAccountID"
    }

    @Published private(set) var accounts: [CursorAccountRecord]
    @Published var selectedAccountID: String? {
        didSet {
            persistSelectedAccountID()
        }
    }
    @Published private(set) var isRefreshing = false

    private let userDefaults: UserDefaults
    private let client: CursorAPIClient
    private let timerFactory: RefreshTimerFactory
    private let now: () -> Date
    private var refreshTimer: RefreshTimer?
    private var refreshIntervalSeconds: Int
    private var hasStarted = false

    init(
        userDefaults: UserDefaults = .standard,
        client: CursorAPIClient = CursorAPIClient(),
        timerFactory: RefreshTimerFactory = FoundationRefreshTimerFactory(),
        now: @escaping () -> Date = Date.init,
        refreshIntervalSeconds: Int = UsageSnapshotMonitor.defaultRefreshIntervalSeconds
    ) {
        self.userDefaults = userDefaults
        self.client = client
        self.timerFactory = timerFactory
        self.now = now
        self.refreshIntervalSeconds = UsageSnapshotMonitor.allowedRefreshIntervalSeconds.contains(refreshIntervalSeconds)
            ? refreshIntervalSeconds
            : UsageSnapshotMonitor.defaultRefreshIntervalSeconds
        accounts = Self.loadAccounts(from: userDefaults)
        let storedSelection = userDefaults.string(forKey: DefaultsKey.selectedAccountID)
        if let storedSelection, accounts.contains(where: { $0.id == storedSelection }) {
            selectedAccountID = storedSelection
        } else {
            selectedAccountID = accounts.first?.id
        }
    }

    var selectedAccount: CursorAccountRecord? {
        guard let selectedAccountID else { return nil }
        return accounts.first { $0.id == selectedAccountID }
    }

    var menuBarColumns: [[MenuBarKeyDisplayRow]] {
        accounts.filter(\.showsInMenuBar).map { $0.menuBarRows() }
    }

    var menuBarKeyRows: [MenuBarKeyDisplayRow] {
        menuBarColumns.flatMap { $0 }
    }

    var selectedAccountRefreshText: String {
        refreshText(for: selectedAccount)
    }

    var selectedAutoUsageText: String {
        selectedAccount?.autoUsageText ?? "—"
    }

    func refreshText(for account: CursorAccountRecord?) -> String {
        if isRefreshing && account != nil {
            return "正在刷新"
        }
        if let date = account?.lastSuccessfulRefresh {
            return "上次成功刷新 \(date.formatted(date: .omitted, time: .shortened))"
        }
        if let error = account?.lastError, !error.isEmpty {
            return error
        }
        return "尚未成功刷新"
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        scheduleTimerIfNeeded()
        Task { await refreshAll() }
    }

    func syncRefreshInterval(_ seconds: Int) {
        let normalized = UsageSnapshotMonitor.allowedRefreshIntervalSeconds.contains(seconds)
            ? seconds
            : UsageSnapshotMonitor.defaultRefreshIntervalSeconds
        guard normalized != refreshIntervalSeconds else { return }
        refreshIntervalSeconds = normalized
        if hasStarted {
            scheduleTimerIfNeeded()
        }
    }

    @discardableResult
    func addAccount() -> String {
        let account = CursorAccountRecord(
            id: UUID().uuidString,
            email: "",
            accessToken: "",
            refreshToken: "",
            showsInMenuBar: true,
            ringColorHex: CursorAccountRecord.nextRingColorHex(after: accounts)
        )
        accounts.append(account)
        persistAccounts()
        if selectedAccountID == nil {
            selectedAccountID = account.id
        }
        return account.id
    }

    func deleteAccount(id: String) {
        accounts.removeAll { $0.id == id }
        persistAccounts()
        if selectedAccountID == id {
            selectedAccountID = accounts.first?.id
        }
    }

    func setShowsInMenuBar(id: String, shows: Bool) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        var updated = accounts
        updated[index].showsInMenuBar = shows
        accounts = updated
        persistAccounts()
    }

    func updateRingColor(id: String, hex: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        var updated = accounts
        updated[index].ringColorHex = CursorAccountRecord.normalizedRingColorHex(hex)
        accounts = updated
        persistAccounts()
    }

    func updateSymbolName(id: String, symbolName: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        var updated = accounts
        updated[index].symbolName = CursorAccountRecord.normalizedSymbolName(symbolName)
        accounts = updated
        persistAccounts()
    }

    func updateAccountKind(id: String, kind: CursorAccountKind) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        guard accounts[index].kind != kind else { return }
        var updated = accounts
        updated[index].kind = kind
        updated[index].accessToken = ""
        updated[index].refreshToken = ""
        clearUsage(in: &updated[index])
        accounts = updated
        persistAccounts()
    }

    func updateAccount(id: String, accessToken: String, refreshToken: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let isTeam = accounts[index].kind == .team
        let normalizedAccess = isTeam
            ? accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            : CursorSessionToken.normalizedAccessToken(accessToken)
        let normalizedRefresh = isTeam ? "" : refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = accounts
        let tokenChanged =
            updated[index].accessToken != normalizedAccess
            || updated[index].refreshToken != normalizedRefresh
        updated[index].accessToken = normalizedAccess
        updated[index].refreshToken = normalizedRefresh
        if tokenChanged {
            clearUsage(in: &updated[index])
        }
        accounts = updated
        persistAccounts()
    }

    func refreshSelected() async {
        await refreshAll()
    }

    func refreshAll() async {
        let ids = accounts.map(\.id)
        guard !ids.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for id in ids {
            await refreshAccountWithoutFlag(id: id)
        }
    }

    func refreshAccount(id: String) async {
        isRefreshing = true
        defer { isRefreshing = false }
        await refreshAccountWithoutFlag(id: id)
    }

    private func refreshAccountWithoutFlag(id: String) async {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        if accounts[index].kind == .team {
            await refreshTeamAccount(id: id)
            return
        }

        guard accounts[index].hasAccessToken || !accounts[index].refreshToken.isEmpty else {
            var updated = accounts
            updated[index].lastError = "请先粘贴 Access Token"
            accounts = updated
            persistAccounts()
            return
        }

        do {
            try await refreshAccountOnce(id: id, forceTokenRefresh: false)
        } catch let error as CursorAPIClientError where error.isUnauthorized {
            if !currentRefreshToken(for: id).isEmpty {
                do {
                    try await refreshAccountOnce(id: id, forceTokenRefresh: true)
                } catch {
                    recordFailure(id: id, error: error)
                }
            } else {
                recordFailure(id: id, error: error)
            }
        } catch {
            recordFailure(id: id, error: error)
        }
    }

    private func refreshTeamAccount(id: String) async {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        let cardSession = accounts[index].cardSession
        guard !cardSession.isEmpty else {
            var updated = accounts
            updated[index].lastError = "请先粘贴 Card Session"
            accounts = updated
            persistAccounts()
            return
        }

        do {
            let snapshot = try await client.fetchTeamExtractionUsage(cardSession: cardSession)
            guard let latestIndex = accounts.firstIndex(where: { $0.id == id }) else { return }
            var updated = accounts
            if let email = snapshot.email, !email.isEmpty {
                updated[latestIndex].email = email
            }
            updated[latestIndex].autoPercentUsed = snapshot.autoPercentUsed
            updated[latestIndex].apiPercentUsed = nil
            updated[latestIndex].membershipType = snapshot.membershipType
            updated[latestIndex].billingCycleEnd = nil
            updated[latestIndex].sandHasAllowance = snapshot.sandHasAllowance
            updated[latestIndex].sandPercentUsed = snapshot.sandHasAllowance ? snapshot.sandPercentUsed : nil
            updated[latestIndex].sandPlanLabel = snapshot.sandPlanLabel
            updated[latestIndex].sandResetAt = snapshot.sandResetAt
            updated[latestIndex].lastSuccessfulRefresh = now()
            updated[latestIndex].lastError = snapshot.autoPercentUsed == nil ? "响应中没有 Auto 用量" : nil
            accounts = updated
            persistAccounts()
        } catch {
            recordFailure(id: id, error: error)
        }
    }

    private func refreshAccountOnce(id: String, forceTokenRefresh: Bool) async throws {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else {
            throw CursorAPIClientError.authorizationFailure
        }

        var accessToken = accounts[index].accessToken
        var refreshToken = accounts[index].refreshToken

        if !refreshToken.isEmpty, forceTokenRefresh || CursorSessionToken.needsRefresh(accessToken, now: now()) {
            let refreshed = try await client.refreshAccessToken(refreshToken: refreshToken)
            accessToken = CursorSessionToken.normalizedAccessToken(refreshed.accessToken)
            if let nextRefresh = refreshed.refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines),
               !nextRefresh.isEmpty {
                refreshToken = nextRefresh
            }
            var refreshedAccounts = accounts
            refreshedAccounts[index].accessToken = accessToken
            refreshedAccounts[index].refreshToken = refreshToken
            accounts = refreshedAccounts
            persistAccounts()
        }

        let summary = try await client.fetchUsageSummary(accessToken: accessToken)
        guard let latestIndex = accounts.firstIndex(where: { $0.id == id }) else {
            throw CursorAPIClientError.authorizationFailure
        }
        var updated = accounts
        if let meta = try? await client.fetchUserMeta(accessToken: accessToken),
           let email = meta.email, !email.isEmpty {
            updated[latestIndex].email = email
        }

        updated[latestIndex].autoPercentUsed = summary.autoPercentUsed
        updated[latestIndex].apiPercentUsed = summary.apiPercentUsed
        updated[latestIndex].membershipType = summary.membershipType
        updated[latestIndex].billingCycleEnd = summary.billingCycleEnd
        updated[latestIndex].lastSuccessfulRefresh = now()
        updated[latestIndex].lastError = summary.autoPercentUsed == nil ? "响应中没有 Auto 用量" : nil
        accounts = updated
        persistAccounts()

        if let sand = try? await client.fetchSandUsage(accessToken: accessToken),
           let sandIndex = accounts.firstIndex(where: { $0.id == id }) {
            var sandUpdated = accounts
            sandUpdated[sandIndex].sandHasAllowance = sand.hasNonZeroIncludedLimit
            sandUpdated[sandIndex].sandPercentUsed = sand.shouldShowRing ? sand.usagePercent : nil
            sandUpdated[sandIndex].sandPlanLabel = sand.planLabel
            sandUpdated[sandIndex].sandResetAt = sand.nextReset
            accounts = sandUpdated
            persistAccounts()
        }
    }

    private func clearUsage(in account: inout CursorAccountRecord) {
        account.autoPercentUsed = nil
        account.apiPercentUsed = nil
        account.membershipType = nil
        account.billingCycleEnd = nil
        account.sandPercentUsed = nil
        account.sandHasAllowance = false
        account.sandPlanLabel = nil
        account.sandResetAt = nil
        account.lastSuccessfulRefresh = nil
        account.lastError = nil
    }

    private func currentRefreshToken(for id: String) -> String {
        accounts.first { $0.id == id }?.refreshToken ?? ""
    }

    private func recordFailure(id: String, error: Error) {
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        var updated = accounts
        if let clientError = error as? CursorAPIClientError {
            updated[index].lastError = clientError.userMessage
        } else {
            updated[index].lastError = error.localizedDescription
        }
        accounts = updated
        persistAccounts()
    }

    private func scheduleTimerIfNeeded() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshTimer = timerFactory.schedule(interval: TimeInterval(refreshIntervalSeconds)) { [weak self] in
            Task { @MainActor in
                await self?.refreshAll()
            }
        }
    }

    private func persistAccounts() {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        userDefaults.set(data, forKey: DefaultsKey.accounts)
    }

    private func persistSelectedAccountID() {
        if let selectedAccountID {
            userDefaults.set(selectedAccountID, forKey: DefaultsKey.selectedAccountID)
        } else {
            userDefaults.removeObject(forKey: DefaultsKey.selectedAccountID)
        }
    }

    private static func loadAccounts(from userDefaults: UserDefaults) -> [CursorAccountRecord] {
        guard
            let data = userDefaults.data(forKey: DefaultsKey.accounts),
            let accounts = try? JSONDecoder().decode([CursorAccountRecord].self, from: data)
        else {
            return []
        }
        return accounts
    }
}
