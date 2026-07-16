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
    let onBack: () -> Void
    let onSubmit: () -> Void
    let onMoveSelection: (Int) -> Void
    let onEscape: () -> Void
    let filterControl: FilterControl

    @Environment(\.commandlyLayoutDensity) private var density

    var body: some View {
        HStack(spacing: density.spacing(.sm)) {
            CommandlyBackButton(action: onBack)

            HStack(spacing: density.spacing(.sm)) {
                Image(systemName: "magnifyingglass")
                    .symbolVariant(.none)
                    .commandlyFont(size: 15, weight: .medium)
                    .foregroundStyle(.secondary)
                    .frame(width: density.iconSize, height: density.iconSize)
                    .accessibilityHidden(true)

                TextField(searchPlaceholder, text: $query)
                    .textFieldStyle(.plain)
                    .commandlyFont(size: 16, weight: .medium)
                    .focused(isSearchFocused)
                    .accessibilityLabel(searchPlaceholder)
                    .accessibilityValue(query)
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
                            .commandlyFont(size: 14, weight: .regular)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            // Search belongs to the application canvas. Keeping it unfilled and borderless
            // matches the root launcher while the full row remains a generous focus target.
            .padding(.vertical, density.searchVerticalPadding)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                isSearchFocused.wrappedValue = true
            }
            .accessibilityElement(children: .contain)
            .layoutPriority(1)

            filterControl
                .fixedSize(horizontal: true, vertical: false)
                .zIndex(30)
        }
        .padding(.horizontal, density.spacing(.md))
        .padding(.top, density.spacing(.xs))
        .padding(.bottom, density.spacing(.xxs))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.075))
                .frame(height: 1)
        }
        .zIndex(20)
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
