import XCTest
@testable import UsageMonitor

final class UsageFormattersTests: XCTestCase {
    func testCurrencyFormattingAlwaysKeepsTwoDecimals() {
        XCTAssertEqual(UsageFormatters.currency(84.04), "$84.04")
        XCTAssertEqual(UsageFormatters.currency(5), "$5.00")
        XCTAssertEqual(UsageFormatters.currency(0.5), "$0.50")
    }

    func testDailyLimitZeroFormatsAsInfinityAndHasNoPercentage() {
        let text = UsageFormatters.dailyUsageText(used: 84.04, limit: 0)

        XCTAssertEqual(text, "$84.04/∞")
        XCTAssertNil(UsageFormatters.percentage(used: 84.04, limit: 0))
        XCTAssertEqual(UsageFormatters.healthState(used: 84.04, limit: 0), .normal)
    }

    func testDailyUsageTextFormatsLimitedPlan() {
        XCTAssertEqual(
            UsageFormatters.dailyUsageText(used: 84.04, limit: 500),
            "$84.04/$500.00"
        )
    }

    func testCompactDailyUsageTextStacksUsedAndLimitForMenuBar() {
        XCTAssertEqual(
            UsageFormatters.compactDailyUsageText(used: 84.04, limit: 500),
            "$84.04\n$500.00"
        )
        XCTAssertEqual(
            UsageFormatters.compactDailyUsageText(used: 84.04, limit: 0),
            "$84.04\n∞"
        )
    }

    func testHealthThresholdsMapAtEightyAndNinetyFivePercent() {
        XCTAssertEqual(UsageFormatters.healthState(used: 79.99, limit: 100), .normal)
        XCTAssertEqual(UsageFormatters.healthState(used: 80, limit: 100), .warning)
        XCTAssertEqual(UsageFormatters.healthState(used: 94.99, limit: 100), .warning)
        XCTAssertEqual(UsageFormatters.healthState(used: 95, limit: 100), .danger)
    }

    func testRemainingAmountNeverDropsBelowZero() {
        XCTAssertEqual(UsageFormatters.remainingText(used: 125, limit: 100), "$0.00")
        XCTAssertEqual(UsageFormatters.remainingText(used: 25, limit: 100), "$75.00")
    }
}
