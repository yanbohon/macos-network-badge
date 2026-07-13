import XCTest
@testable import UsageMonitor

final class ServiceStatusModelsTests: XCTestCase {
    func testStatusResponseDecodesObservedShapeAndSelectsGPT55() throws {
        let response = try JSONDecoder.serviceStatus.decode(
            ServiceStatusResponse.self,
            from: Data(Self.sampleStatusJSON.utf8)
        )

        let service = try XCTUnwrap(response.service(model: "gpt-5.5"))

        XCTAssertTrue(response.allOK)
        XCTAssertEqual(response.generatedAt, 1_778_762_578)
        XCTAssertEqual(service.model, "gpt-5.5")
        XCTAssertEqual(service.uptimePct, 81.67)
        XCTAssertEqual(service.last?.ts, 1_778_762_557)
        XCTAssertEqual(service.last?.ok, true)
        XCTAssertEqual(service.last?.latencyMS, 1_111)
        XCTAssertNil(service.last?.error)
        XCTAssertEqual(service.history.count, 9)
    }

    func testStatusResponseAllowsNullFailureFieldsAndShortHistory() throws {
        let json = """
        {
          "all_ok": false,
          "generated_at": 1778762578,
          "services": [
            {
              "model": "gpt-5.5",
              "uptime_pct": 50,
              "last": {
                "ts": 1778762557,
                "ok": false,
                "latency_ms": null,
                "error": "timeout"
              },
              "history": [
                {
                  "ts": 1778762497,
                  "ok": false,
                  "latency_ms": null,
                  "error": "timeout"
                }
              ]
            }
          ]
        }
        """

        let response = try JSONDecoder.serviceStatus.decode(
            ServiceStatusResponse.self,
            from: Data(json.utf8)
        )
        let service = try XCTUnwrap(response.service(model: "gpt-5.5"))

        XCTAssertEqual(service.history.count, 1)
        XCTAssertEqual(service.last?.ok, false)
        XCTAssertNil(service.last?.latencyMS)
        XCTAssertEqual(service.last?.error, "timeout")
    }

    func testStatusCellClassificationIncludesThresholdAndUnknowns() {
        XCTAssertEqual(
            ServiceStatusCellKind.classify(ServiceStatusProbe(ts: 1, ok: true, latencyMS: 2_999, error: nil)),
            .green
        )
        XCTAssertEqual(
            ServiceStatusCellKind.classify(ServiceStatusProbe(ts: 1, ok: true, latencyMS: 3_000, error: nil)),
            .yellow
        )
        XCTAssertEqual(
            ServiceStatusCellKind.classify(ServiceStatusProbe(ts: 1, ok: false, latencyMS: nil, error: "timeout")),
            .red
        )
        XCTAssertEqual(
            ServiceStatusCellKind.classify(ServiceStatusProbe(ts: nil, ok: nil, latencyMS: nil, error: nil)),
            .gray
        )
        XCTAssertEqual(ServiceStatusCellKind.classify(nil), .gray)
    }

    func testLatestEightCellsAreOldToNewAndPadMissingEntriesAsGray() throws {
        let response = try JSONDecoder.serviceStatus.decode(
            ServiceStatusResponse.self,
            from: Data(Self.sampleStatusJSON.utf8)
        )
        let service = try XCTUnwrap(response.service(model: "gpt-5.5"))

        XCTAssertEqual(
            service.latestDisplayCells(count: 8).map(\.kind),
            [.green, .yellow, .red, .green, .yellow, .red, .green, .yellow]
        )

        let shortService = ServiceStatusService(
            model: "gpt-5.5",
            uptimePct: 99,
            last: nil,
            history: [
                ServiceStatusProbe(ts: 10, ok: true, latencyMS: 100, error: nil),
                ServiceStatusProbe(ts: 11, ok: false, latencyMS: nil, error: "failed"),
            ]
        )

        XCTAssertEqual(
            shortService.latestDisplayCells(count: 8).map(\.kind),
            [.gray, .gray, .gray, .gray, .gray, .gray, .green, .red]
        )
    }

    func testTimelineRowsFollowConfiguredModelOrderAndPadToSixtyCells() throws {
        let response = ServiceStatusResponse(
            allOK: true,
            generatedAt: 1,
            services: [
                ServiceStatusService(
                    model: "gpt-5.6-luna",
                    uptimePct: 65,
                    last: ServiceStatusProbe(ts: 4, ok: true, latencyMS: 2_000, error: nil),
                    history: [
                        ServiceStatusProbe(ts: 2, ok: false, latencyMS: nil, error: "timeout"),
                        ServiceStatusProbe(ts: 3, ok: true, latencyMS: 3_000, error: nil),
                        ServiceStatusProbe(ts: 4, ok: true, latencyMS: 2_000, error: nil),
                    ]
                ),
                ServiceStatusService(
                    model: "gpt-5.5",
                    uptimePct: 95,
                    last: ServiceStatusProbe(ts: 5, ok: true, latencyMS: 1_000, error: nil),
                    history: [
                        ServiceStatusProbe(ts: 5, ok: true, latencyMS: 1_000, error: nil),
                    ]
                ),
            ]
        )

        let rows = response.timelineRows(
            for: ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"],
            count: 60
        )

        XCTAssertEqual(
            rows.map(\.model),
            ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"]
        )
        XCTAssertEqual(rows.map(\.cells.count), [60, 60, 60, 60])
        XCTAssertEqual(rows.map(\.sampleCount), [0, 0, 3, 1])
        XCTAssertEqual(rows.map(\.samplesText), ["0/60", "0/60", "3/60", "1/60"])
        XCTAssertEqual(rows.map(\.statusText), ["缺少数据", "缺少数据", "在线", "在线"])
        XCTAssertEqual(rows[0].cells.map(\.kind), Array(repeating: .gray, count: 60))
        XCTAssertEqual(rows[1].cells.map(\.kind), Array(repeating: .gray, count: 60))
        XCTAssertEqual(rows[2].cells.suffix(3).map(\.kind), [.red, .yellow, .green])
        XCTAssertEqual(rows[3].cells.suffix(1).map(\.kind), [.green])
    }

    static let sampleStatusJSON = """
    {
      "all_ok": true,
      "generated_at": 1778762578,
      "services": [
        {
          "model": "gpt-4.1",
          "uptime_pct": 100,
          "last": null,
          "history": []
        },
        {
          "model": "gpt-5.5",
          "uptime_pct": 81.67,
          "last": {
            "ts": 1778762557,
            "ok": true,
            "latency_ms": 1111,
            "error": null
          },
          "history": [
            { "ts": 1, "ok": true, "latency_ms": 1000, "error": null },
            { "ts": 2, "ok": true, "latency_ms": 1200, "error": null },
            { "ts": 3, "ok": true, "latency_ms": 3000, "error": null },
            { "ts": 4, "ok": false, "latency_ms": null, "error": "timeout" },
            { "ts": 5, "ok": true, "latency_ms": 10, "error": null },
            { "ts": 6, "ok": true, "latency_ms": 3001, "error": null },
            { "ts": 7, "ok": false, "latency_ms": null, "error": "500" },
            { "ts": 8, "ok": true, "latency_ms": 2500, "error": null },
            { "ts": 9, "ok": true, "latency_ms": 5000, "error": null }
          ]
        }
      ]
    }
    """
}
