import Foundation
import XCTest
@testable import UsageMonitor

@MainActor
final class ServiceStatusMonitorTests: XCTestCase {
    func testStartSchedulesOneMinuteTimerAndRefreshesOnce() async throws {
        let client = StubServiceStatusClient(results: [
            .success(Self.statusResult()),
        ])
        let timers = ManualTimerFactory()
        let monitor = ServiceStatusMonitor(client: client, timerFactory: timers)

        monitor.start()
        monitor.start()

        while monitor.lastSuccessfulRefresh == nil {
            await Task.yield()
        }

        XCTAssertEqual(timers.scheduledIntervals, [60])
        let fetchCount = await client.fetchCount()
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(monitor.selectedService?.model, "gpt-5.5")
        XCTAssertNil(monitor.lastError)
    }

    func testTimerRefreshUsesSameOneMinuteSchedule() async throws {
        let client = StubServiceStatusClient(results: [
            .success(Self.statusResult(generatedAt: 1)),
            .success(Self.statusResult(generatedAt: 2)),
        ])
        let timers = ManualTimerFactory()
        let monitor = ServiceStatusMonitor(client: client, timerFactory: timers)

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
        let monitor = ServiceStatusMonitor(client: client, timerFactory: ManualTimerFactory())

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

        XCTAssertEqual(monitor.selectedService?.model, "gpt-5.5")
        let completedCount = await client.fetchCount()
        XCTAssertEqual(completedCount, 1)
    }

    func testFailureAfterSuccessKeepsPreviousCellsAndMarksStale() async throws {
        let client = StubServiceStatusClient(results: [
            .success(Self.statusResult()),
            .failure(StatusAPIClientError.network("offline")),
        ])
        let monitor = ServiceStatusMonitor(client: client, timerFactory: ManualTimerFactory())

        await monitor.refreshNow()
        let cells = monitor.displayCells
        let rawJSONText = monitor.rawJSONText

        await monitor.refreshNow()

        XCTAssertEqual(monitor.displayCells, cells)
        XCTAssertEqual(monitor.rawJSONText, rawJSONText)
        XCTAssertEqual(monitor.lastError, "状态请求失败")
        XCTAssertTrue(monitor.isStaleAfterFailure)
        XCTAssertEqual(monitor.selectedService?.model, "gpt-5.5")
    }

    func testFailureBeforeAnySuccessKeepsGrayCellsAndReportsError() async throws {
        let client = StubServiceStatusClient(results: [
            .failure(StatusAPIClientError.httpStatus(503, "status unavailable")),
        ])
        let monitor = ServiceStatusMonitor(client: client, timerFactory: ManualTimerFactory())

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
        let monitor = ServiceStatusMonitor(client: client, timerFactory: ManualTimerFactory())

        await monitor.refreshNow()

        XCTAssertNil(monitor.selectedService)
        XCTAssertEqual(monitor.lastError, "未找到 gpt-5.5 状态")
        XCTAssertEqual(monitor.displayCells.map(\.kind), Array(repeating: .gray, count: 8))
    }

    private static func statusResult(generatedAt: TimeInterval = 1_778_762_578) -> StatusAPIResult {
        let response = ServiceStatusResponse(
            allOK: true,
            generatedAt: generatedAt,
            services: [
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
