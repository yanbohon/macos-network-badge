import AppKit
import SwiftUI
import XCTest
@testable import UsageMonitor

final class NativeTextInputTests: XCTestCase {
    func testCoordinatorCopiesEditedPlainTextIntoBinding() {
        var value = "old"
        let coordinator = NativeTextInputCoordinator(text: Binding(
            get: { value },
            set: { value = $0 }
        ))
        let field = NSTextField(string: "new")

        coordinator.controlTextDidChange(Notification(name: NSText.didChangeNotification, object: field))

        XCTAssertEqual(value, "new")
    }
}
