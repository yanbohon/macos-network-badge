import AppKit
import XCTest
@testable import UsageMonitor

@MainActor
final class SettingsViewRenderingTests: XCTestCase {
    func testSettingsWindowRendersVisibleContentAtDefaultAndMinimumSizes() {
        let controller = SettingsWindowController(activateApplication: {})
        let monitor = UsageSnapshotMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            client: Sub2APIClient(requestLoader: RequestRecordingLoader()),
            timerFactory: ManualTimerFactory()
        )
        let serviceStatusMonitor = ServiceStatusMonitor(
            userDefaults: UserDefaults(suiteName: "UsageMonitorTests.\(UUID().uuidString)")!,
            timerFactory: ManualTimerFactory()
        )

        let window = controller.makeWindow(
            monitor: monitor,
            serviceStatusMonitor: serviceStatusMonitor
        )

        for size in [
            NSSize(width: 460, height: 430),
            NSSize(width: 420, height: 400)
        ] {
            window.setContentSize(size)
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentViewController?.view.layoutSubtreeIfNeeded()

            let image = renderContent(of: window)
            XCTAssertTrue(hasVisibleContent(in: image), "Expected visible content at size \(size)")
        }
    }

    private func renderContent(of window: NSWindow) -> NSBitmapImageRep {
        let contentView = try! XCTUnwrap(window.contentView)
        let bounds = contentView.bounds
        let width = max(1, Int(ceil(bounds.width)))
        let height = max(1, Int(ceil(bounds.height)))
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = context
        contentView.cacheDisplay(in: bounds, to: rep)

        return rep
    }

    private func hasVisibleContent(in image: NSBitmapImageRep) -> Bool {
        guard image.pixelsWide > 0, image.pixelsHigh > 0 else { return false }

        let background = image.colorAt(x: 0, y: 0)
        let sampleStepX = max(1, image.pixelsWide / 24)
        let sampleStepY = max(1, image.pixelsHigh / 24)

        for x in stride(from: 0, to: image.pixelsWide, by: sampleStepX) {
            for y in stride(from: 0, to: image.pixelsHigh, by: sampleStepY) {
                guard let sample = image.colorAt(x: x, y: y) else { continue }
                if !sample.isApproximatelyEqual(to: background) {
                    return true
                }
            }
        }

        return false
    }
}

private extension NSColor {
    func isApproximatelyEqual(to other: NSColor?, tolerance: CGFloat = 0.01) -> Bool {
        guard
            let other,
            let lhs = usingColorSpace(.deviceRGB),
            let rhs = other.usingColorSpace(.deviceRGB)
        else {
            return false
        }

        return abs(lhs.redComponent - rhs.redComponent) <= tolerance
            && abs(lhs.greenComponent - rhs.greenComponent) <= tolerance
            && abs(lhs.blueComponent - rhs.blueComponent) <= tolerance
            && abs(lhs.alphaComponent - rhs.alphaComponent) <= tolerance
    }
}
