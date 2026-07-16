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
    @Environment(\.commandlyLayoutDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isSearchFocused: Bool

    private var selectedTitle: String {
        items.first(where: { $0.id == selectionID })?.title ?? placeholderTitle
    }

    private var filteredItems: [CommandlyOptionItem] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowsSearch, trimmed.isEmpty == false else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            trigger
                .overlay(alignment: .topTrailing) {
                    if isExpanded {
                        menuPanel
                            .offset(y: 40)
                            .transition(
                                .opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing))
                            )
                    }
                }
                .background {
                    OutsideMouseDownMonitor(isActive: isExpanded) {
                        dismissMenu()
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .animation(reduceMotion ? nil : CommandlyMotion.navigation, value: isExpanded)
                .onChange(of: isExpanded) { _, expanded in
                    if expanded {
                        if allowsSearch {
                            isSearchFocused = true
                        }
                    } else {
                        searchQuery = ""
                        hoveredItemID = nil
                        isSearchFocused = false
                    }
                }
        }
    }

    private var trigger: some View {
        Button {
            withAnimation(reduceMotion ? nil : CommandlyMotion.navigation) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedTitle)
                    .commandlyFont(size: 12, weight: .medium)
                    .foregroundStyle(isHovered || isExpanded ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .commandlyFont(size: 9, weight: .semibold)
                    .foregroundStyle(isHovered || isExpanded ? Color.primary : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : CommandlyMotion.hover) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(selectedTitle)
        .accessibilityHint(isExpanded ? "Expanded" : "Collapsed")
    }

    private var menuPanel: some View {
        VStack(spacing: 0) {
            if allowsSearch {
                HStack(spacing: density.spacing(.xs)) {
                    Image(systemName: "magnifyingglass")
                        .commandlyFont(size: 11, weight: .medium)
                        .foregroundStyle(.tertiary)
                    TextField(searchPrompt, text: $searchQuery)
                        .textFieldStyle(.plain)
                        .commandlyFont(size: 12, weight: .medium)
                        .focused($isSearchFocused)
                        .onSubmit {
                            if let first = filteredItems.first {
                                select(first)
                            }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().opacity(0.28)
            }

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredItems) { item in
                        optionRow(item)
                    }
                    if filteredItems.isEmpty {
                        Text("No matches")
                            .commandlyFont(size: 11, weight: .medium)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
                .padding(6)
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
        return Button {
            select(item)
        } label: {
            Text(item.title)
                .commandlyFont(size: 12, weight: isSelected ? .semibold : .medium)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isSelected
                                ? Color.primary.opacity(0.14)
                                : Color.primary.opacity(isRowHovered ? 0.08 : 0)
                        )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredItemID = hovering ? item.id : (hoveredItemID == item.id ? nil : hoveredItemID)
        }
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func select(_ item: CommandlyOptionItem) {
        onSelect(item)
        dismissMenu()
    }

    private func dismissMenu() {
        withAnimation(reduceMotion ? nil : CommandlyMotion.navigation) {
            isExpanded = false
        }
    }
}

/// Local mouse-down monitor that dismisses when the click lands outside the
/// menu chrome (trigger + dropdown). Has zero layout impact.
private struct OutsideMouseDownMonitor: NSViewRepresentable {
    var isActive: Bool
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
        context.coordinator.setActive(isActive)
    }

    static func dismantleNSView(_ nsView: MonitorHostView, coordinator: Coordinator) {
        coordinator.setActive(false)
    }

    final class Coordinator {
        var onOutside: () -> Void
        private weak var host: MonitorHostView?
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
            removeMonitor()
            guard active else { return }
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
