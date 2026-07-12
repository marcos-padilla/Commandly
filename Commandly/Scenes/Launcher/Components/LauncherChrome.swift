import SwiftUI
import DesignSystem
import CommandKit
import AppKit

struct LauncherSearchField: View {
    @Binding var query: String
    var autocompleteSuffix: String = ""
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
                .accessibilityHidden(true)

            ZStack(alignment: .leading) {
                if autocompleteSuffix.isEmpty == false, query.isEmpty == false {
                    Text(query + autocompleteSuffix)
                        .commandlyFont(size: 16, weight: .medium)
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
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.vertical, density.searchVerticalPadding)
        .onAppear {
            isFocused = true
        }
        .onChange(of: focusEpoch) { _, _ in
            isFocused = true
        }
    }
}

struct LauncherSectionHeader: View {
    let title: String
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        Text(title.uppercased())
            .commandlyFont(size: 10, weight: .semibold)
            .foregroundStyle(.tertiary)
            .tracking(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, density.spacing(.md))
            .padding(.top, density.sectionHeaderTopPadding)
            .padding(.bottom, density.spacing(.xxs))
            .accessibilityAddTraits(.isHeader)
    }
}

struct LauncherResultRow: View {
    let item: LauncherItem
    let isSelected: Bool
    var onHoverChange: ((Bool) -> Void)?
    let action: () -> Void
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        Button(action: action) {
            HStack(spacing: density.spacing(.sm)) {
                launcherItemIcon(
                    icon: item.icon,
                    emphasized: isSelected,
                    size: density.iconSize
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .commandlyFont(size: 13, weight: .medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .commandlyFont(size: 11, weight: .regular)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: density.spacing(.xs))

                Text(item.badge.title)
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, density.rowHorizontalPadding)
            .padding(.vertical, density.rowVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                    .fill(isSelected ? BrandPalette.accent.opacity(0.22) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, density.spacing(.xs))
        .onHover { hovering in
            onHoverChange?(hovering)
        }
        .accessibilityLabel("\(item.title), \(item.badge.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct LauncherFooterBar: View {
    let contextTitle: String
    let contextSystemImage: String
    let actions: [CommandActionDescriptor]
    var menuActions: [CommandActionDescriptor] = []
    @Binding var showsActionsMenu: Bool
    var onAction: (CommandActionID) -> Void
    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        HStack(spacing: density.spacing(.sm)) {
            Image(systemName: contextSystemImage)
                .commandlyFont(size: 12, weight: .semibold)
                .foregroundStyle(BrandPalette.accentSoft)
                .frame(width: density.iconSize - 6, height: density.iconSize - 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(BrandPalette.accent.opacity(0.18))
                )
                .accessibilityHidden(true)

            Text(contextTitle)
                .commandlyFont(size: 11, weight: .semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: density.spacing(.sm))

            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                if index > 0 {
                    footerDivider
                }

                if action.id == BuiltInCommandActionID.openActions {
                    Menu {
                        ForEach(menuActions) { menuAction in
                            Button(menuAction.title) {
                                onAction(menuAction.id)
                            }
                            .disabled(menuAction.isEnabled == false)
                        }
                    } label: {
                        footerLabel(action)
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(action.isEnabled == false)
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
        .padding(.vertical, density.spacing(.sm))
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var footerDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 14)
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
                                    .fill(Color.primary.opacity(0.08))
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
        didSucceed: Binding<Bool>
    ) async {
        guard token > 0 else { return }
        withAnimation(succeedSpring) {
            didSucceed.wrappedValue = true
        }
        try? await Task.sleep(for: visibleDuration)
        guard Task.isCancelled == false else { return }
        withAnimation(revertSpring) {
            didSucceed.wrappedValue = false
        }
    }
}

private struct LauncherFooterActionButton: View {
    let title: String
    let keys: [String]
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            footerChrome(
                title: title,
                keys: keys,
                isHovered: isHovered,
                isPressed: isPressed,
                didSucceed: false,
                showsLeadingIcon: false
            )
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
        .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: isPressed)
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(title)
    }
}

/// Footer Copy control with the same success morph as sidebar Copy.
private struct LauncherFooterCopyActionButton: View {
    let title: String
    let keys: [String]
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false
    @State private var didSucceed = false
    @State private var successToken = 0

    var body: some View {
        Button {
            action()
            successToken += 1
        } label: {
            footerChrome(
                title: didSucceed ? "Copied" : title,
                keys: keys,
                isHovered: isHovered,
                isPressed: isPressed,
                didSucceed: didSucceed,
                showsLeadingIcon: true
            )
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
        .animation(CopySuccessFeedback.succeedSpring, value: didSucceed)
        .animation(.easeOut(duration: MotionDuration.fast.rawValue), value: isPressed)
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .task(id: successToken) {
            await CopySuccessFeedback.runMorph(token: successToken, didSucceed: $didSucceed)
        }
        .accessibilityLabel(didSucceed ? "Copied" : title)
    }
}

@ViewBuilder
private func footerChrome(
    title: String,
    keys: [String],
    isHovered: Bool,
    isPressed: Bool,
    didSucceed: Bool,
    showsLeadingIcon: Bool
) -> some View {
    HStack(spacing: 6) {
        if showsLeadingIcon {
            Image(systemName: didSucceed ? "checkmark" : "doc.on.doc")
                .commandlyFont(size: 10, weight: .semibold)
                .foregroundStyle(
                    didSucceed
                        ? BrandPalette.accentSoft
                        : (isHovered ? Color.primary : Color.secondary)
                )
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: didSucceed)
        }

        Text(title)
            .commandlyFont(size: 11, weight: .medium)
            .foregroundStyle(
                didSucceed
                    ? BrandPalette.accentSoft
                    : (isHovered ? Color.primary : Color.secondary)
            )
            .contentTransition(.opacity)

        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .commandlyFont(size: 10, weight: .semibold, design: .rounded)
                    .foregroundStyle(
                        didSucceed || isHovered ? BrandPalette.accentSoft : Color.secondary
                    )
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                didSucceed || isHovered
                                    ? BrandPalette.accent.opacity(0.22)
                                    : Color.primary.opacity(0.08)
                            )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(
                                BrandPalette.accent.opacity(didSucceed || isHovered ? 0.35 : 0),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: BrandPalette.accent.opacity(isHovered && didSucceed == false ? 0.28 : 0),
                        radius: isHovered && didSucceed == false ? 6 : 0,
                        y: isHovered && didSucceed == false ? 1 : 0
                    )
            }
        }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(
                didSucceed
                    ? BrandPalette.accent.opacity(0.16)
                    : (isHovered ? BrandPalette.accent.opacity(0.12) : Color.clear)
            )
    )
    .overlay {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(
                BrandPalette.accent.opacity(didSucceed ? 0.28 : (isHovered ? 0.22 : 0)),
                lineWidth: 1
            )
    }
    .scaleEffect(isPressed ? 0.97 : (isHovered || didSucceed ? 1.03 : 1))
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
    Image(systemName: systemName)
        .commandlyFont(size: size * 0.46, weight: .semibold)
        .foregroundStyle(emphasized ? Color.white : BrandPalette.accentSoft)
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    emphasized
                        ? BrandPalette.accent
                        : BrandPalette.accent.opacity(0.16)
                )
        )
        .accessibilityHidden(true)
}

/// Renders an installed application's real icon from its `.app` bundle path.
struct ApplicationLauncherIcon: View {
    let path: String
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let image = ApplicationIconCache.shared.icon(forPath: path) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .commandlyFont(size: size * 0.46, weight: .semibold)
                    .foregroundStyle(BrandPalette.accentSoft)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Small in-memory cache for workspace app icons (paths only — never logs contents).
@MainActor
final class ApplicationIconCache {
    static let shared = ApplicationIconCache()

    private var images: [String: NSImage] = [:]

    func icon(forPath path: String) -> NSImage? {
        if let cached = images[path] {
            return cached
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 128, height: 128)
        images[path] = icon
        return icon
    }
}
