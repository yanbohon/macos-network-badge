import AppKit
import XCTest
@testable import UsageMonitor

final class StandardEditMenuTests: XCTestCase {
    func testMainMenuContainsEditSubmenu() {
        let mainMenu = StandardEditMenu.makeMainMenu()

        XCTAssertEqual(mainMenu.items.map(\.title), [StandardEditMenu.menuTitle])
        XCTAssertEqual(mainMenu.items.first?.submenu?.title, StandardEditMenu.menuTitle)
    }

    func testEditMenuProvidesPasteShortcutThroughResponderChain() {
        let menu = StandardEditMenu.makeMenu()

        let pasteItem = menu.items.first { $0.action == #selector(NSText.paste(_:)) }

        XCTAssertEqual(pasteItem?.keyEquivalent, "v")
        XCTAssertEqual(
            pasteItem?.keyEquivalentModifierMask.intersection(NSEvent.ModifierFlags.deviceIndependentFlagsMask),
            .command
        )
        XCTAssertNil(pasteItem?.target)
    }

    func testEditMenuProvidesCommonTextEditingCommands() {
        let menu = StandardEditMenu.makeMenu()
        let actions = Set(menu.items.compactMap { $0.action })

        XCTAssertTrue(actions.contains(#selector(NSText.cut(_:))))
        XCTAssertTrue(actions.contains(#selector(NSText.copy(_:))))
        XCTAssertTrue(actions.contains(#selector(NSText.paste(_:))))
        XCTAssertTrue(actions.contains(#selector(NSText.selectAll(_:))))
    }
}
