import AppKit
import SwiftUI
import DesignSystem

/// A selectable item for ``CommandlyOptionMenu``.
struct CommandlyOptionItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

/// Searchable option menu used for sort/filter chrome across launcher surfaces.
///
/// Screens supply the option list and selection; styling stays shared.
///
/// The expanded panel is an overlay so it never participates in layout. Outside
/// clicks are handled with a local AppKit mouse monitor (not a giant clear view).
struct CommandlyOptionMenu: View {
    let items: [CommandlyOptionItem]
    let selectionID: String
    var placeholderTitle: String = "Options"
    var searchPrompt: String = "Search…"
    var allowsSearch: Bool = true
    var accessibilityLabelText: String = "Options"
    var onSelect: (CommandlyOptionItem) -> Void

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var searchQuery = ""
    @State private var hoveredItemID: String?
    @State private var keyboardSelection = LauncherMenuSelection<String>()
    @State private var menuID = UUID()
    @State private var restoresFocusOnDismiss = true
    @Environment(\.commandlyLayoutDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.launcherTransientMenuState) private var transientMenuState
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isMenuFocused: Bool

    private var selectedTitle: String {
        items.first(where: { $0.id == selectionID })?.title ?? placeholderTitle
    }

    private var filteredItems: [CommandlyOptionItem] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowsSearch, trimmed.isEmpty == false else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    private var visibleIDs: [String] { filteredItems.map(\.id) }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            trigger
                .overlay(alignment: .topTrailing) {
                    if isExpanded {
                        menuPanel
                            .offset(y: 32)
                            .transition(
                                .opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing))
                            )
                    }
                }
                .background {
                    OutsideMouseDownMonitor(
                        isActive: isExpanded,
                        restoresFocusOnDismiss: restoresFocusOnDismiss
                    ) {
                        dismissMenu(restoringFocus: false)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .animation(reduceMotion ? nil : CommandlyMotion.navigation, value: isExpanded)
                .onChange(of: isExpanded) { _, expanded in
                    if expanded {
                        restoresFocusOnDismiss = true
                        keyboardSelection = LauncherMenuSelection<String>()
                        keyboardSelection.reconcile(with: visibleIDs, preferredID: selectionID)
                        transientMenuState?.present(id: menuID) { restoringFocus in
                            dismissMenu(restoringFocus: restoringFocus)
                        }
                        if allowsSearch {
                            // The overlay is inserted by the same state change. Reapply focus on
                            // the next main-queue turn so the menu field exists before focus moves.
                            isSearchFocused = false
                            DispatchQueue.main.async {
                                guard isExpanded else { return }
                                isSearchFocused = true
                            }
                        } else {
                            isMenuFocused = true
                        }
                    } else {
                        transientMenuState?.remove(id: menuID)
                        searchQuery = ""
                        hoveredItemID = nil
                        isSearchFocused = false
                        isMenuFocused = false
                    }
                }
                .onChange(of: visibleIDs) { _, ids in
                    keyboardSelection.reconcile(with: ids)
                }
                .onDisappear {
                    transientMenuState?.remove(id: menuID)
                }
        }
    }

    private var trigger: some View {
        Button {
            withAnimation(reduceMotion ? nil : CommandlyMotion.navigation) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedTitle)
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(isHovered || isExpanded ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .symbolVariant(.none)
                    .commandlyFont(size: 8, weight: .semibold)
                    .foregroundStyle(isHovered || isExpanded ? Color.primary : Color.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.mini)
        .fixedSize(horizontal: true, vertical: false)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : CommandlyMotion.hover) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(selectedTitle)
        .accessibilityHint(isExpanded ? "Expanded" : "Collapsed")
        .help("\(accessibilityLabelText): \(selectedTitle)")
    }

    private var menuPanel: some View {
        VStack(spacing: 0) {
            if allowsSearch {
                HStack(spacing: density.spacing(.xs)) {
                    Image(systemName: "magnifyingglass")
                        .commandlyFont(size: 11, weight: .medium)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    TextField(searchPrompt, text: $searchQuery)
                        .textFieldStyle(.plain)
                        .commandlyFont(size: 12, weight: .medium)
                        .focused($isSearchFocused)
                        .accessibilityLabel("Search \(accessibilityLabelText)")
                        .onKeyPress(.upArrow) {
                            keyboardSelection.move(by: -1, in: visibleIDs)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            keyboardSelection.move(by: 1, in: visibleIDs)
                            return .handled
                        }
                        .onSubmit(selectKeyboardItem)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().opacity(0.28)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredItems) { item in
                            optionRow(item)
                                .id(item.id)
                        }
                        if filteredItems.isEmpty {
                            Text("No matches")
                                .commandlyFont(size: 11, weight: .medium)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: keyboardSelection.selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(reduceMotion ? nil : CommandlyMotion.hover) {
                        proxy.scrollTo(id)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .frame(width: 200, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.clear)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LauncherPalette.separator, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.24), radius: 20, y: 10)
        .focusable(allowsSearch == false)
        .focusEffectDisabled()
        .focused($isMenuFocused)
        .onKeyPress(.upArrow) {
            keyboardSelection.move(by: -1, in: visibleIDs)
            return .handled
        }
        .onKeyPress(.downArrow) {
            keyboardSelection.move(by: 1, in: visibleIDs)
            return .handled
        }
        .onKeyPress(.return) {
            selectKeyboardItem()
            return .handled
        }
        .onKeyPress(.escape) {
            dismissMenu()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabelText)
    }

    private func optionRow(_ item: CommandlyOptionItem) -> some View {
        let isSelected = item.id == selectionID
        let isRowHovered = hoveredItemID == item.id
        let isKeyboardSelected = keyboardSelection.selectedID == item.id
        return Button {
            select(item)
        } label: {
            HStack(spacing: 8) {
                Text(item.title)
                    .commandlyFont(size: 12, weight: isSelected ? .semibold : .medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .commandlyFont(size: 10, weight: .semibold)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                        .fill(
                            isKeyboardSelected
                                ? LauncherPalette.selection
                                : isRowHovered ? LauncherPalette.hover : .clear
                        )
                )
                .overlay {
                    if isKeyboardSelected, contrast == .increased {
                        RoundedRectangle(cornerRadius: CornerRadius.sm.rawValue, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
            if hovering { keyboardSelection.select(item.id, in: visibleIDs) }
        }
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func select(_ item: CommandlyOptionItem) {
        onSelect(item)
        dismissMenu()
    }

    private func selectKeyboardItem() {
        guard let id = keyboardSelection.activationID(in: visibleIDs),
              let item = filteredItems.first(where: { $0.id == id }) else { return }
        select(item)
    }

    private func dismissMenu(restoringFocus: Bool = true) {
        restoresFocusOnDismiss = restoringFocus
        withAnimation(reduceMotion ? nil : CommandlyMotion.navigation) {
            isExpanded = false
        }
    }
}

/// Local mouse-down monitor that dismisses when the click lands outside the
/// menu chrome (trigger + dropdown). Has zero layout impact.
private struct OutsideMouseDownMonitor: NSViewRepresentable {
    var isActive: Bool
    var restoresFocusOnDismiss: Bool
    var onOutside: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOutside: onOutside)
    }

    func makeNSView(context: Context) -> MonitorHostView {
        let view = MonitorHostView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: MonitorHostView, context: Context) {
        context.coordinator.onOutside = onOutside
        context.coordinator.restoresFocusOnDismiss = restoresFocusOnDismiss
        context.coordinator.setActive(isActive)
    }

    static func dismantleNSView(_ nsView: MonitorHostView, coordinator: Coordinator) {
        coordinator.setActive(false)
    }

    final class Coordinator {
        var onOutside: () -> Void
        var restoresFocusOnDismiss = true
        private weak var host: MonitorHostView?
        private weak var previousResponder: NSResponder?
        private var isActive = false
        /// Event monitor token; cleared in `setActive(false)` / `dismantleNSView`.
        nonisolated(unsafe) private var monitor: Any?

        init(onOutside: @escaping () -> Void) {
            self.onOutside = onOutside
        }

        func attach(to host: MonitorHostView) {
            self.host = host
            host.coordinator = self
        }

        func setActive(_ active: Bool) {
            guard isActive != active else { return }
            isActive = active
            removeMonitor()
            guard active else {
                if restoresFocusOnDismiss, let window = host?.window,
                   let previousResponder, window.isKeyWindow {
                    DispatchQueue.main.async { [weak window, weak previousResponder] in
                        guard let window, let previousResponder, window.isKeyWindow else { return }
                        window.makeFirstResponder(previousResponder)
                    }
                }
                previousResponder = nil
                return
            }
            if let editor = host?.window?.firstResponder as? NSTextView,
               let field = editor.delegate as? NSTextField {
                previousResponder = field
            } else {
                previousResponder = host?.window?.firstResponder
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                guard let self, let host = self.host else {
                    return event
                }

                let location = event.locationInWindow
                let triggerFrame = host.convert(host.bounds, to: nil)
                // Approximate the dropdown under the trailing trigger (AppKit y grows upward).
                let panelFrame = NSRect(
                    x: triggerFrame.maxX - 208,
                    y: triggerFrame.minY - 268,
                    width: 216,
                    height: 260
                )
                let interactiveBounds = triggerFrame.insetBy(dx: -8, dy: -8).union(panelFrame)

                if interactiveBounds.contains(location) == false {
                    DispatchQueue.main.async {
                        self.onOutside()
                    }
                }
                return event
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }

    final class MonitorHostView: NSView {
        weak var coordinator: Coordinator?
    }
}

#Preview {
    struct Host: View {
        @State private var selection = "path"
        var body: some View {
            CommandlyOptionMenu(
                items: [
                    .init(id: "path", title: "Sort by Path"),
                    .init(id: "name", title: "Sort by Name"),
                    .init(id: "size", title: "Sort by Size")
                ],
                selectionID: selection,
                onSelect: { selection = $0.id }
            )
            .padding(40)
        }
    }
    return Host()
}
