import Foundation
import XCTest
@testable import UsageMonitor

@MainActor
final class ServiceStatusMonitorTests: XCTestCase {
    func testMonitoredModelsContainGPT56SeriesAndGPT55Only() {
        XCTAssertEqual(
            ServiceStatusMonitor.monitoredModels,
            ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"]
        )
    }

    func testMenuBarModelDefaultsToGPT56Sol() {
        let monitor = ServiceStatusMonitor(
            userDefaults: Self.makeDefaults(),
            timerFactory: ManualTimerFactory()
        )

        XCTAssertEqual(monitor.menuBarModel, .gpt56Sol)
    }

    func testMenuBarModelSelectionControlsCellsAndPersists() async {
        let defaults = Self.makeDefaults()
        let monitor = ServiceStatusMonitor(
            userDefaults: defaults,
            client: StubServiceStatusClient(results: [.success(Self.statusResult())]),
            timerFactory: ManualTimerFactory()
        )
        await monitor.refreshNow()

        XCTAssertEqual(monitor.selectedService?.model, "gpt-5.6-sol")
        XCTAssertEqual(monitor.displayCells.last?.kind, .red)

        monitor.menuBarModel = .gpt56Terra

        XCTAssertEqual(monitor.selectedService?.model, "gpt-5.6-terra")
        XCTAssertEqual(monitor.displayCells.last?.kind, .green)

        let restoredMonitor = ServiceStatusMonitor(
            userDefaults: defaults,
            timerFactory: ManualTimerFactory()
        )
        XCTAssertEqual(restoredMonitor.menuBarModel, .gpt56Terra)
    }

    func testInitialAvailableStatusAndGreenToYellowChangeDoNotNotify() async {
        let notifier = RecordingServiceStatusNotifier()
        let client = StubServiceStatusClient(results: [
            .success(Self.statusResult(selectedProbe: Self.greenProbe)),
            .success(Self.statusResult(selectedProbe: Self.yellowProbe)),
        ])
        let monitor = ServiceStatusMonitor(
            userDefaults: Self.makeDefaults(),
            client: client,
            timerFactory: ManualTimerFactory(),
            notificationSink: notifier
        )

        await monitor.refreshNow()
        await monitor.refreshNow()

        XCTAssertEqual(notifier.changes, [])
    }

    func testAvailableToRedChangeNotifiesSelectedModelUnavailable() async {
        let notifier = RecordingServiceStatusNotifier()
        let client = StubServiceStatusClient(results: [
            .success(Self.statusResult(selectedProbe: Self.greenProbe)),
            .success(Self.statusResult(selectedProbe: Self.redProbe)),
        ])
        let monitor = ServiceStatusMonitor(
            userDefaults: Self.makeDefaults(),
            client: client,
            timerFactory: ManualTimerFactory(),
            notificationSink: notifier
        )

        await monitor.refreshNow()
        await monitor.refreshNow()

        XCTAssertEqual(notifier.changes, [
            ServiceStatusChange(
                model: .gpt56Sol,
                previousAvailability: .available,
                availability: .unavailable,
                cellKind: .red,
                probe: Self.redProbe
            ),
        ])
    }

    func testRedToYellowChangeNotifiesSelectedModelAvailable() async {
        let notifier = RecordingServiceStatusNotifier()
        let client = StubServiceStatusClient(results: [
            .success(Self.statusResult(selectedProbe: Self.redProbe)),
            .success(Self.statusResult(selectedProbe: Self.yellowProbe)),
        ])
        let monitor = ServiceStatusMonitor(
            userDefaults: Self.makeDefaults(),
            client: client,
            timerFactory: ManualTimerFactory(),
            notificationSink: notifier
        )

        await monitor.refreshNow()
        await monitor.refreshNow()

        XCTAssertEqual(notifier.changes, [
            ServiceStatusChange(
                model: .gpt56Sol,
                previousAvailability: .unavailable,
                availability: .available,
                cellKind: .yellow,
                probe: Self.yellowProbe
            ),
        ])
    }

    func testChangingMenuBarModelEstablishesNewNotificationBaseline() async {
        let notifier = RecordingServiceStatusNotifier()
        let client = StubServiceStatusClient(results: [
            .success(Self.statusResult(selectedProbe: Self.greenProbe, terraProbe: Self.redProbe)),
            .success(Self.statusResult(selectedProbe: Self.greenProbe, terraProbe: Self.redProbe)),
            .success(Self.statusResult(selectedProbe: Self.greenProbe, terraProbe: Self.yellowProbe)),
        ])
        let monitor = ServiceStatusMonitor(
            userDefaults: Self.makeDefaults(),
            client: client,
            timerFactory: ManualTimerFactory(),
            notificationSink: notifier
        )

        await monitor.refreshNow()
        monitor.menuBarModel = .gpt56Terra
        await monitor.refreshNow()
        await monitor.refreshNow()

        XCTAssertEqual(notifier.changes, [
            ServiceStatusChange(
                model: .gpt56Terra,
                previousAvailability: .unavailable,
                availability: .available,
                cellKind: .yellow,
                probe: Self.yellowProbe
            ),
        ])
    }

    func testStartSchedulesOneMinuteTimerAndRefreshesOnce() async throws {
        let client = StubServiceStatusClient(results: [
            .success(Self.statusResult()),
        ])
        let timers = ManualTimerFactory()
        let monitor = ServiceStatusMonitor(
            userDefaults: Self.makeDefaults(),
            client: client,
            timerFactory: timers
        )

        monitor.start()
        monitor.start()

        while monitor.lastSuccessfulRefresh == nil {
            await Task.yield()
        }

        XCTAssertEqual(timers.scheduledIntervals, [60])
        let fetchCount = await client.fetchCount()
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(monitor.selectedService?.model, "gpt-5.6-sol")
        XCTAssertNil(monitor.lastError)
    }

    func testTimerRefreshUsesSameOneMinuteSchedule() async throws {
        let client = StubServiceStatusClient(results: [
            .success(Self.statusResult(generatedAt: 1)),
            .success(Self.statusResult(generatedAt: 2)),
        ])
        let timers = ManualTimerFactory()
        let monitor = ServiceStatusMonitor(
            userDefaults: Self.makeDefaults(),
            client: client,
            timerFactory: timers
        )

        monitor.start()
        while monitor.lastSuccessfulRefresh == nil {
            await Task.yield()
        }

        timers.timers.last?.fire()
        while monitor.response?.generatedAt != 2 {
            await Task.yield()
        }

        XCTAssertEqual(timers.scheduledIntervals, [60])
        let fetchCount = await client.fetchCount()
        XCTAssertEqual(fetchCount, 2)
    }

    func testConcurrentRefreshesShareSingleRequest() async {
        let client = BlockingServiceStatusClient()
        let monitor = ServiceStatusMonitor(
            userDefaults: Self.makeDefaults(),
            client: client,
            timerFactory: ManualTimerFactory()
        )

        let first = Task { await monitor.refreshNow() }
        let second = Task { await monitor.refreshNow() }

        while await client.fetchCount() == 0 {
            await Task.yield()
        }

        let inFlightCount = await client.fetchCount()
        XCTAssertEqual(inFlightCount, 1)
        await client.resume(.success(Self.statusResult()))
        await first.value
        await second.value

        XCTAssertEqual(monitor.selectedService?.model, "gpt-5.6-sol")
        let completedCount = await client.fetchCount()
        XCTAssertEqual(completedCount, 1)
    }

    func testTimerTicksDoNotAccumulateRefreshWaitersWhileRequestIsInFlight() async {
        let client = BlockingServiceStatusClient()
        let timers = ManualTimerFactory()
        let monitor = ServiceStatusMonitor(
            userDefaults: Self.makeDefaults(),
            client: client,
            timerFactory: timers
        )

        monitor.start()
        while await client.fetchCount() == 0 {
            await Task.yield()
        }

        for _ in 0..<100 {
            timers.timers.last?.fire()
        }
        for _ in 0..<100 {
            await Task.yield()
        }

        XCTAssertEqual(monitor.peakTimerRefreshCount, 1)
        await client.resume(.success(Self.statusResult()))
        while monitor.activeTimerRefreshCount > 0 {
            await Task.yield()
        }
    }

    func testFailureAfterSuccessKeepsPreviousCellsAndMarksStale() async throws {
        let client = StubServiceStatusClient(results: [
            .success(Self.statusResult()),
            .failure(StatusAPIClientError.network("offline")),
        ])
        let monitor = ServiceStatusMonitor(
            userDefaults: Self.makeDefaults(),
            client: client,
            timerFactory: ManualTimerFactory()
        )

        await monitor.refreshNow()
        let cells = monitor.displayCells
        let rawJSONText = monitor.rawJSONText

        await monitor.refreshNow()

        XCTAssertEqual(monitor.displayCells, cells)
        XCTAssertEqual(monitor.rawJSONText, rawJSONText)
        XCTAssertEqual(monitor.lastError, "状态请求失败")
        XCTAssertTrue(monitor.isStaleAfterFailure)
        XCTAssertEqual(monitor.selectedService?.model, "gpt-5.6-sol")
    }

    func testFailureBeforeAnySuccessKeepsGrayCellsAndReportsError() async throws {
        let client = StubServiceStatusClient(results: [
            .failure(StatusAPIClientError.httpStatus(503, "status unavailable")),
        ])
        let monitor = ServiceStatusMonitor(
            userDefaults: Self.makeDefaults(),
            client: client,
            timerFactory: ManualTimerFactory()
        )

        await monitor.refreshNow()

        XCTAssertNil(monitor.selectedService)
        XCTAssertNil(monitor.rawJSONText)
        XCTAssertFalse(monitor.isStaleAfterFailure)
        XCTAssertEqual(monitor.lastError, "status unavailable")
        XCTAssertEqual(monitor.displayCells.map(\.kind), Array(repeating: .gray, count: 8))
    }

    func testMissingModelReportsFailureAndShowsGrayCells() async throws {
        let result = StatusAPIResult(
            response: ServiceStatusResponse(
                allOK: true,
                generatedAt: 1,
                services: [
                    ServiceStatusService(model: "gpt-4.1", uptimePct: 100, last: nil, history: []),
                ]
            ),
            prettyRawJSON: "{}"
        )
        let client = StubServiceStatusClient(results: [
            .success(result),
        ])
        let monitor = ServiceStatusMonitor(
            userDefaults: Self.makeDefaults(),
            client: client,
            timerFactory: ManualTimerFactory()
        )

        await monitor.refreshNow()

        XCTAssertNil(monitor.selectedService)
        XCTAssertEqual(monitor.lastError, "未找到 gpt-5.6-sol 状态")
        XCTAssertEqual(monitor.displayCells.map(\.kind), Array(repeating: .gray, count: 8))
    }

    private static let greenProbe = ServiceStatusProbe(ts: 9, ok: true, latencyMS: 900, error: nil)
    private static let yellowProbe = ServiceStatusProbe(ts: 10, ok: true, latencyMS: 3_500, error: nil)
    private static let redProbe = ServiceStatusProbe(ts: 11, ok: false, latencyMS: nil, error: "timeout")

    private static func statusResult(
        generatedAt: TimeInterval = 1_778_762_578,
        selectedProbe: ServiceStatusProbe = ServiceStatusProbe(
            ts: 9,
            ok: false,
            latencyMS: nil,
            error: "timeout"
        ),
        terraProbe: ServiceStatusProbe = ServiceStatusProbe(
            ts: 9,
            ok: true,
            latencyMS: 900,
            error: nil
        )
    ) -> StatusAPIResult {
        let response = ServiceStatusResponse(
            allOK: true,
            generatedAt: generatedAt,
            services: [
                ServiceStatusService(
                    model: "gpt-5.6-sol",
                    uptimePct: 99.9,
                    last: selectedProbe,
                    history: [
                        ServiceStatusProbe(ts: 1, ok: true, latencyMS: 100, error: nil),
                        ServiceStatusProbe(ts: 2, ok: true, latencyMS: 3_000, error: nil),
                        ServiceStatusProbe(ts: 3, ok: false, latencyMS: nil, error: "timeout"),
                    ]
                ),
                ServiceStatusService(
                    model: "gpt-5.6-terra",
                    uptimePct: 100,
                    last: terraProbe,
                    history: [
                        ServiceStatusProbe(ts: 9, ok: true, latencyMS: 900, error: nil),
                    ]
                ),
                ServiceStatusService(
                    model: "gpt-5.5",
                    uptimePct: 99.5,
                    last: ServiceStatusProbe(ts: 9, ok: true, latencyMS: 1_111, error: nil),
                    history: [
                        ServiceStatusProbe(ts: 1, ok: true, latencyMS: 100, error: nil),
                        ServiceStatusProbe(ts: 2, ok: true, latencyMS: 3_000, error: nil),
                        ServiceStatusProbe(ts: 3, ok: false, latencyMS: nil, error: "timeout"),
                    ]
                ),
            ]
        )
        return StatusAPIResult(response: response, prettyRawJSON: #"{"all_ok":true}"#)
    }

    private static func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!
    }
}

@MainActor
final class RecordingServiceStatusNotifier: ServiceStatusNotificationSinking {
    private(set) var changes: [ServiceStatusChange] = []

    func serviceStatusDidChange(_ change: ServiceStatusChange) {
        changes.append(change)
    }
}

actor StubServiceStatusClient: ServiceStatusFetching {
    private var results: [Result<StatusAPIResult, Error>]
    private var count = 0

    init(results: [Result<StatusAPIResult, Error>]) {
        self.results = results
    }

    func fetchStatus() async throws -> StatusAPIResult {
        count += 1
        return try results.removeFirst().get()
    }

    func fetchCount() -> Int {
        count
    }
}

actor BlockingServiceStatusClient: ServiceStatusFetching {
    private var count = 0
    private var continuation: CheckedContinuation<StatusAPIResult, Error>?

    func fetchStatus() async throws -> StatusAPIResult {
        count += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func fetchCount() -> Int {
        count
    }

    func resume(_ result: Result<StatusAPIResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}
