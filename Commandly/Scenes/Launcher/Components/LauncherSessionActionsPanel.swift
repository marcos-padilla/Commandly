import AppKit
import CommandKit
import DesignSystem
import SwiftUI

/// The shared command-surface menu used by both Command-K and the footer Actions button.
struct LauncherSessionActionsPanel: View {
    let session: LauncherApplicationSession
    @State private var query = ""
    @State private var priorFocus: NSView?
    @State private var restoredFocus = false
    @Environment(\.commandlyLayoutDensity) private var density

    private var actions: [LauncherActionPanelItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return session.menuActions.filter {
            needle.isEmpty || $0.title.localizedCaseInsensitiveContains(needle)
        }.map {
            LauncherActionPanelItem(id: $0.id, title: $0.title, systemImage: "arrow.turn.down.right",
                                    keyHint: $0.keyHint, isEnabled: $0.isEnabled)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
            LauncherActionPanel(
                title: session.manifest.title,
                actions: actions,
                query: $query,
                onSelect: { action in
                    guard session.showsActionsMenu,
                          session.menuActions.contains(where: { $0.id == action && $0.isEnabled }) else { return }
                    // Restore the old field before dispatch so an action can focus its new editor or sheet.
                    restoreFocus()
                    session.performMenuAction(action)
                },
                onDismiss: dismiss,
                onBack: nil
            )
            .padding(.trailing, density.spacing(.md))
            .padding(.bottom, density.spacing(.md))
        }
        .onAppear {
            let responder = NSApp.keyWindow?.firstResponder
            if let editor = responder as? NSTextView, editor.isFieldEditor,
               let field = editor.delegate as? NSView {
                priorFocus = field
            } else {
                priorFocus = responder as? NSView
            }
        }
        .onDisappear { restoreFocus() }
    }

    private func dismiss() {
        restoreFocus()
        session.showsActionsMenu = false
    }

    private func restoreFocus() {
        guard !restoredFocus else { return }
        restoredFocus = true
        guard let priorFocus, let window = priorFocus.window, window.isKeyWindow else { return }
        window.makeFirstResponder(priorFocus)
    }
}
