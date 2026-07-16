import DesignSystem
import SwiftUI

/// Reusable search/filter/sidebar/detail composition for launcher applications.
///
/// Applications with a different interaction model can provide their own surface without using
/// this view. Applications that share the standard browser layout get identical focus, keyboard,
/// sizing, and semantic chrome behavior from one implementation.
struct LauncherApplicationScreen<FilterControl: View, Sidebar: View, Detail: View>: View {
    @Binding private var query: String
    @FocusState private var isSearchFocused: Bool
    @State private var isSearchHovered = false

    private let searchPlaceholder: String
    private let searchAccessibilityIdentifier: String
    private let sidebarWidth: CGFloat
    private let onBack: () -> Void
    private let onSubmit: () -> Void
    private let onMoveSelection: (Int) -> Void
    private let onEscape: () -> Void
    private let filterControl: FilterControl
    private let sidebar: Sidebar
    private let detail: Detail

    init(
        query: Binding<String>,
        searchPlaceholder: String,
        searchAccessibilityIdentifier: String = "launcher-application-query",
        sidebarWidth: CGFloat = 270,
        onBack: @escaping () -> Void,
        onSubmit: @escaping () -> Void,
        onMoveSelection: @escaping (Int) -> Void,
        onEscape: @escaping () -> Void,
        @ViewBuilder filterControl: () -> FilterControl,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        _query = query
        self.searchPlaceholder = searchPlaceholder
        self.searchAccessibilityIdentifier = searchAccessibilityIdentifier
        self.sidebarWidth = sidebarWidth
        self.onBack = onBack
        self.onSubmit = onSubmit
        self.onMoveSelection = onMoveSelection
        self.onEscape = onEscape
        self.filterControl = filterControl()
        self.sidebar = sidebar()
        self.detail = detail()
    }

    var body: some View {
        VStack(spacing: 0) {
            LauncherApplicationHeader(
                query: $query,
                searchPlaceholder: searchPlaceholder,
                searchAccessibilityIdentifier: searchAccessibilityIdentifier,
                isSearchFocused: $isSearchFocused,
                isSearchHovered: $isSearchHovered,
                onBack: onBack,
                onSubmit: onSubmit,
                onMoveSelection: onMoveSelection,
                onEscape: onEscape,
                filterControl: filterControl
            )

            HStack(spacing: 0) {
                sidebar
                    .frame(width: sidebarWidth)
                    .layoutPriority(1)
                    .background(Color.primary.opacity(0.025))
                    .clipped()

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(0)
                    .background(Color.clear)
                    .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            isSearchFocused = true
        }
    }
}

private struct LauncherApplicationHeader<FilterControl: View>: View {
    @Binding var query: String
    let searchPlaceholder: String
    let searchAccessibilityIdentifier: String
    let isSearchFocused: FocusState<Bool>.Binding
    @Binding var isSearchHovered: Bool
    let onBack: () -> Void
    let onSubmit: () -> Void
    let onMoveSelection: (Int) -> Void
    let onEscape: () -> Void
    let filterControl: FilterControl

    @Environment(\.commandlyLayoutDensity) private var density
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: density.spacing(.sm)) {
            CommandlyBackButton(action: onBack)

            HStack(spacing: density.spacing(.xs)) {
                Image(systemName: "magnifyingglass")
                    .symbolVariant(.none)
                    .commandlyFont(size: 13, weight: .medium)
                    .foregroundStyle(
                        isSearchFocused.wrappedValue ? Color.primary : Color.secondary
                    )

                TextField(searchPlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .commandlyFont(size: 14, weight: .medium)
                    .focused(isSearchFocused)
                    .accessibilityIdentifier(searchAccessibilityIdentifier)
                    .onSubmit(onSubmit)
                    .onKeyPress(.upArrow) {
                        onMoveSelection(-1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        onMoveSelection(1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        onEscape()
                        return .handled
                    }

                if query.isEmpty == false {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .commandlyFont(size: 12)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, density.spacing(.sm))
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .contentShape(
                RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.lg.rawValue, style: .continuous)
                    .strokeBorder(searchStroke, lineWidth: 1)
            }
            .onHover { isSearchHovered = $0 }
            .onTapGesture {
                isSearchFocused.wrappedValue = true
            }
            .animation(reduceMotion ? nil : CommandlyMotion.hover, value: isSearchHovered)
            .animation(
                reduceMotion ? nil : CommandlyMotion.hover,
                value: isSearchFocused.wrappedValue
            )
            .accessibilityElement(children: .contain)
            .layoutPriority(1)

            filterControl
                .fixedSize(horizontal: true, vertical: false)
                .zIndex(30)
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.top, density.spacing(.sm))
        .padding(.bottom, density.spacing(.xs))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.075))
                .frame(height: 1)
        }
        .zIndex(20)
    }

    private var searchStroke: Color {
        if isSearchFocused.wrappedValue {
            return Color.primary.opacity(0.28)
        }
        return Color.primary.opacity(isSearchHovered ? 0.16 : 0.09)
    }
}

/// Shared selection and pointer chrome for rows in application sidebars.
struct LauncherApplicationRow<Label: View, Accessory: View>: View {
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: (() -> Void)?
    let onContextAction: (() -> Void)?
    let onHoverChange: (Bool) -> Void
    let label: Label
    let accessory: Accessory

    @Environment(\.commandlyLayoutDensity) private var density

    init(
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onOpen: (() -> Void)? = nil,
        onContextAction: (() -> Void)? = nil,
        onHoverChange: @escaping (Bool) -> Void,
        @ViewBuilder label: () -> Label,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onOpen = onOpen
        self.onContextAction = onContextAction
        self.onHoverChange = onHoverChange
        self.label = label()
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: density.spacing(.sm)) {
            Button(action: onSelect) {
                label
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            accessory
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onOpen?()
            }
        )
        .padding(.horizontal, density.spacing(.sm))
        .padding(.vertical, density.rowVerticalPadding)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.md.rawValue, style: .continuous)
                .fill(isSelected ? Color.primary.opacity(0.105) : Color.clear)
        }
        .padding(.horizontal, density.spacing(.xs))
        .background {
            if let onContextAction {
                LauncherRightClickCatcher(onRightClick: onContextAction)
            }
        }
        .onHover(perform: onHoverChange)
    }
}

struct LauncherApplicationEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Spacing.xs.rawValue) {
            Image(systemName: systemImage)
                .commandlyFont(size: 25, weight: .medium)
                .foregroundStyle(.tertiary)
            Text(title)
                .commandlyFont(size: 12, weight: .semibold)
            Text(message)
                .commandlyFont(size: 10)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.md.rawValue)
        .accessibilityElement(children: .combine)
    }
}

struct LauncherApplicationMetadataRow: View {
    let label: String
    let value: String
    var labelWidth: CGFloat = 62
    var fontSize: CGFloat = 11
    var truncatesValue = true

    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: density.spacing(.sm)) {
            Text(label)
                .commandlyFont(size: fontSize, weight: .semibold)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .commandlyFont(size: fontSize, weight: .medium)
                .lineLimit(truncatesValue ? 1 : nil)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
