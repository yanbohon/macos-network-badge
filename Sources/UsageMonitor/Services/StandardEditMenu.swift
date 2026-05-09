import AppKit

enum StandardEditMenu {
    static let menuTitle = "编辑"

    static func makeMenu() -> NSMenu {
        let menu = NSMenu(title: menuTitle)
        menu.addItem(command("剪切", action: #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(command("拷贝", action: #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(command("粘贴", action: #selector(NSText.paste(_:)), key: "v"))
        menu.addItem(.separator())
        menu.addItem(command("全选", action: #selector(NSText.selectAll(_:)), key: "a"))
        return menu
    }

    private static func command(_ title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = .command
        item.target = nil
        return item
    }
}
