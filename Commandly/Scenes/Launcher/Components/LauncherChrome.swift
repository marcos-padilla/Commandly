import AppKit
import CommandKit
import DesignSystem
import SwiftUI

enum LauncherChromeMetrics {
    static let footerHeight: CGFloat = 50
    static let actionPanelBottomInset: CGFloat = footerHeight + 8
}

struct LauncherSearchField: View {
    @Binding var query: String
    var autocompleteSuffix: String = ""
    var autocompleteActionLabel: String?
    var focusEpoch: Int = 0
    var onSubmit: () -> Void
    var onMoveSelection: (Int) -> Void = { _ in }
    var onAcceptAutocomplete: () -> Void = {}
    var onCancel: (() -> Void)?
    @FocusState private var isFocused: Bool
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        HStack(spacing: density.spacing(.sm)) {
            Image(systemName: "magnifyingglass")
                .commandlyFont(size: 15, weight: .medium)
                .foregroundStyle(.secondary)
                .frame(width: density.iconSize, height: density.iconSize)
                .accessibilityHidden(true)

            ZStack(alignment: .leading) {
                if autocompleteSuffix.isEmpty == false, query.isEmpty == false {
                    Text(query + autocompleteSuffix)
                        .commandlyFont(size: 15, weight: .medium)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                TextField("Search apps and commands…", text: $query)
                    .textFieldStyle(.plain)
                    .commandlyFont(size: 16, weight: .medium)
                    .focused($isFocused)
                    .onSubmit(onSubmit)
                    .onKeyPress(.upArrow) {
                        onMoveSelection(-1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        onMoveSelection(1)
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        if autocompleteSuffix.isEmpty == false {
                            onAcceptAutocomplete()
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.escape) {
                        if query.isEmpty == false {
                            query = ""
                            return .handled
                        }
                        onCancel?()
                        return onCancel == nil ? .ignored : .handled
                    }
                    .accessibilityLabel("Search apps and commands")
                    .accessibilityValue(
                        autocompleteSuffix.isEmpty
                            ? query
                            : "\(query), autocomplete \(autocompleteSuffix)"
                    )
            }

            if query.isEmpty == false {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .commandlyFont(size: 14, weight: .regular)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            if let autocompleteActionLabel {
                Button(action: onAcceptAutocomplete) {
                    HStack(spacing: density.spacing(.xxs)) {
                        Text("Tab")
                            .commandlyFont(size: 10, weight: .semibold)
                            .padding(.horizontal, density.spacing(.xs))
                            .padding(.vertical, 2)
                            .background(
                                LauncherPalette.surface,
                                in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Text(
                            autocompleteActionLabel == "Tab to convert"
                                ? "to convert" : "to complete"
                        )
                        .commandlyFont(size: 11, weight: .medium)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(autocompleteActionLabel)
                .accessibilityHint("Completes the suggested calculator or search input")
            }
        }
        // The search field is part of the launcher canvas, rather than a control
        // floating inside another rounded surface.
        .padding(.horizontal, density.spacing(.lg))
        .padding(.vertical, density.searchVerticalPadding)
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
        }
        .padding(.top, density.spacing(.xs))
        .padding(.bottom, density.spacing(.xxs))
        .onAppear {
            reclaimFocus()
        }
        .onChange(of: focusEpoch) { _, _ in
            reclaimFocus()
        }
    }

    /// Clears then re-applies focus so `@FocusState` is not a no-op when already `true`,
    /// and so reclaim happens after the launcher window has become key.
    private func reclaimFocus() {
        isFocused = false
        DispatchQueue.main.async {
            isFocused = true
        }
    }
}

struct LauncherSectionHeader: View {
    let title: String
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        Text(title)
            .commandlyFont(size: 11, weight: .medium)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, density.spacing(.md))
            .padding(.top, density.sectionHeaderTopPadding)
            .padding(.bottom, density.spacing(.xxxs))
            .accessibilityAddTraits(.isHeader)
    }
}

struct LauncherResultRow: View {
    let item: LauncherItem
    let isSelected: Bool
    var onHoverChange: ((Bool) -> Void)?
    var onContextAction: (() -> Void)?
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.commandlyLayoutDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: density.spacing(.sm)) {
                launcherItemIcon(
                    icon: item.icon,
                    emphasized: isSelected,
                    size: density.iconSize
                )

                HStack(spacing: density.spacing(.xs)) {
                    Text(item.title)
                        .commandlyFont(size: 13, weight: isSelected ? .semibold : .medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .commandlyFont(size: 12, weight: .regular)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(item.badge.title)
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .padding(.horizontal, density.rowHorizontalPadding)
            .padding(.vertical, density.rowVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                    .fill(rowFill)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, density.spacing(.xs))
        .background {
            if onContextAction != nil {
                LauncherRightClickCatcher {
                    onContextAction?()
                }
            }
        }
        .onHover { hovering in
            isHovered = hovering
            onHoverChange?(hovering)
        }
        .animation(reduceMotion ? nil : CommandlyMotion.hover, value: isHovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(accessibilityValueText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var rowFill: Color {
        if isSelected { return Color.primary.opacity(0.105) }
        if isHovered { return Color.primary.opacity(0.052) }
        return .clear
    }

    private var accessibilityLabelText: String {
        if item.badge == .calculator {
            return "Calculator result \(item.title)"
        }
        return item.title
    }

    private var accessibilityValueText: String {
        var parts: [String] = []
        if let subtitle = item.subtitle, subtitle.isEmpty == false {
            parts.append(subtitle)
        }
        parts.append(item.badge.title)
        return parts.joined(separator: ", ")
    }
}

/// Root launcher footer: contextual actions on the left, app utilities on the right.
struct LauncherRootFooterBar: View {
    let appMenuActions: [CommandActionDescriptor]
    let actions: [CommandActionDescriptor]
    var menuActions: [CommandActionDescriptor] = []
    var onAction: (CommandActionID) -> Void
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        HStack(spacing: density.spacing(.xs)) {
            ForEach(actions) { action in
                LauncherFooterActionButton(
                    title: action.title,
                    keys: action.keyHint?.symbols ?? [],
                    isEnabled: action.isEnabled,
                    action: { onAction(action.id) }
                )
            }

            Spacer(minLength: density.spacing(.sm))

            // Keep app-wide utilities behind one quiet, native menu instead of
            // adding a second branded control to the footer.
            LauncherUpwardMenuButton(
                actions: appMenuActions,
                isEnabled: appMenuActions.contains(where: \.isEnabled),
                onAction: onAction
            ) {
                Image(systemName: "gearshape")
                    .commandlyFont(size: 14, weight: .medium)
                    .foregroundStyle(.secondary)
                    .frame(width: density.iconSize - 2, height: density.iconSize - 2)
                    .accessibilityHidden(true)
            }
            .accessibilityIdentifier("launcher.settings-menu")
            .accessibilityLabel("Settings menu")
            .accessibilityHint("Includes Settings, Documentation, and Quit Commandly")
            .help("Settings menu")
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.xs))
        .frame(minHeight: LauncherChromeMetrics.footerHeight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.075))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Launcher footer")
    }
}

/// Command-surface footer: context title on the left, actions on the right.
struct LauncherFooterBar: View {
    let contextTitle: String
    let contextSystemImage: String
    let actions: [CommandActionDescriptor]
    var menuActions: [CommandActionDescriptor] = []
    @Binding var showsActionsMenu: Bool
    var onAction: (CommandActionID) -> Void
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        HStack(spacing: density.spacing(.xs)) {
            Image(systemName: contextSystemImage)
                .symbolVariant(.fill)
                .symbolRenderingMode(.monochrome)
                .commandlyFont(size: 12, weight: .semibold)
                .foregroundStyle(.secondary)
                .frame(width: density.iconSize - 4, height: density.iconSize - 4)
                .accessibilityHidden(true)

            Text(contextTitle)
                .commandlyFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: density.spacing(.sm))

            ForEach(actions) { action in
                if action.id == BuiltInCommandActionID.openActions {
                    LauncherUpwardMenuButton(
                        actions: menuActions,
                        isEnabled: action.isEnabled,
                        onAction: onAction
                    ) {
                        footerLabel(action)
                    }
                    .accessibilityLabel(action.title)
                } else if action.id == BuiltInCommandActionID.copy {
                    LauncherFooterCopyActionButton(
                        title: action.title,
                        keys: action.keyHint?.symbols ?? [],
                        isEnabled: action.isEnabled,
                        action: { onAction(action.id) }
                    )
                } else {
                    LauncherFooterActionButton(
                        title: action.title,
                        keys: action.keyHint?.symbols ?? [],
                        isEnabled: action.isEnabled,
                        action: { onAction(action.id) }
                    )
                }
            }
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.spacing(.xs))
        .frame(minHeight: LauncherChromeMetrics.footerHeight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.075))
                .frame(height: 1)
        }
    }
}

private func footerLabel(_ action: CommandActionDescriptor) -> some View {
    HStack(spacing: 6) {
        Text(action.title)
            .commandlyFont(size: 11, weight: .medium)
            .foregroundStyle(.secondary)
        if let keys = action.keyHint?.symbols {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .commandlyFont(size: 10, weight: .semibold, design: .rounded)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(LauncherPalette.surface)
                        )
                }
            }
        }
    }
}

/// Footer control that presents a native `NSMenu` above the anchor.
///
/// SwiftUI `Menu` with `.menuStyle(.borderlessButton)` often draws an empty
/// title strip at the top of the panel; AppKit avoids that and lets us pin the
/// menu above footer controls.
private struct LauncherUpwardMenuButton<Label: View>: View {
    let actions: [CommandActionDescriptor]
    var emptyPlaceholderTitle: String?
    var isEnabled: Bool = true
    let onAction: (CommandActionID) -> Void
    @ViewBuilder let label: () -> Label

    @State private var anchorView: NSView?
    @State private var menuBridge: LauncherUpwardMenuBridge?

    var body: some View {
        Button {
            presentMenu()
        } label: {
            label()
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(isEnabled == false)
        .opacity(isEnabled ? 1 : 0.45)
        .background {
            LauncherMenuAnchorViewReader(anchorView: $anchorView)
        }
    }

    private func presentMenu() {
        guard isEnabled, let anchorView else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let bridge = LauncherUpwardMenuBridge(onAction: onAction)
        menuBridge = bridge

        if actions.isEmpty, let emptyPlaceholderTitle {
            let item = NSMenuItem(title: emptyPlaceholderTitle, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for action in actions {
                if action.id == BuiltInCommandActionID.quit, menu.items.isEmpty == false {
                    menu.addItem(.separator())
                }
                let item = NSMenuItem(
                    title: action.title,
                    action: #selector(LauncherUpwardMenuBridge.selectItem(_:)),
                    keyEquivalent: keyEquivalent(for: action)
                )
                item.target = bridge
                item.representedObject = action.id.rawValue
                item.isEnabled = action.isEnabled
                if action.id == BuiltInCommandActionID.documentation {
                    item.keyEquivalentModifierMask = [.command]
                } else if action.id == BuiltInCommandActionID.settings
                    || action.id == BuiltInCommandActionID.quit
                {
                    item.keyEquivalentModifierMask = [.command]
                }
                menu.addItem(item)
            }
        }

        // Non-flipped coords: y grows up. Place the menu’s top-left so its bottom
        // sits just above the button.
        let menuHeight = menu.size.height
        let point = NSPoint(x: 0, y: anchorView.bounds.height + menuHeight)
        menu.popUp(positioning: nil, at: point, in: anchorView)
    }

    private func keyEquivalent(for action: CommandActionDescriptor) -> String {
        switch action.id {
        case BuiltInCommandActionID.documentation:
            return "?"
        case BuiltInCommandActionID.settings:
            return ","
        case BuiltInCommandActionID.quit:
            return "q"
        default:
            return ""
        }
    }
}

/// Captures the hosting `NSView` so AppKit menus can be positioned from SwiftUI.
private struct LauncherMenuAnchorViewReader: NSViewRepresentable {
    @Binding var anchorView: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            anchorView = view
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if anchorView !== nsView {
                anchorView = nsView
            }
        }
    }
}

/// Target for upward footer `NSMenuItem` actions.
private final class LauncherUpwardMenuBridge: NSObject {
    private let onAction: (CommandActionID) -> Void

    init(onAction: @escaping (CommandActionID) -> Void) {
        self.onAction = onAction
    }

    @objc func selectItem(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String else { return }
        onAction(CommandActionID(rawValue: rawValue))
    }
}

/// Shared clipboard→checkmark success morph timing for Copy controls.
@MainActor
enum CopySuccessFeedback {
    static let succeedSpring = Animation.spring(response: 0.32, dampingFraction: 0.68)
    static let revertSpring = Animation.spring(response: 0.28, dampingFraction: 0.78)
    static let visibleDuration: Duration = .milliseconds(900)

    static func runMorph(
        token: Int,
        didSucceed: Binding<Bool>,
        reduceMotion: Bool = false
    ) async {
        guard token > 0 else { return }
        withAnimation(reduceMotion ? nil : succeedSpring) {
            didSucceed.wrappedValue = true
        }
        try? await Task.sleep(for: visibleDuration)
        guard Task.isCancelled == false else { return }
        withAnimation(reduceMotion ? nil : revertSpring) {
            didSucceed.wrappedValue = false
        }
    }
}

private struct LauncherFooterActionButton: View {
    let title: String
    let keys: [String]
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            footerChrome(
                title: title,
                keys: keys,
                didSucceed: false,
                showsLeadingIcon: false,
                reduceMotion: false
            )
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(isEnabled == false)
        .accessibilityLabel(title)
    }
}

/// Footer Copy control with the same success morph as sidebar Copy.
private struct LauncherFooterCopyActionButton: View {
    let title: String
    let keys: [String]
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var didSucceed = false
    @State private var successToken = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            action()
            successToken += 1
        } label: {
            footerChrome(
                title: didSucceed ? "Copied" : title,
                keys: keys,
                didSucceed: didSucceed,
                showsLeadingIcon: true,
                reduceMotion: reduceMotion
            )
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(isEnabled == false)
        .animation(reduceMotion ? nil : CommandlyMotion.control, value: didSucceed)
        .task(id: successToken) {
            await CopySuccessFeedback.runMorph(
                token: successToken,
                didSucceed: $didSucceed,
                reduceMotion: reduceMotion
            )
        }
        .accessibilityLabel(didSucceed ? "Copied" : title)
    }
}

@ViewBuilder
private func footerChrome(
    title: String,
    keys: [String],
    didSucceed: Bool,
    showsLeadingIcon: Bool,
    reduceMotion: Bool
) -> some View {
    HStack(spacing: 6) {
        if showsLeadingIcon {
            Image(systemName: didSucceed ? "checkmark" : "doc.on.doc")
                .commandlyFont(size: 10, weight: .semibold)
                .foregroundStyle(didSucceed ? CommandlyTint.green.color : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: reduceMotion ? false : didSucceed)
        }

        Text(title)
            .commandlyFont(size: 11, weight: .medium)
            .foregroundStyle(didSucceed ? CommandlyTint.green.color : Color.primary)
            .contentTransition(.opacity)

        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .commandlyFont(size: 10, weight: .semibold, design: .rounded)
                    .foregroundStyle(didSucceed ? CommandlyTint.green.color : Color.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(didSucceed ? CommandlyTint.green.softFill : LauncherPalette.surface)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(
                                didSucceed
                                    ? CommandlyTint.green.color.opacity(0.32)
                                    : LauncherPalette.separator,
                                lineWidth: 1
                            )
                    }
            }
        }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .contentShape(Rectangle())
}

/// Captures secondary clicks so launcher result rows can open their actions panel.
struct LauncherRightClickCatcher: NSViewRepresentable {
    var onRightClick: () -> Void

    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.onRightClick = onRightClick
    }

    final class RightClickView: NSView {
        var onRightClick: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                installMonitorIfNeeded()
            } else {
                removeMonitor()
            }
        }

        private func installMonitorIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) {
                [weak self] event in
                guard let self, self.window != nil else { return event }
                let location = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(location) else { return event }
                self.onRightClick?()
                return nil
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

@ViewBuilder
func launcherItemIcon(icon: LauncherItemIcon, emphasized: Bool, size: CGFloat = 28) -> some View {
    switch icon {
    case .system(let systemName):
        launcherIcon(systemName: systemName, emphasized: emphasized, size: size)
    case .application(let path):
        ApplicationLauncherIcon(path: path, size: size)
    }
}

func launcherIcon(systemName: String, emphasized: Bool, size: CGFloat = 28) -> some View {
    LauncherGlyph(
        systemName: LauncherCommandArtwork.filledSymbol(for: systemName),
        tone: LauncherCommandArtwork.tone(for: systemName),
        isSelected: emphasized,
        size: size
    )
}

/// Renders an installed application's real icon from its `.app` bundle path.
struct ApplicationLauncherIcon: View {
    private let request: ApplicationIconRequest?
    var size: CGFloat = 28
    @State private var image: CGImage?

    init(path: String, size: CGFloat = 28) {
        self.request = ApplicationIconRequest(path: path)
        self.size = size
    }

    init(bundleIdentifier: String, size: CGFloat = 28) {
        self.request = ApplicationIconRequest(bundleIdentifier: bundleIdentifier)
        self.size = size
    }

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .commandlyFont(size: size * 0.46, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
        .task(id: request) {
            guard let request else {
                image = nil
                return
            }
            image = nil
            let loadedImage = await ApplicationIconCache.shared.image(for: request)
            guard Task.isCancelled == false else { return }
            image = loadedImage
        }
    }
}

nonisolated enum ApplicationIconRequest: Hashable, Sendable {
    case path(String)
    case bundleIdentifier(String)

    init?(path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        self = .path(URL(fileURLWithPath: trimmed).standardizedFileURL.path)
    }

    init?(bundleIdentifier: String) {
        let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        self = .bundleIdentifier(trimmed)
    }
}

nonisolated struct LoadedApplicationIcon: Sendable {
    let canonicalPath: String
    let image: CGImage
}

/// Shared bounded cache for fully rasterized workspace icons (paths only — never logs contents).
///
/// File-system access, bundle lookup, AppKit icon retrieval, and rasterization are confined to
/// this actor's executor. SwiftUI receives only the resulting sendable `CGImage` value.
actor ApplicationIconCache {
    typealias Loader = @Sendable (ApplicationIconRequest) -> LoadedApplicationIcon?

    static let shared = ApplicationIconCache()

    private nonisolated struct CachedImage {
        let image: CGImage
        let loadedAt: Date
        var lastAccessSequence: UInt64
    }

    private let cacheLifetime: TimeInterval
    private let failureRetryInterval: TimeInterval
    private let maximumEntryCount: Int
    private let now: @Sendable () -> Date
    private let loader: Loader
    private var imagesByCanonicalPath: [String: CachedImage] = [:]
    private var canonicalPathsByRequest: [ApplicationIconRequest: String] = [:]
    private var failedLoadsAt: [ApplicationIconRequest: Date] = [:]
    private var accessSequence: UInt64 = 0

    init(
        cacheLifetime: TimeInterval = 5 * 60,
        failureRetryInterval: TimeInterval = 15,
        maximumEntryCount: Int = 128,
        now: @escaping @Sendable () -> Date = Date.init,
        loader: @escaping Loader = ApplicationIconCache.loadWorkspaceIcon
    ) {
        self.cacheLifetime = max(0, cacheLifetime)
        self.failureRetryInterval = max(0, failureRetryInterval)
        self.maximumEntryCount = max(1, maximumEntryCount)
        self.now = now
        self.loader = loader
    }

    func image(for request: ApplicationIconRequest) -> CGImage? {
        guard Task.isCancelled == false else { return nil }
        let currentDate = now()
        evictExpiredEntries(at: currentDate)

        if let canonicalPath = canonicalPathsByRequest[request],
           var cached = imagesByCanonicalPath[canonicalPath] {
            if Self.isFresh(
                cached.loadedAt,
                at: currentDate,
                lifetime: cacheLifetime
            ) {
                cached.lastAccessSequence = nextAccessSequence()
                imagesByCanonicalPath[canonicalPath] = cached
                return cached.image
            }
            removeCanonicalPath(canonicalPath)
        }

        if case .path(let path) = request,
           var cached = imagesByCanonicalPath[path] {
            if Self.isFresh(
                cached.loadedAt,
                at: currentDate,
                lifetime: cacheLifetime
            ) {
                cached.lastAccessSequence = nextAccessSequence()
                imagesByCanonicalPath[path] = cached
                canonicalPathsByRequest[request] = path
                return cached.image
            }
            removeCanonicalPath(path)
        }

        if let failedAt = failedLoadsAt[request],
           Self.isFresh(
               failedAt,
               at: currentDate,
               lifetime: failureRetryInterval
           ) {
            return nil
        }

        guard let loaded = loader(request) else {
            failedLoadsAt[request] = currentDate
            evictExcessFailures()
            return nil
        }

        let canonicalPath = URL(fileURLWithPath: loaded.canonicalPath)
            .standardizedFileURL.path
        imagesByCanonicalPath[canonicalPath] = CachedImage(
            image: loaded.image,
            loadedAt: currentDate,
            lastAccessSequence: nextAccessSequence()
        )
        canonicalPathsByRequest[request] = canonicalPath
        if let pathRequest = ApplicationIconRequest(path: canonicalPath) {
            canonicalPathsByRequest[pathRequest] = canonicalPath
            failedLoadsAt.removeValue(forKey: pathRequest)
        }
        failedLoadsAt.removeValue(forKey: request)
        evictExcessImages()
        return loaded.image
    }

    /// Invalidates one bundle identifier so an install, removal, or update can be reflected now.
    func invalidate(bundleIdentifier: String) {
        guard let request = ApplicationIconRequest(bundleIdentifier: bundleIdentifier) else {
            return
        }
        invalidate(request)
    }

    /// Invalidates one application path so an install, removal, or update can be reflected now.
    func invalidate(path: String) {
        guard let request = ApplicationIconRequest(path: path) else { return }
        invalidate(request)
    }

    /// Clears all positive and negative icon entries, for example after an application scan.
    func invalidateAll() {
        imagesByCanonicalPath.removeAll(keepingCapacity: true)
        canonicalPathsByRequest.removeAll(keepingCapacity: true)
        failedLoadsAt.removeAll(keepingCapacity: true)
        accessSequence = 0
    }

    private func invalidate(_ request: ApplicationIconRequest) {
        failedLoadsAt.removeValue(forKey: request)
        guard let canonicalPath = canonicalPathsByRequest[request] else { return }
        removeCanonicalPath(canonicalPath)
    }

    private func removeCanonicalPath(_ canonicalPath: String) {
        imagesByCanonicalPath.removeValue(forKey: canonicalPath)
        let aliases = canonicalPathsByRequest.compactMap { request, path in
            path == canonicalPath ? request : nil
        }
        for alias in aliases {
            canonicalPathsByRequest.removeValue(forKey: alias)
        }
    }

    /// Sweeps TTL-expired positive and negative entries on each cache access. The cache is small
    /// and capacity-limited, so this keeps aliases fresh without a background timer.
    private func evictExpiredEntries(at currentDate: Date) {
        let expiredPaths = imagesByCanonicalPath.compactMap { path, cached in
            Self.isFresh(cached.loadedAt, at: currentDate, lifetime: cacheLifetime)
                ? nil : path
        }
        for path in expiredPaths {
            removeCanonicalPath(path)
        }
        failedLoadsAt = failedLoadsAt.filter { _, failedAt in
            Self.isFresh(
                failedAt,
                at: currentDate,
                lifetime: failureRetryInterval
            )
        }
    }

    private func evictExcessImages() {
        guard imagesByCanonicalPath.count > maximumEntryCount else { return }
        let excessCount = imagesByCanonicalPath.count - maximumEntryCount
        let leastRecentlyUsedPaths = imagesByCanonicalPath
            .sorted { lhs, rhs in
                if lhs.value.lastAccessSequence != rhs.value.lastAccessSequence {
                    return lhs.value.lastAccessSequence < rhs.value.lastAccessSequence
                }
                return lhs.key < rhs.key
            }
            .prefix(excessCount)
            .map(\.key)
        for path in leastRecentlyUsedPaths {
            removeCanonicalPath(path)
        }
    }

    private func nextAccessSequence() -> UInt64 {
        accessSequence &+= 1
        return accessSequence
    }

    private func evictExcessFailures() {
        guard failedLoadsAt.count > maximumEntryCount else { return }
        let excessCount = failedLoadsAt.count - maximumEntryCount
        let oldestRequests = failedLoadsAt
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                return String(describing: lhs.key) < String(describing: rhs.key)
            }
            .prefix(excessCount)
            .map(\.key)
        for request in oldestRequests {
            failedLoadsAt.removeValue(forKey: request)
        }
    }

    nonisolated private static func isFresh(
        _ cachedAt: Date,
        at currentDate: Date,
        lifetime: TimeInterval
    ) -> Bool {
        let age = currentDate.timeIntervalSince(cachedAt)
        return age >= 0 && age < lifetime
    }

    nonisolated private static func loadWorkspaceIcon(
        for request: ApplicationIconRequest
    ) -> LoadedApplicationIcon? {
        autoreleasepool {
            let path: String
            switch request {
            case .path(let requestedPath):
                guard FileManager.default.fileExists(atPath: requestedPath) else {
                    return nil
                }
                path = requestedPath
            case .bundleIdentifier(let bundleIdentifier):
                guard let applicationURL = NSWorkspace.shared.urlForApplication(
                    withBundleIdentifier: bundleIdentifier
                ) else {
                    return nil
                }
                path = applicationURL.standardizedFileURL.path
            }

            let icon = NSWorkspace.shared.icon(forFile: path)
            var proposedRect = NSRect(x: 0, y: 0, width: 128, height: 128)
            guard let sourceImage = icon.cgImage(
                forProposedRect: &proposedRect,
                context: nil,
                hints: nil
            ), let decodedImage = decodedImage(sourceImage, size: 128) else {
                return nil
            }
            return LoadedApplicationIcon(
                canonicalPath: path,
                image: decodedImage
            )
        }
    }

    nonisolated private static func decodedImage(
        _ sourceImage: CGImage,
        size: Int
    ) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(
            sourceImage,
            in: CGRect(x: 0, y: 0, width: size, height: size)
        )
        return context.makeImage()
    }
}
