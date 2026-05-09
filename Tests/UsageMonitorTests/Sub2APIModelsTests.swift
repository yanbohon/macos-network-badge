import XCTest
@testable import UsageMonitor

final class Sub2APIModelsTests: XCTestCase {
    func testUsageResponseParsesSampleJSONAndFractionalTimestamps() throws {
        let response = try JSONDecoder.sub2api.decode(
            UsageResponse.self,
            from: Data(Self.sampleUsageJSON.utf8)
        )

        XCTAssertTrue(response.isValid)
        XCTAssertEqual(response.mode, "api-key")
        XCTAssertEqual(response.planName, "Pro")
        XCTAssertEqual(response.remaining, 415.96)
        XCTAssertEqual(response.unit, "usd")
        XCTAssertEqual(response.subscription.dailyUsageUSD, 84.04)
        XCTAssertEqual(response.subscription.dailyLimitUSD, 500)
        XCTAssertEqual(response.subscription.weeklyUsageUSD, 120.5)
        XCTAssertEqual(response.subscription.weeklyLimitUSD, 2500)
        XCTAssertEqual(response.subscription.monthlyUsageUSD, 300.25)
        XCTAssertEqual(response.subscription.monthlyLimitUSD, 10000)
        XCTAssertNotNil(response.subscription.expiresAt)
        XCTAssertEqual(response.usage.today.requestCount, 12)
        XCTAssertEqual(response.usage.today.totalTokens, 3000)
        XCTAssertEqual(response.usage.total.totalCostUSD, 19.75)
        XCTAssertEqual(response.usage.averageDurationMS, 842.7)
        XCTAssertEqual(response.usage.rpm, 0.7)
        XCTAssertEqual(response.usage.tpm, 85.3)
        XCTAssertEqual(response.modelStats.map(\.modelName), ["gpt-4o-mini", "claude-3-5-sonnet"])
        XCTAssertEqual(response.modelStats[0].requestCount, 7)
        XCTAssertEqual(response.modelStats[0].inputCostUSD, 0.12)
        XCTAssertEqual(response.modelStats[0].outputCostUSD, 0.34)
        XCTAssertEqual(response.modelStats[0].totalCostUSD, 0.46)
    }

    func testUsageResponseAllowsNumericStringsForKnownAmountFields() throws {
        let json = """
        {
          "isValid": true,
          "mode": "api-key",
          "model_stats": [],
          "planName": "Starter",
          "remaining": "12.5",
          "subscription": {
            "daily_usage_usd": "2.5",
            "daily_limit_usd": "10",
            "weekly_usage_usd": "3",
            "weekly_limit_usd": "70",
            "monthly_usage_usd": "4",
            "monthly_limit_usd": "300",
            "expires_at": null
          },
          "unit": "usd",
          "usage": {
            "today": 2.5,
            "total": 4,
            "average_duration_ms": "100.5",
            "rpm": "0.2",
            "tpm": "1.5"
          }
        }
        """

        let response = try JSONDecoder.sub2api.decode(UsageResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.remaining, 12.5)
        XCTAssertEqual(response.subscription.dailyUsageUSD, 2.5)
        XCTAssertEqual(response.usage.today.totalCostUSD, 2.5)
        XCTAssertEqual(response.usage.total.totalCostUSD, 4)
        XCTAssertEqual(response.usage.averageDurationMS, 100.5)
    }

    static let sampleUsageJSON = """
    {
      "isValid": true,
      "mode": "api-key",
      "model_stats": [
        {
          "model": "gpt-4o-mini",
          "request_count": 7,
          "input_tokens": 1000,
          "output_tokens": 2000,
          "total_tokens": 3000,
          "input_cost_usd": 0.12,
          "output_cost_usd": 0.34,
          "total_cost_usd": 0.46,
          "ignored": "field"
        },
        {
          "model_name": "claude-3-5-sonnet",
          "requests": 5,
          "prompt_tokens": 400,
          "completion_tokens": 600,
          "tokens": 1000,
          "input_cost": 0.20,
          "output_cost": 0.90,
          "cost": 1.10
        }
      ],
      "planName": "Pro",
      "remaining": 415.96,
      "subscription": {
        "daily_usage_usd": 84.04,
        "daily_limit_usd": 500,
        "weekly_usage_usd": 120.5,
        "weekly_limit_usd": 2500,
        "monthly_usage_usd": 300.25,
        "monthly_limit_usd": 10000,
        "expires_at": "2026-06-01T12:00:00.123Z"
      },
      "unit": "usd",
      "usage": {
        "today": {
          "request_count": 12,
          "input_tokens": 1000,
          "output_tokens": 2000,
          "total_tokens": 3000,
          "input_cost_usd": 0.45,
          "output_cost_usd": 0.78,
          "total_cost_usd": 1.23
        },
        "total": {
          "request_count": 90,
          "input_tokens": 12000,
          "output_tokens": 13000,
          "total_tokens": 25000,
          "input_cost_usd": 8.25,
          "output_cost_usd": 11.50,
          "total_cost_usd": 19.75
        },
        "average_duration_ms": 842.7,
        "rpm": 0.7,
        "tpm": 85.3
      },
      "unknown_root": true
    }
    """
}
