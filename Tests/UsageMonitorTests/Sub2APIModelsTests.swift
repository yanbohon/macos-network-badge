import XCTest
@testable import UsageMonitor

final class Sub2APIModelsTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testLoginResponseParsesTokenAndUserFields() throws {
        let json = """
        {
          "code": 0,
          "message": "success",
          "data": {
            "access_token": "jwt-token",
            "refresh_token": "rt-token",
            "expires_in": 86400,
            "token_type": "Bearer",
            "user": {
              "id": 2964,
              "email": "user@example.com",
              "balance": 336,
              "status": "active"
            }
          }
        }
        """

        let response = try decoder.decode(Sub2APILoginEnvelope.self, from: Data(json.utf8))

        XCTAssertEqual(response.code, 0)
        XCTAssertEqual(response.message, "success")
        XCTAssertEqual(response.data?.accessToken, "jwt-token")
        XCTAssertEqual(response.data?.refreshToken, "rt-token")
        XCTAssertEqual(response.data?.expiresIn, 86400)
        XCTAssertEqual(response.data?.tokenType, "Bearer")
        XCTAssertEqual(response.data?.user.email, "user@example.com")
        XCTAssertEqual(response.data?.user.balance, 336)
    }

    func testSubscriptionsResponseParsesActiveAndInactiveRecords() throws {
        let response = try decoder.decode(
            Sub2APISubscriptionsEnvelope.self,
            from: Data(Self.subscriptionsJSON.utf8)
        )

        XCTAssertEqual(response.code, 0)
        XCTAssertEqual(response.data.count, 3)
        XCTAssertEqual(response.data[0].status, "active")
        XCTAssertEqual(response.data[0].group.name, "Pro")
        XCTAssertEqual(response.data[0].group.platform, "openai")
        XCTAssertEqual(response.data[0].group.dailyLimitUSD, 500)
        XCTAssertEqual(response.data[1].status, "expired")
    }

    func testSubscriptionsResponseParsesLiveSub2APIFieldNames() throws {
        let response = try decoder.decode(
            Sub2APISubscriptionsEnvelope.self,
            from: Data(Self.liveShapeSubscriptionsJSON.utf8)
        )

        XCTAssertEqual(response.data[0].id, "3182")
        XCTAssertEqual(response.data[0].usedTodayUSD, 84.04)
        XCTAssertEqual(response.data[0].usedWeekUSD, 120.5)
        XCTAssertEqual(response.data[0].usedMonthUSD, 300.25)
        XCTAssertEqual(response.data[0].group.dailyLimitUSD, 500)
    }

    func testActiveFilteringAndInactiveCount() throws {
        let response = try decoder.decode(
            Sub2APISubscriptionsEnvelope.self,
            from: Data(Self.subscriptionsJSON.utf8)
        )
        let catalog = SubscriptionCatalog(all: response.data)

        XCTAssertEqual(catalog.active.map(\.id), ["sub-active", "sub-unlimited"])
        XCTAssertEqual(catalog.inactiveCount, 1)
    }

    func testSelectedSubscriptionLookupHandlesMissingOrInactiveIDs() throws {
        let response = try decoder.decode(
            Sub2APISubscriptionsEnvelope.self,
            from: Data(Self.subscriptionsJSON.utf8)
        )
        let catalog = SubscriptionCatalog(all: response.data)

        XCTAssertEqual(catalog.selectedSubscription(id: "sub-active")?.id, "sub-active")
        XCTAssertNil(catalog.selectedSubscription(id: "sub-expired"))
        XCTAssertEqual(catalog.selectedSubscription(id: "missing")?.id, "sub-active")
        XCTAssertEqual(catalog.selectedSubscription(id: nil)?.id, "sub-active")
    }

    static let subscriptionsJSON = """
    {
      "code": 0,
      "message": "success",
      "data": [
        {
          "id": "sub-active",
          "status": "active",
          "used_today_usd": 84.04,
          "used_week_usd": 120.5,
          "used_month_usd": 300.25,
          "expires_at": "2026-06-01T12:00:00Z",
          "group": {
            "name": "Pro",
            "platform": "openai",
            "daily_limit_usd": 500,
            "weekly_limit_usd": 2500,
            "monthly_limit_usd": 10000
          }
        },
        {
          "id": "sub-expired",
          "status": "expired",
          "used_today_usd": 4,
          "used_week_usd": 10,
          "used_month_usd": 20,
          "expires_at": null,
          "group": {
            "name": "Old",
            "platform": "anthropic",
            "daily_limit_usd": 100,
            "weekly_limit_usd": 700,
            "monthly_limit_usd": 3000
          }
        },
        {
          "id": "sub-unlimited",
          "status": "active",
          "used_today_usd": 1.25,
          "used_week_usd": 7,
          "used_month_usd": 30,
          "expires_at": null,
          "group": {
            "name": "Unlimited",
            "platform": "openai",
            "daily_limit_usd": 0,
            "weekly_limit_usd": 0,
            "monthly_limit_usd": 0
          }
        }
      ]
    }
    """

    static let liveShapeSubscriptionsJSON = """
    {
      "code": 0,
      "message": "success",
      "data": [
        {
          "id": 3182,
          "user_id": 2964,
          "group_id": 12,
          "starts_at": "2026-05-01T00:00:00.000Z",
          "expires_at": "2026-06-01T12:00:00.000Z",
          "status": "active",
          "daily_usage_usd": 84.04,
          "weekly_usage_usd": 120.5,
          "monthly_usage_usd": 300.25,
          "created_at": "2026-05-01T00:00:00.000Z",
          "updated_at": "2026-05-09T00:00:00.000Z",
          "group": {
            "id": 12,
            "name": "Pro",
            "description": "Plan",
            "platform": "openai",
            "daily_limit_usd": 500,
            "weekly_limit_usd": 2500,
            "monthly_limit_usd": 10000,
            "status": "active"
          }
        }
      ]
    }
    """
}
