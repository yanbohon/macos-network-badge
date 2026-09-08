import XCTest
@testable import UsageMonitor

final class CursorSessionTokenTests: XCTestCase {
    func testNormalizedAccessTokenStripsWorkosPrefix() {
        let jwt = Self.makeJWT(sub: "user_abc", exp: 1_800_000_000)
        XCTAssertEqual(CursorSessionToken.normalizedAccessToken("user_abc::\(jwt)"), jwt)
        XCTAssertEqual(CursorSessionToken.normalizedAccessToken("user_abc%3A%3A\(jwt)"), jwt)
        XCTAssertEqual(CursorSessionToken.normalizedAccessToken("  \(jwt)  "), jwt)
    }

    func testWorkosUserIDReadsPrefixedTokenAndJWTSubject() {
        let jwt = Self.makeJWT(sub: "email|user_01ABC", exp: 1_800_000_000)
        XCTAssertEqual(CursorSessionToken.workosUserID(from: jwt), "user_01ABC")
        XCTAssertEqual(CursorSessionToken.workosUserID(from: "user_local::\(jwt)"), "user_local")
    }

    func testSessionCookieMatchesCockpitFormat() {
        let jwt = Self.makeJWT(sub: "user_cookie", exp: 1_800_000_000)
        XCTAssertEqual(
            CursorSessionToken.sessionCookie(from: jwt),
            "WorkosCursorSessionToken=user_cookie%3A%3A\(jwt)"
        )
    }

    func testExportableAccessTokenRestoresUserPrefixedSessionToken() {
        let jwt = Self.makeJWT(sub: "email|user_01COPY", exp: 1_800_000_000)
        XCTAssertEqual(
            CursorSessionToken.exportableAccessToken(from: jwt),
            "user_01COPY::\(jwt)"
        )
        XCTAssertEqual(
            CursorSessionToken.exportableAccessToken(from: "user_local::\(jwt)"),
            "user_local::\(jwt)"
        )
        XCTAssertEqual(CursorSessionToken.exportableAccessToken(from: "   "), "")
        XCTAssertEqual(CursorSessionToken.exportableAccessToken(from: "plain-token"), "plain-token")
    }

    func testNeedsRefreshWhenExpiredOrMissingExp() {
        let expired = Self.makeJWT(sub: "user_exp", exp: 1)
        let fresh = Self.makeJWT(sub: "user_exp", exp: Int(Date().timeIntervalSince1970) + 3_600)
        XCTAssertTrue(CursorSessionToken.needsRefresh(expired))
        XCTAssertFalse(CursorSessionToken.needsRefresh(fresh))
        XCTAssertTrue(CursorSessionToken.needsRefresh("not-a-jwt"))
    }

    func testUsageSummaryReadsAutoPercentFromIndividualUsage() throws {
        let json = """
        {
          "membershipType": "pro",
          "billingCycleEnd": "2026-09-01T00:00:00.000Z",
          "individualUsage": {
            "plan": {
              "autoPercentUsed": 42.4,
              "apiPercentUsed": 88.2,
              "totalPercentUsed": 55
            }
          }
        }
        """
        let summary = try CursorUsageSummary.parse(from: Data(json.utf8))
        XCTAssertEqual(summary.autoPercentUsed, 42.4)
        XCTAssertEqual(summary.apiPercentUsed, 88.2)
        XCTAssertEqual(summary.membershipType, "pro")
        XCTAssertEqual(summary.billingCycleEnd, Date(timeIntervalSince1970: 1_788_220_800))
        XCTAssertEqual(
            CursorUsageSummary.billingCycleEndText(
                from: Date(timeIntervalSince1970: 1_788_220_800),
                now: Date(timeIntervalSince1970: 1_780_000_000)
            )?.hasPrefix("到期 "),
            true
        )
        XCTAssertEqual(
            CursorUsageSummary.billingCycleEndText(
                from: Date(timeIntervalSince1970: 1),
                now: Date(timeIntervalSince1970: 2)
            ),
            "已到期"
        )
        XCTAssertEqual(CursorUsageSummary.displayPercent(from: 42.4), 42)
        XCTAssertEqual(CursorUsageSummary.displayPercent(from: 0.4), 1)
        XCTAssertEqual(CursorUsageSummary.membershipDisplayName(from: "pro"), "pro")
        XCTAssertEqual(CursorUsageSummary.membershipDisplayName(from: "ultra"), "ultra")
        XCTAssertEqual(CursorUsageSummary.membershipDisplayName(from: "pro_plus"), "pro_plus")
        XCTAssertEqual(CursorUsageSummary.membershipDisplayName(from: "hobby"), "hobby")
        XCTAssertEqual(CursorUsageSummary.membershipDisplayName(from: "enterprise"), "Team")
        XCTAssertEqual(CursorUsageSummary.membershipColorHex(from: "hobby"), "#94A3B8")
        XCTAssertEqual(CursorUsageSummary.membershipColorHex(from: "pro"), "#38BDF8")
        XCTAssertEqual(CursorUsageSummary.membershipColorHex(from: "pro_plus"), "#34D399")
        XCTAssertEqual(CursorUsageSummary.membershipColorHex(from: "ultra"), "#FBBF24")
        XCTAssertEqual(CursorUsageSummary.membershipColorHex(from: "enterprise"), "#A78BFA")
        XCTAssertNil(CursorUsageSummary.membershipDisplayName(from: "   "))
        XCTAssertNil(CursorUsageSummary.membershipColorHex(from: "   "))
    }

    func testUsageSummaryReadsSnakeCasePlanUsage() throws {
        let json = #"{"plan_usage":{"auto_percent_used":"88","api_percent_used":"12"}}"#
        let summary = try CursorUsageSummary.parse(from: Data(json.utf8))
        XCTAssertEqual(summary.autoPercentUsed, 88)
        XCTAssertEqual(summary.apiPercentUsed, 12)
        XCTAssertEqual(CursorUsageSummary.displayPercent(from: 88), 88)
    }

    func testSandUsageReadsPercentAndAllowance() throws {
        let json = """
        {
            "currentPeriodStart": "2026-08-26T17:22:03.913Z",
            "nextResetTimestampUtc": "2026-09-02T09:46:13.336Z",
            "usagePercent": 27.43963,
            "hasAvailableUsage": true,
            "hasNonZeroIncludedLimit": true,
            "onDemandSettings": {
                "visible": true,
                "eligible": true,
                "dashboardUrl": "https://cursor.com/dashboard/spending"
            },
            "grokPlanLabel": "Grok Bot Plan"
        }
        """
        let status = try CursorSandUsageStatus.parse(from: Data(json.utf8))
        XCTAssertEqual(status.usagePercent, 27.43963)
        XCTAssertTrue(status.hasNonZeroIncludedLimit)
        XCTAssertTrue(status.shouldShowRing)
        XCTAssertEqual(status.planLabel, "Grok Bot Plan")
        XCTAssertEqual(CursorUsageSummary.displayPercent(from: 27.43963), 27)
    }

    func testSandUsageHidesRingWithoutIncludedLimit() throws {
        let status = try CursorSandUsageStatus.parse(from: Data(#"{"usagePercent":10,"hasNonZeroIncludedLimit":false}"#.utf8))
        XCTAssertFalse(status.shouldShowRing)
    }

    func testTeamExtractionReadsAutoAndGrokPercentsFromFirstResult() throws {
        let snapshot = try CursorTeamExtractionUsage.parse(from: Data(Self.teamExtractionJSON.utf8))
        XCTAssertEqual(snapshot.email, "robertflynn8702@outlook.com")
        XCTAssertEqual(snapshot.membershipType, "enterprise")
        XCTAssertEqual(snapshot.autoPercentUsed, 18.3832)
        XCTAssertEqual(snapshot.sandPercentUsed, 4.327936)
        XCTAssertTrue(snapshot.sandHasAllowance)
        XCTAssertEqual(snapshot.sandPlanLabel, "Grok Bot Plan")
        XCTAssertEqual(snapshot.sandResetAt, Date(timeIntervalSince1970: 1_789_133_481.656))
        XCTAssertEqual(CursorUsageSummary.displayPercent(from: 18.3832), 18)
        XCTAssertEqual(CursorUsageSummary.displayPercent(from: 4.327936), 4)
    }

    func testTeamExtractionRejectsEmptyResults() {
        XCTAssertThrowsError(try CursorTeamExtractionUsage.parse(from: Data(#"{"ok":true,"results":[]}"#.utf8)))
    }

    static let teamExtractionJSON = """
        {
            "ok": true,
            "checkedAt": "2026-09-07T11:21:24.335Z",
            "skipped": 0,
            "results": [
                {
                    "accountId": 9058,
                    "email": "robertflynn8702@outlook.com",
                    "tier": "bot_premium",
                    "health": "ok",
                    "membershipType": "enterprise",
                    "currency": "usd",
                    "cursorModels": {
                        "limitCents": 125000,
                        "usedCents": 22979,
                        "remainingCents": 102021,
                        "usedPercent": 18.3832,
                        "remainingPercent": 81.6168
                    },
                    "otherModels": {
                        "limitCents": 20000,
                        "usedCents": 20000,
                        "remainingCents": 0,
                        "usedPercent": 100,
                        "remainingPercent": 0
                    },
                    "grokBot": {
                        "usedPercent": 4.327936,
                        "remainingPercent": 95.672064,
                        "resetAt": "2026-09-11T13:31:21.656Z",
                        "planLabel": "Grok Bot Plan",
                        "hasAllowance": true
                    }
                }
            ]
        }
        """

    static func makeJWT(sub: String, exp: Int) -> String {
        func encode(_ object: [String: Any]) -> String {
            let data = try! JSONSerialization.data(withJSONObject: object)
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .trimmingCharacters(in: CharacterSet(charactersIn: "="))
        }
        return "\(encode(["alg": "none"])).\(encode(["sub": sub, "exp": exp])).sig"
    }
}

final class CursorAPIClientTests: XCTestCase {
    func testUsageSummaryRequestUsesSessionCookieAndBrowserUserAgent() async throws {
        let jwt = CursorSessionTokenTests.makeJWT(sub: "user_req", exp: 1_800_000_000)
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: #"{"individualUsage":{"plan":{"autoPercentUsed":12}}}"#),
        ]
        let client = CursorAPIClient(requestLoader: loader)

        let summary = try await client.fetchUsageSummary(accessToken: jwt)

        XCTAssertEqual(summary.autoPercentUsed, 12)
        XCTAssertEqual(loader.requests[0].url, CursorAPIClient.usageSummaryURL)
        XCTAssertEqual(loader.requests[0].httpMethod, "GET")
        XCTAssertEqual(
            loader.requests[0].value(forHTTPHeaderField: "Cookie"),
            "WorkosCursorSessionToken=user_req%3A%3A\(jwt)"
        )
        XCTAssertEqual(loader.requests[0].value(forHTTPHeaderField: "User-Agent"), CursorAPIClient.browserUserAgent)
        XCTAssertEqual(loader.requests[0].value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testSandUsageRequestPostsDashboardSessionCookie() async throws {
        let jwt = CursorSessionTokenTests.makeJWT(sub: "user_sand", exp: 1_800_000_000)
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(
                statusCode: 200,
                body: #"{"usagePercent":27.4,"hasNonZeroIncludedLimit":true,"grokPlanLabel":"Grok Bot Plan"}"#
            ),
        ]
        let client = CursorAPIClient(requestLoader: loader)

        let status = try await client.fetchSandUsage(accessToken: jwt)

        XCTAssertEqual(status.usagePercent, 27.4)
        XCTAssertEqual(loader.requests[0].url, CursorAPIClient.sandUsageURL)
        XCTAssertEqual(loader.requests[0].httpMethod, "POST")
        XCTAssertEqual(loader.requests[0].value(forHTTPHeaderField: "Origin"), "https://cursor.com")
        XCTAssertEqual(
            loader.requests[0].value(forHTTPHeaderField: "Cookie"),
            "WorkosCursorSessionToken=user_sand%3A%3A\(jwt)"
        )
        XCTAssertEqual(loader.requests[0].httpBody, Data("{}".utf8))
    }

    func testRefreshTokenRequestUsesOfficialClientID() async throws {
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: #"{"accessToken":"new-access","refreshToken":"new-refresh"}"#),
        ]
        let client = CursorAPIClient(requestLoader: loader)

        let result = try await client.refreshAccessToken(refreshToken: "old-refresh")

        XCTAssertEqual(result.accessToken, "new-access")
        XCTAssertEqual(result.refreshToken, "new-refresh")
        XCTAssertEqual(loader.requests[0].url, CursorAPIClient.oauthTokenURL)
        XCTAssertEqual(loader.requests[0].httpMethod, "POST")
        let body = try XCTUnwrap(loader.requests[0].httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(object["grant_type"], "refresh_token")
        XCTAssertEqual(object["client_id"], CursorAPIClient.authClientID)
        XCTAssertEqual(object["refresh_token"], "old-refresh")
    }

    func testUserMetaRequestUsesBearerToken() async throws {
        let jwt = CursorSessionTokenTests.makeJWT(sub: "user_meta", exp: 1_800_000_000)
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: #"{"email":"ada@example.com"}"#),
        ]
        let client = CursorAPIClient(requestLoader: loader)

        let meta = try await client.fetchUserMeta(accessToken: jwt)

        XCTAssertEqual(meta.email, "ada@example.com")
        XCTAssertEqual(loader.requests[0].url, CursorAPIClient.userMetaURL)
        XCTAssertEqual(loader.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer \(jwt)")
    }

    func testTeamExtractionRequestPostsCardSessionCookie() async throws {
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: CursorSessionTokenTests.teamExtractionJSON),
        ]
        let client = CursorAPIClient(requestLoader: loader)

        let snapshot = try await client.fetchTeamExtractionUsage(cardSession: "  SWdz2qvYhB17kGqBc26QP1iHZBmofumvIBEtciGW2TM  ")

        XCTAssertEqual(snapshot.autoPercentUsed, 18.3832)
        XCTAssertEqual(snapshot.sandPercentUsed, 4.327936)
        XCTAssertEqual(loader.requests[0].url, CursorAPIClient.teamExtractionUsageURL)
        XCTAssertEqual(loader.requests[0].httpMethod, "POST")
        XCTAssertEqual(
            loader.requests[0].value(forHTTPHeaderField: "Cookie"),
            "card_session=SWdz2qvYhB17kGqBc26QP1iHZBmofumvIBEtciGW2TM"
        )
        XCTAssertEqual(loader.requests[0].value(forHTTPHeaderField: "User-Agent"), CursorAPIClient.browserUserAgent)
        XCTAssertEqual(loader.requests[0].value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testUnauthorizedUsageMapsToAuthorizationFailure() async {
        let jwt = CursorSessionTokenTests.makeJWT(sub: "user_unauth", exp: 1_800_000_000)
        let loader = RequestRecordingLoader()
        loader.responses = [.init(statusCode: 401, body: "{}")]
        let client = CursorAPIClient(requestLoader: loader)

        do {
            _ = try await client.fetchUsageSummary(accessToken: jwt)
            XCTFail("Expected authorization failure")
        } catch let error as CursorAPIClientError {
            XCTAssertEqual(error, .authorizationFailure)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }
}

@MainActor
final class CursorUsageMonitorTests: XCTestCase {
    func testPersistsAccountsAndSelectedID() {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let first = CursorUsageMonitor(userDefaults: defaults, client: CursorAPIClient(requestLoader: RequestRecordingLoader()), timerFactory: ManualTimerFactory())
        let id = first.addAccount()
        first.updateAccount(id: id, accessToken: "user_a::aaa.bbb.ccc", refreshToken: "refresh-1")
        first.updateRingColor(id: id, hex: "#FF3B30")
        first.updateSymbolName(id: id, symbolName: "star.fill")

        let second = CursorUsageMonitor(userDefaults: defaults, client: CursorAPIClient(requestLoader: RequestRecordingLoader()), timerFactory: ManualTimerFactory())
        XCTAssertEqual(second.accounts.count, 1)
        XCTAssertEqual(second.accounts[0].accessToken, "aaa.bbb.ccc")
        XCTAssertEqual(second.accounts[0].refreshToken, "refresh-1")
        XCTAssertEqual(second.accounts[0].ringColorHex, "#FF3B30")
        XCTAssertEqual(second.accounts[0].symbolName, "star.fill")
        XCTAssertTrue(second.accounts[0].showsInMenuBar)
        XCTAssertEqual(second.accounts[0].kind, .personal)
        XCTAssertEqual(second.selectedAccountID, id)
    }

    func testPersistsTeamAccountKindAndCardSession() {
        let defaults = UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
        let first = CursorUsageMonitor(userDefaults: defaults, client: CursorAPIClient(requestLoader: RequestRecordingLoader()), timerFactory: ManualTimerFactory())
        let id = first.addAccount()
        first.updateAccountKind(id: id, kind: .team)
        first.updateAccount(id: id, accessToken: "  team-card-session  ", refreshToken: "ignored")

        let second = CursorUsageMonitor(userDefaults: defaults, client: CursorAPIClient(requestLoader: RequestRecordingLoader()), timerFactory: ManualTimerFactory())
        XCTAssertEqual(second.accounts[0].kind, .team)
        XCTAssertEqual(second.accounts[0].accessToken, "team-card-session")
        XCTAssertEqual(second.accounts[0].refreshToken, "")
    }

    func testMenuBarCanShowMultipleAccountColumnsWithDistinctColors() {
        let monitor = makeTestCursorMonitor()
        XCTAssertEqual(monitor.menuBarKeyRows, [])

        let first = monitor.addAccount()
        let second = monitor.addAccount()
        XCTAssertEqual(monitor.menuBarColumns.count, 2)
        XCTAssertEqual(monitor.menuBarKeyRows.map(\.text), ["—", "—"])
        XCTAssertNotEqual(monitor.menuBarKeyRows[0].symbolColorHex, monitor.menuBarKeyRows[1].symbolColorHex)

        monitor.setShowsInMenuBar(id: first, shows: false)
        XCTAssertEqual(monitor.menuBarKeyRows.map(\.id), ["\(second)-auto"])

        monitor.setShowsInMenuBar(id: second, shows: false)
        XCTAssertEqual(monitor.menuBarKeyRows, [])
    }

    func testRefreshUpdatesAutoPercentAndEmail() async {
        let jwt = CursorSessionTokenTests.makeJWT(sub: "user_refresh", exp: Int(Date().timeIntervalSince1970) + 3_600)
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: #"{"membershipType":"ultra","billingCycleEnd":"2026-09-01T00:00:00.000Z","individualUsage":{"plan":{"autoPercentUsed":67.6,"apiPercentUsed":91.2}}}"#),
            .init(statusCode: 200, body: #"{"email":"cursor@example.com"}"#),
            .init(
                statusCode: 200,
                body: #"{"usagePercent":27.43963,"hasNonZeroIncludedLimit":true,"grokPlanLabel":"Grok Bot Plan"}"#
            ),
        ]
        let monitor = CursorUsageMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            client: CursorAPIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )
        let id = monitor.addAccount()
        monitor.updateAccount(id: id, accessToken: jwt, refreshToken: "")

        await monitor.refreshAccount(id: id)

        XCTAssertEqual(monitor.selectedAutoUsageText, "68%")
        XCTAssertEqual(monitor.menuBarColumns.count, 1)
        XCTAssertEqual(monitor.menuBarKeyRows.map(\.text), ["68%", "27%"])
        XCTAssertEqual(monitor.menuBarKeyRows.map(\.id), ["\(id)-auto", "\(id)-sand"])
        XCTAssertTrue(monitor.menuBarKeyRows[0].name.hasSuffix("Auto"))
        XCTAssertTrue(monitor.menuBarKeyRows[1].name.hasSuffix("Grok"))
        XCTAssertEqual(monitor.selectedAccount?.email, "cursor@example.com")
        XCTAssertEqual(monitor.selectedAccount?.membershipType, "ultra")
        XCTAssertEqual(monitor.selectedAccount?.membershipDisplayName, "ultra")
        XCTAssertEqual(monitor.selectedAccount?.apiUsageText, "91%")
        XCTAssertEqual(monitor.selectedAccount?.billingCycleEnd, Date(timeIntervalSince1970: 1_788_220_800))
        XCTAssertEqual(monitor.selectedAccount?.sandUsageText, "27%")
        XCTAssertNil(monitor.selectedAccount?.lastError)
        XCTAssertEqual(loader.requests.count, 3)
        XCTAssertEqual(loader.requests[0].url, CursorAPIClient.usageSummaryURL)
        XCTAssertEqual(loader.requests[1].url, CursorAPIClient.userMetaURL)
        XCTAssertEqual(loader.requests[2].url, CursorAPIClient.sandUsageURL)
    }

    func testExpiredAccessTokenRefreshesBeforeUsage() async {
        let expired = CursorSessionTokenTests.makeJWT(sub: "user_old", exp: 10)
        let fresh = CursorSessionTokenTests.makeJWT(sub: "user_new", exp: Int(Date().timeIntervalSince1970) + 3_600)
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: #"{"accessToken":"\#(fresh)","refreshToken":"next-refresh"}"#),
            .init(statusCode: 200, body: #"{"individualUsage":{"plan":{"autoPercentUsed":10}}}"#),
            .init(statusCode: 200, body: #"{"email":"new@example.com"}"#),
            .init(statusCode: 200, body: #"{"hasNonZeroIncludedLimit":false}"#),
        ]
        let monitor = CursorUsageMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            client: CursorAPIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )
        let id = monitor.addAccount()
        monitor.updateAccount(id: id, accessToken: expired, refreshToken: "old-refresh")

        await monitor.refreshAccount(id: id)

        XCTAssertEqual(monitor.selectedAccount?.accessToken, fresh)
        XCTAssertEqual(monitor.selectedAccount?.refreshToken, "next-refresh")
        XCTAssertEqual(monitor.menuBarKeyRows.map(\.text), ["10%"])
        XCTAssertEqual(loader.requests[0].url, CursorAPIClient.oauthTokenURL)
        XCTAssertEqual(loader.requests[1].url, CursorAPIClient.usageSummaryURL)
    }

    func testUnauthorizedUsageRetriesAfterForcedRefresh() async {
        let jwt = CursorSessionTokenTests.makeJWT(sub: "user_retry", exp: Int(Date().timeIntervalSince1970) + 3_600)
        let fresh = CursorSessionTokenTests.makeJWT(sub: "user_retry2", exp: Int(Date().timeIntervalSince1970) + 3_600)
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 401, body: "{}"),
            .init(statusCode: 200, body: #"{"accessToken":"\#(fresh)"}"#),
            .init(statusCode: 200, body: #"{"individualUsage":{"plan":{"autoPercentUsed":3}}}"#),
            .init(statusCode: 200, body: #"{"email":"retry@example.com"}"#),
            .init(statusCode: 200, body: #"{"hasNonZeroIncludedLimit":false}"#),
        ]
        let monitor = CursorUsageMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            client: CursorAPIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )
        let id = monitor.addAccount()
        monitor.updateAccount(id: id, accessToken: jwt, refreshToken: "refresh-now")

        await monitor.refreshAccount(id: id)

        XCTAssertEqual(monitor.menuBarKeyRows.map(\.text), ["3%"])
        XCTAssertEqual(loader.requests[0].url, CursorAPIClient.usageSummaryURL)
        XCTAssertEqual(loader.requests[1].url, CursorAPIClient.oauthTokenURL)
        XCTAssertEqual(loader.requests[2].url, CursorAPIClient.usageSummaryURL)
    }

    func testDeletingSelectedAccountSelectsTheNextOne() {
        let monitor = makeTestCursorMonitor()
        let first = monitor.addAccount()
        let second = monitor.addAccount()
        monitor.deleteAccount(id: first)
        XCTAssertEqual(monitor.selectedAccountID, second)
        monitor.deleteAccount(id: second)
        XCTAssertNil(monitor.selectedAccountID)
        XCTAssertEqual(monitor.menuBarKeyRows, [])
    }

    func testTeamAccountRefreshMapsExtractionUsageToAutoAndGrok() async {
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: CursorSessionTokenTests.teamExtractionJSON),
        ]
        let monitor = CursorUsageMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            client: CursorAPIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )
        let id = monitor.addAccount()
        monitor.updateAccountKind(id: id, kind: .team)
        monitor.updateAccount(id: id, accessToken: "team-card-session", refreshToken: "")

        await monitor.refreshAccount(id: id)

        XCTAssertEqual(monitor.selectedAutoUsageText, "18%")
        XCTAssertEqual(monitor.menuBarKeyRows.map(\.text), ["18%", "4%"])
        XCTAssertEqual(monitor.menuBarKeyRows.map(\.id), ["\(id)-auto", "\(id)-sand"])
        XCTAssertTrue(monitor.menuBarKeyRows[0].name.hasSuffix("Auto"))
        XCTAssertTrue(monitor.menuBarKeyRows[1].name.hasSuffix("Grok"))
        XCTAssertEqual(monitor.selectedAccount?.email, "robertflynn8702@outlook.com")
        XCTAssertEqual(monitor.selectedAccount?.membershipType, "enterprise")
        XCTAssertEqual(monitor.selectedAccount?.membershipDisplayName, "Team")
        XCTAssertEqual(monitor.selectedAccount?.sandUsageText, "4%")
        XCTAssertNil(monitor.selectedAccount?.lastError)
        XCTAssertEqual(loader.requests.count, 1)
        XCTAssertEqual(loader.requests[0].url, CursorAPIClient.teamExtractionUsageURL)
        XCTAssertEqual(loader.requests[0].httpMethod, "POST")
        XCTAssertEqual(
            loader.requests[0].value(forHTTPHeaderField: "Cookie"),
            "card_session=team-card-session"
        )
    }

    func testTeamAccountRefreshRequiresCardSession() async {
        let loader = RequestRecordingLoader()
        let monitor = CursorUsageMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            client: CursorAPIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )
        let id = monitor.addAccount()
        monitor.updateAccountKind(id: id, kind: .team)

        await monitor.refreshAccount(id: id)

        XCTAssertEqual(monitor.selectedAccount?.lastError, "请先粘贴 Card Session")
        XCTAssertTrue(loader.requests.isEmpty)
    }

    func testSandUsageFailureLeavesAutoRingIntact() async {
        let jwt = CursorSessionTokenTests.makeJWT(sub: "user_sand_fail", exp: Int(Date().timeIntervalSince1970) + 3_600)
        let loader = RequestRecordingLoader()
        loader.responses = [
            .init(statusCode: 200, body: #"{"individualUsage":{"plan":{"autoPercentUsed":12}}}"#),
            .init(statusCode: 200, body: #"{"email":"sand-fail@example.com"}"#),
            .init(statusCode: 500, body: "{}"),
        ]
        let monitor = CursorUsageMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            client: CursorAPIClient(requestLoader: loader),
            timerFactory: ManualTimerFactory()
        )
        let id = monitor.addAccount()
        monitor.updateAccount(id: id, accessToken: jwt, refreshToken: "")

        await monitor.refreshAccount(id: id)

        XCTAssertEqual(monitor.menuBarKeyRows.map(\.text), ["12%"])
        XCTAssertFalse(monitor.accounts[0].showsSandRing)
        XCTAssertNil(monitor.accounts[0].lastError)
    }
}
