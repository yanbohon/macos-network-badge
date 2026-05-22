import XCTest
@testable import UsageMonitor

final class UsageKeyPagerTests: XCTestCase {
    func testSelectedKeyClampsAfterDeletion() {
        let keys = [
            UsageKeyConfiguration(id: "a", name: "A", symbolName: "a.circle", apiKey: "a", baseURLMode: .inherited, baseURLOverride: ""),
            UsageKeyConfiguration(id: "b", name: "B", symbolName: "b.circle", apiKey: "b", baseURLMode: .inherited, baseURLOverride: ""),
            UsageKeyConfiguration(id: "c", name: "C", symbolName: "c.circle", apiKey: "c", baseURLMode: .inherited, baseURLOverride: ""),
        ]

        XCTAssertEqual(UsageKeyPager.clampedSelection(currentIndex: 2, keyCount: keys.count - 1), 1)
        XCTAssertEqual(UsageKeyPager.clampedSelection(currentIndex: 0, keyCount: keys.count - 1), 0)
        XCTAssertEqual(UsageKeyPager.clampedSelection(currentIndex: 4, keyCount: keys.count), 2)
    }

    func testCurrentKeyDetailSelection() {
        let entries = [
            UsageKeyEntry(configuration: UsageKeyConfiguration(id: "a", name: "A", symbolName: "a.circle", apiKey: "a", baseURLMode: .inherited, baseURLOverride: "")),
            UsageKeyEntry(configuration: UsageKeyConfiguration(id: "b", name: "B", symbolName: "b.circle", apiKey: "b", baseURLMode: .independent, baseURLOverride: "https://b.example.com")),
        ]

        XCTAssertEqual(UsageKeyPager.selectedEntry(in: entries, selectedIndex: 0)?.id, "a")
        XCTAssertEqual(UsageKeyPager.selectedEntry(in: entries, selectedIndex: 1)?.id, "b")
        XCTAssertEqual(UsageKeyPager.selectedEntry(in: entries, selectedIndex: 7)?.id, "b")
    }
}
