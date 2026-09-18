import AppKit
import CommandKit

/// Uses public NSStatusItem menus with template SF Symbols and native keyboard/VoiceOver behavior.
/// Native objects are created only for an explicit saved pin, not for every catalog item.
@MainActor
final class NativeMenuBarShortcutPresenter: NSObject, MenuBarShortcutsPresenting {
    private var entries: [CommandID: NSStatusItem] = [:]
    private var invoke: (CommandID) -> Void = { _ in }
    private var remove: (CommandID) -> Void = { _ in }
    private var manage: () -> Void = {}

    func update(_ items: [MenuBarShortcutItem], invoke: @escaping (CommandID) -> Void,
                remove: @escaping (CommandID) -> Void, manage: @escaping () -> Void) {
        self.invoke = invoke; self.remove = remove; self.manage = manage
        let ids = Set(items.map(\.id))
        for id in Array(entries.keys) where !ids.contains(id) {
            if let item = entries.removeValue(forKey: id) { NSStatusBar.system.removeStatusItem(item) }
        }
        for item in items {
            let status: NSStatusItem
            if let existing = entries[item.id] { status = existing }
            else {
                status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                status.autosaveName = "Commandly.Shortcut.\(item.id.rawValue)"
                entries[item.id] = status
            }
            let image = NSImage(systemSymbolName: item.systemImage, accessibilityDescription: item.title)
                ?? NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: item.title)
            image?.isTemplate = true
            status.button?.image = image
            status.button?.toolTip = "\(item.title) — Commandly\(item.isEnabled ? "" : " (disabled)")"
            status.button?.setAccessibilityLabel("\(item.title), Commandly menu-bar shortcut")
            let menu = NSMenu(title: item.title)
            menu.autoenablesItems = false
            let open = NSMenuItem(title: "Open \(item.title)", action: #selector(openShortcut(_:)), keyEquivalent: "")
            open.target = self; open.representedObject = item.id.rawValue; open.isEnabled = item.isEnabled
            menu.addItem(open)
            if !item.isEnabled {
                let disabled = NSMenuItem(title: "Enable this application in Commandly Settings", action: nil, keyEquivalent: "")
                disabled.isEnabled = false; menu.addItem(disabled)
            }
            menu.addItem(.separator())
            let manage = NSMenuItem(title: "Manage Menu-Bar Shortcuts…", action: #selector(manageShortcuts), keyEquivalent: "")
            manage.target = self; menu.addItem(manage)
            let remove = NSMenuItem(title: "Remove from Menu Bar", action: #selector(removeShortcut(_:)), keyEquivalent: "")
            remove.target = self; remove.representedObject = item.id.rawValue; menu.addItem(remove)
            status.menu = menu
        }
    }

    func stop() {
        for item in entries.values { NSStatusBar.system.removeStatusItem(item) }
        entries.removeAll()
        invoke = { _ in }; remove = { _ in }; manage = {}
    }

    @objc private func openShortcut(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        invoke(CommandID(rawValue: value))
    }
    @objc private func removeShortcut(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        remove(CommandID(rawValue: value))
    }
    @objc private func manageShortcuts() { manage() }
}
