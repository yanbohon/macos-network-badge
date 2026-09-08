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

    func testApplyBoundTextDoesNotOverwriteSecureFieldWhileEditing() {
        let session = "SWdz2qvYhB17kGqBc26QP1iHZBmofumvIBEtciGW2TM"
        XCTAssertFalse(
            NativeTextInput.shouldWriteBoundText(session, fieldValue: "••", editorValue: session)
        )
    }

    func testApplyBoundTextUpdatesSecureFieldAfterEditingEnds() {
        XCTAssertTrue(
            NativeTextInput.shouldWriteBoundText("new-session", fieldValue: "old-session", editorValue: nil)
        )
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        field.stringValue = "old-session"
        NativeTextInput.applyBoundText("new-session", to: field)
        XCTAssertEqual(field.stringValue, "new-session")
    }

    func testRequestInitialFocusSelectsTheFieldOnce() {
        let field = FocusRecordingTextField(string: "base")
        let coordinator = NativeTextInputCoordinator(text: Binding(
            get: { field.stringValue },
            set: { field.stringValue = $0 }
        ))

        coordinator.requestInitialFocus(on: field)

        let expectation = expectation(description: "focus callback runs")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(field.selectTextCallCount, 1)
    }
}

private final class FocusRecordingTextField: NSTextField {
    var selectTextCallCount = 0

    override func selectText(_ sender: Any?) {
        selectTextCallCount += 1
        super.selectText(sender)
    }
}
