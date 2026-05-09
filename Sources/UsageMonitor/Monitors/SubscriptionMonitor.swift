import Foundation

protocol RefreshTimer {
    func invalidate()
}

protocol RefreshTimerFactory {
    func schedule(interval: TimeInterval, action: @escaping @Sendable () -> Void) -> RefreshTimer
}

final class FoundationRefreshTimer: RefreshTimer {
    private let timer: Timer

    init(timer: Timer) {
        self.timer = timer
    }

    func invalidate() {
        timer.invalidate()
    }
}

final class FoundationRefreshTimerFactory: RefreshTimerFactory {
    func schedule(interval: TimeInterval, action: @escaping @Sendable () -> Void) -> RefreshTimer {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            action()
        }
        return FoundationRefreshTimer(timer: timer)
    }
}

@MainActor
final class SubscriptionMonitor: ObservableObject {
    enum DefaultsKey {
        static let baseURL = "sub2api.baseURL"
        static let email = "sub2api.email"
        static let selectedSubscriptionID = "sub2api.selectedSubscriptionID"
        static let refreshIntervalMinutes = "sub2api.refreshIntervalMinutes"
    }

    static let allowedRefreshIntervals = [1, 5, 15, 30, 60]
    static let defaultRefreshInterval = 5

    @Published private(set) var baseURLText: String
    @Published private(set) var email: String
    @Published private(set) var password: String
    @Published var selectedSubscriptionID: String? {
        didSet {
            userDefaults.set(selectedSubscriptionID, forKey: DefaultsKey.selectedSubscriptionID)
        }
    }
    @Published var refreshIntervalMinutes: Int {
        didSet {
            if !Self.allowedRefreshIntervals.contains(refreshIntervalMinutes) {
                refreshIntervalMinutes = Self.defaultRefreshInterval
                return
            }
            userDefaults.set(refreshIntervalMinutes, forKey: DefaultsKey.refreshIntervalMinutes)
            scheduleTimer()
        }
    }
    @Published private(set) var user: Sub2APIUser?
    @Published private(set) var catalog = SubscriptionCatalog(all: [])
    @Published private(set) var lastSuccessfulRefresh: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var authState: AuthState = .notConfigured

    private let userDefaults: UserDefaults
    private let secretStore: SecretStoring
    private let client: Sub2APIClient
    private let timerFactory: RefreshTimerFactory
    private var refreshTimer: RefreshTimer?

    init(
        userDefaults: UserDefaults = .standard,
        secretStore: SecretStoring = KeychainStore(),
        client: Sub2APIClient = Sub2APIClient(),
        timerFactory: RefreshTimerFactory = FoundationRefreshTimerFactory()
    ) {
        self.userDefaults = userDefaults
        self.secretStore = secretStore
        self.client = client
        self.timerFactory = timerFactory

        baseURLText = userDefaults.string(forKey: DefaultsKey.baseURL) ?? ""
        email = userDefaults.string(forKey: DefaultsKey.email) ?? ""
        selectedSubscriptionID = userDefaults.string(forKey: DefaultsKey.selectedSubscriptionID)
        let savedInterval = userDefaults.integer(forKey: DefaultsKey.refreshIntervalMinutes)
        refreshIntervalMinutes = Self.allowedRefreshIntervals.contains(savedInterval)
            ? savedInterval
            : Self.defaultRefreshInterval
        password = (try? secretStore.read(.password)) ?? ""
        updateAuthState()
        scheduleTimer()
    }

    var activeSubscriptions: [Sub2APISubscription] {
        catalog.active
    }

    var selectedSubscription: Sub2APISubscription? {
        catalog.selectedSubscription(id: selectedSubscriptionID)
    }

    var menuBarText: String {
        guard !baseURLText.isEmpty, !email.isEmpty else { return "未配置" }
        if authState == .needsLogin {
            return "未登录"
        }
        guard !(password.isEmpty && ((try? secretStore.read(.accessToken)) ?? nil) == nil) else {
            return "未登录"
        }
        if let selectedSubscription {
            return UsageFormatters.dailyUsageText(
                used: selectedSubscription.usedTodayUSD,
                limit: selectedSubscription.group.dailyLimitUSD
            )
        }
        if lastError != nil && lastSuccessfulRefresh == nil {
            return "刷新失败"
        }
        if (!catalog.all.isEmpty || lastSuccessfulRefresh != nil) && activeSubscriptions.isEmpty {
            return "无套餐"
        }
        return "未登录"
    }

    var selectedHealthState: UsageHealthState {
        guard let selectedSubscription else { return .normal }
        return UsageFormatters.healthState(
            used: selectedSubscription.usedTodayUSD,
            limit: selectedSubscription.group.dailyLimitUSD
        )
    }

    func updateBaseURL(_ value: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        baseURLText = normalized
        userDefaults.set(normalized, forKey: DefaultsKey.baseURL)
        updateAuthState()
    }

    func updateEmail(_ value: String) {
        email = value.trimmingCharacters(in: .whitespacesAndNewlines)
        userDefaults.set(email, forKey: DefaultsKey.email)
        updateAuthState()
    }

    func updatePassword(_ value: String) {
        password = value
        if value.isEmpty {
            try? secretStore.delete(.password)
        } else {
            try? secretStore.write(value, for: .password)
        }
        updateAuthState()
    }

    func setSelectedSubscription(_ id: String) {
        selectedSubscriptionID = id
    }

    func start() {
        Task { [weak self] in
            await self?.refreshOnLaunch()
        }
    }

    func loginAndRefresh() async throws {
        let token: Sub2APILoginData
        do {
            token = try await login()
        } catch {
            lastError = userMessage(for: error)
            authState = .needsLogin
            throw error
        }

        do {
            try storeToken(token)
            try await refreshSubscriptions(accessToken: token.accessToken, retryUnauthorized: true)
            lastError = nil
            authState = .authenticated
        } catch {
            lastError = userMessage(for: error)
            authState = .error
            throw error
        }
    }

    func refreshNow() async {
        do {
            try await refreshUsingStoredCredentials()
        } catch {
            lastError = userMessage(for: error)
            updateAuthState()
        }
    }

    private func refreshOnLaunch() async {
        guard configurationIsComplete else {
            updateAuthState()
            return
        }
        await refreshNow()
    }

    private func refreshUsingStoredCredentials() async throws {
        guard let baseURL = validatedBaseURL() else {
            throw ValidationError.invalidBaseURL
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let token = try await validAccessTokenOrLogin()
        do {
            try await refreshSubscriptions(baseURL: baseURL, accessToken: token, retryUnauthorized: true)
            lastError = nil
            authState = .authenticated
        } catch let error as Sub2APIClientError where error.isUnauthorized {
            lastError = "登录已失效，请重新验证"
            authState = .needsLogin
            throw error
        }
    }

    private func refreshSubscriptions(accessToken: String, retryUnauthorized: Bool) async throws {
        guard let baseURL = validatedBaseURL() else {
            throw ValidationError.invalidBaseURL
        }
        try await refreshSubscriptions(baseURL: baseURL, accessToken: accessToken, retryUnauthorized: retryUnauthorized)
    }

    private func refreshSubscriptions(baseURL: URL, accessToken: String, retryUnauthorized: Bool) async throws {
        do {
            let subscriptions = try await client.subscriptions(baseURL: baseURL, accessToken: accessToken)
            catalog = SubscriptionCatalog(all: subscriptions)
            if selectedSubscriptionID == nil || catalog.selectedSubscription(id: selectedSubscriptionID)?.id != selectedSubscriptionID {
                selectedSubscriptionID = catalog.active.first?.id
            }
            lastSuccessfulRefresh = Date()
        } catch let error as Sub2APIClientError where error.isUnauthorized && retryUnauthorized {
            do {
                let token = try await login()
                try storeToken(token)
                try await refreshSubscriptions(baseURL: baseURL, accessToken: token.accessToken, retryUnauthorized: false)
            } catch {
                throw Sub2APIClientError.httpStatus(401, "登录已失效，请重新验证")
            }
        }
    }

    private func login() async throws -> Sub2APILoginData {
        guard let baseURL = validatedBaseURL() else {
            throw ValidationError.invalidBaseURL
        }
        guard !email.isEmpty else {
            throw ValidationError.missingEmail
        }
        guard !password.isEmpty else {
            throw ValidationError.missingPassword
        }
        return try await client.login(baseURL: baseURL, email: email, password: password)
    }

    private func validAccessTokenOrLogin() async throws -> String {
        if let token = try secretStore.read(.accessToken), !token.isEmpty, !isTokenExpired {
            return token
        }
        let loginData = try await login()
        try storeToken(loginData)
        return loginData.accessToken
    }

    private func storeToken(_ token: Sub2APILoginData) throws {
        try secretStore.write(password, for: .password)
        try secretStore.write(token.accessToken, for: .accessToken)
        if let refreshToken = token.refreshToken {
            try secretStore.write(refreshToken, for: .refreshToken)
        } else {
            try secretStore.delete(.refreshToken)
        }
        let expiry = Date().addingTimeInterval(token.expiresIn).timeIntervalSince1970
        try secretStore.write(String(expiry), for: .accessTokenExpiry)
        user = token.user
    }

    private var isTokenExpired: Bool {
        guard
            let raw = try? secretStore.read(.accessTokenExpiry),
            let timestamp = Double(raw)
        else {
            return true
        }
        return Date().timeIntervalSince1970 >= timestamp
    }

    private var configurationIsComplete: Bool {
        validatedBaseURL() != nil && !email.isEmpty && !password.isEmpty
    }

    private func validatedBaseURL() -> URL? {
        guard
            let url = URL(string: baseURLText),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else {
            return nil
        }
        return url
    }

    private func updateAuthState() {
        if baseURLText.isEmpty || email.isEmpty {
            authState = .notConfigured
        } else if password.isEmpty {
            authState = .needsLogin
        } else if lastError != nil {
            authState = .error
        } else {
            authState = .ready
        }
    }

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        refreshTimer = timerFactory.schedule(interval: TimeInterval(refreshIntervalMinutes * 60)) { [weak self] in
            Task { @MainActor in
                await self?.refreshNow()
            }
        }
    }

    private func userMessage(for error: Error) -> String {
        if let error = error as? Sub2APIClientError {
            return error.userMessage
        }
        if let error = error as? ValidationError {
            return error.userMessage
        }
        return "网络请求失败"
    }
}

enum AuthState {
    case notConfigured
    case needsLogin
    case ready
    case authenticated
    case error
}

enum ValidationError: Error {
    case invalidBaseURL
    case missingEmail
    case missingPassword

    var userMessage: String {
        switch self {
        case .invalidBaseURL:
            return "Base URL 必须以 http:// 或 https:// 开头"
        case .missingEmail:
            return "请输入邮箱"
        case .missingPassword:
            return "请输入密码"
        }
    }
}
