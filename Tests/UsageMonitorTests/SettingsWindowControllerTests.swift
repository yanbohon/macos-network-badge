import AppKit
import XCTest
@testable import UsageMonitor

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testBringToFrontActivatesApplicationBeforeOrderingWindowRegardless() {
        let recorder = WindowFocusEventRecorder()
        let controller = SettingsWindowController(
            activateApplication: {
                recorder.events.append("activate")
            }
        )
        let window = RecordingWindow(recorder: recorder)

        controller.bringToFront(window)

        XCTAssertEqual(recorder.events, [
            "activate",
            "makeKeyAndOrderFront",
            "orderFrontRegardless",
        ])
    }
}

private final class WindowFocusEventRecorder {
    var events: [String] = []
}

private final class RecordingWindow: NSWindow {
    private let recorder: WindowFocusEventRecorder

    init(recorder: WindowFocusEventRecorder) {
        self.recorder = recorder
        super.init(
            contentRect: .zero,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        recorder.events.append("makeKeyAndOrderFront")
    }

    override func orderFrontRegardless() {
        recorder.events.append("orderFrontRegardless")
    }
}
