import AppKit
import CommandKit
import DesignSystem
import SwiftUI

/// Utilities tab: the Commandly windows and Shelf actions the menu bar used to list directly,
/// followed by every enabled application.
///
/// The first rows carry the same actions and shortcuts the older dropdown menu had, so nothing
/// was lost when the menu became a panel. The application rows are projected from registry
/// metadata rather than hand-listed, so a newly registered application appears here without
/// anyone editing this view, and a disabled one disappears.
struct StatusPanelUtilitiesSection: View {
    @Bindable var runtime: AppRuntime
    let onOpenSettings: () -> Void
    let onOpenDocumentation: () -> Void
    let onRestartOnboarding: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.rawValue) {
            VStack(alignment: .leading, spacing: 2) {
                actionRow(
                    title: "Open Commandly",
                    caption: "The keyboard launcher.",
                    symbolName: "command",
                    shortcut: "⌥⌘O",
                    action: runtime.showLauncher
                )
                .keyboardShortcut("o", modifiers: [.command, .option])

                if runtime.isWindowSwitcherAvailable {
                    actionRow(
                        title: "Window Switcher",
                        caption: "Move between open windows.",
                        symbolName: "macwindow.on.rectangle",
                        shortcut: nil,
                        isEnabled: runtime.isWindowSwitcherEnabled,
                        action: runtime.showWindowSwitcher
                    )
                }

                actionRow(
                    title: "Documentation",
                    caption: "Everything Commandly can do.",
                    symbolName: "book",
                    shortcut: "⌘?",
                    action: onOpenDocumentation
                )
                .keyboardShortcut("?", modifiers: .command)

                actionRow(
                    title: "Settings…",
                    caption: "Preferences, shortcuts, and permissions.",
                    symbolName: "gearshape",
                    shortcut: "⌘,",
                    action: onOpenSettings
                )
                .keyboardShortcut(",", modifiers: .command)
            }
            .statusPanelCard(padding: 8)

            VStack(alignment: .leading, spacing: 2) {
                actionRow(
                    title: "New Shelf",
                    caption: "An empty board to drop files on.",
                    symbolName: "tray",
                    shortcut: shelfShortcutTitle(ShelfApplication.newShelfToolID),
                    action: runtime.openNewShelf
                )
                .keyboardShortcut(
                    runtime.resolvedHotKey(for: ShelfApplication.newShelfToolID)?
                        .swiftUIKeyboardShortcut
                )

                actionRow(
                    title: "New Shelf From Clipboard",
                    caption: "Start a board from what you last copied.",
                    symbolName: "tray.and.arrow.down",
                    shortcut: shelfShortcutTitle(ShelfApplication.newShelfFromClipboardToolID),
                    action: runtime.openNewShelfFromClipboard
                )
                .keyboardShortcut(
                    runtime.resolvedHotKey(for: ShelfApplication.newShelfFromClipboardToolID)?
                        .swiftUIKeyboardShortcut
                )
            }
            .statusPanelCard(padding: 8)

            if runtime.utilitiesPanelApplications.isEmpty == false {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(runtime.utilitiesPanelApplications) { definition in
                        actionRow(
                            title: definition.title,
                            caption: definition.subtitle ?? "",
                            symbolName: definition.systemImage,
                            shortcut: runtime.resolvedHotKey(for: definition.id)?.displayTitle,
                            action: { runtime.openRegisteredApplication(definition.id) }
                        )
                    }
                }
                .statusPanelCard(padding: 8)
            }

            #if DEBUG
            VStack(alignment: .leading, spacing: 2) {
                actionRow(
                    title: "Restart Onboarding",
                    caption: "Development builds only.",
                    symbolName: "arrow.counterclockwise",
                    shortcut: nil,
                    action: onRestartOnboarding
                )
            }
            .statusPanelCard(padding: 8)
            #endif
        }
    }

    private func shelfShortcutTitle(_ toolID: CommandID) -> String? {
        runtime.resolvedHotKey(for: toolID)?.displayTitle
    }

    private func actionRow(
        title: String,
        caption: String,
        symbolName: String,
        shortcut: String?,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs.rawValue) {
                Image(systemName: symbolName)
                    .commandlyFont(size: 12, weight: .medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .commandlyFont(size: 11.5, weight: .medium)
                    Text(caption)
                        .commandlyFont(size: 9.5)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: Spacing.xs.rawValue)

                if let shortcut {
                    Text(shortcut)
                        .commandlyFont(size: 10, weight: .medium)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(
                RoundedRectangle(
                    cornerRadius: StatusPanelChrome.controlCornerRadius,
                    style: .continuous
                )
            )
        }
        .buttonStyle(StatusPanelRowButtonStyle())
        .disabled(isEnabled == false)
        .accessibilityLabel(title)
        .accessibilityHint(caption)
    }
}

/// Quiet hover treatment for the panel's action rows.
private struct StatusPanelRowButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(
                    cornerRadius: StatusPanelChrome.controlCornerRadius,
                    style: .continuous
                )
                .fill(fill(isPressed: configuration.isPressed))
            )
            .onHover { hovering in
                withAnimation(CommandlyMotion.hover) { isHovering = hovering }
            }
    }

    private func fill(isPressed: Bool) -> Color {
        if isPressed { return LauncherPalette.selection }
        return isHovering ? LauncherPalette.hover : .clear
    }
}

extension LauncherHotKey {
    /// SwiftUI equivalent of this shortcut, when the key code maps to a printable key.
    var swiftUIKeyboardShortcut: KeyboardShortcut? {
        guard let keyEquivalent = swiftUIKeyEquivalent else { return nil }
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        return KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
    }

    private var swiftUIKeyEquivalent: KeyEquivalent? {
        switch keyCode {
        case 49: return .space
        case 123: return .leftArrow
        case 124: return .rightArrow
        case 125: return .downArrow
        case 126: return .upArrow
        default:
            guard let character = Self.keyCharacters[keyCode] else { return nil }
            return KeyEquivalent(character)
        }
    }

    private static let keyCharacters: [UInt16: Character] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
        38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "n", 46: "m", 47: ".", 50: "`",
    ]
}
