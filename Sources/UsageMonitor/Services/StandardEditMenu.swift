import AppKit

enum StandardEditMenu {
    static let menuTitle = "编辑"

    static func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem(title: menuTitle, action: nil, keyEquivalent: "")
        editItem.submenu = makeMenu()
        mainMenu.addItem(editItem)
        return mainMenu
    }

    static func makeMenu() -> NSMenu {
        let menu = NSMenu(title: menuTitle)
        menu.addItem(command("撤销", action: #selector(UndoManager.undo), key: "z"))
        menu.addItem(
            command(
                "重做",
                action: #selector(UndoManager.redo),
                key: "z",
                modifiers: [.command, .shift]
            )
        )
        menu.addItem(.separator())
        menu.addItem(command("剪切", action: #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(command("拷贝", action: #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(command("粘贴", action: #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(.separator())
        menu.addItem(command("全选", action: #selector(NSText.selectAll(_:)), key: "a"))
        return menu
    }

    private static func command(
        _ title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = nil
        return item
    }
}
