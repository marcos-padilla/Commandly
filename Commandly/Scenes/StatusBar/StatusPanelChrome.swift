import DesignSystem
import SwiftUI

/// Shared surfaces and controls for the menu bar panel.
///
/// The panel sits over the menu bar's own material, so every fill here is a quiet overlay that
/// keeps that material visible instead of painting a second opaque background.
enum StatusPanelChrome {
    /// Corner radius of the panel's cards and grouped controls.
    static let cardCornerRadius: CGFloat = 12
    /// Corner radius of the small controls inside a card.
    static let controlCornerRadius: CGFloat = 8
    /// Width of the panel's content column.
    static let contentWidth: CGFloat = 320
    /// Height of one navigation tab.
    static let navigationTabHeight: CGFloat = 30
}

/// Card background used by every grouped block in the panel.
private struct StatusPanelCardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: StatusPanelChrome.cardCornerRadius, style: .continuous)
                    .fill(LauncherPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StatusPanelChrome.cardCornerRadius, style: .continuous)
                    .strokeBorder(LauncherPalette.separator, lineWidth: 1)
            )
    }
}

extension View {
    /// Wraps content in the panel's standard card.
    func statusPanelCard(padding: CGFloat = 12) -> some View {
        modifier(StatusPanelCardModifier(padding: padding))
    }
}

/// Uppercase heading shown above a section's body.
struct StatusPanelSectionHeader: View {
    let title: String
    var trailing: AnyView?

    init(_ title: String) {
        self.title = title
        self.trailing = nil
    }

    init<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(spacing: Spacing.xs.rawValue) {
            Text(title.uppercased())
                .commandlyFont(size: 10.5, weight: .semibold)
                .foregroundStyle(.secondary)
                .kerning(0.6)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
        }
    }
}

/// A labelled switch row inside a panel card.
struct StatusPanelToggleRow: View {
    let symbolName: String
    let title: String
    var caption: String?
    var captionIsWarning = false
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: Spacing.xs.rawValue) {
                Image(systemName: symbolName)
                    .commandlyFont(size: 11, weight: .medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 15)
                    .accessibilityHidden(true)
                Text(title)
                    .commandlyFont(size: 11, weight: .medium)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.xs.rawValue)
                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .accessibilityLabel(title)
            }
            if let caption {
                Text(caption)
                    .commandlyFont(size: 9.5)
                    .foregroundStyle(
                        captionIsWarning ? SemanticColors.color(for: .danger) : Color.secondary
                    )
                    .padding(.leading, 22)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A disclosure header that reveals more controls, used for the panel's Options blocks.
struct StatusPanelDisclosureHeader<Trailing: View>: View {
    private let title: String
    private let symbolName: String?
    @Binding private var isExpanded: Bool
    private let trailing: () -> Trailing

    init(
        title: String,
        symbolName: String? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.symbolName = symbolName
        self._isExpanded = isExpanded
        self.trailing = trailing
    }

    var body: some View {
        Button {
            withAnimation(CommandlyMotion.control) { isExpanded.toggle() }
        } label: {
            HStack(spacing: Spacing.xxs.rawValue + 3) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .commandlyFont(size: 11, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 15)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "chevron.right")
                        .commandlyFont(size: 9, weight: .bold)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .commandlyFont(size: 11.5, weight: .semibold)
                    .foregroundStyle(symbolName == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Spacer(minLength: 6)
                trailing()
                if symbolName != nil {
                    Image(systemName: "chevron.right")
                        .commandlyFont(size: 8.5, weight: .bold)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

extension StatusPanelDisclosureHeader where Trailing == EmptyView {
    init(title: String, symbolName: String? = nil, isExpanded: Binding<Bool>) {
        self.init(title: title, symbolName: symbolName, isExpanded: isExpanded) { EmptyView() }
    }
}

/// Small pill button used by the panel footer.
struct StatusPanelFooterButton: View {
    let title: String
    let symbolName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbolName)
                .commandlyFont(size: 11, weight: .medium)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, Spacing.xs.rawValue)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    RoundedRectangle(
                        cornerRadius: StatusPanelChrome.controlCornerRadius,
                        style: .continuous
                    )
                    .fill(LauncherPalette.surface)
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: StatusPanelChrome.controlCornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(LauncherPalette.separator, lineWidth: 1)
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: StatusPanelChrome.controlCornerRadius,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

/// A scroll view that reports its own height to the panel.
///
/// The menu bar panel's window sizes itself to its content, so it proposes no definite height to
/// what it contains. A plain `ScrollView` is greedy in that situation and collapses to nothing,
/// which leaves a section header sitting directly on the footer with the whole section missing.
/// Measuring the content and applying that height explicitly is what gives the window something
/// to size to.
///
/// The measurement cannot oscillate: the content's width is fixed, so its height does not depend
/// on the height this view ends up with. Sub-point changes are ignored anyway, so a fractional
/// re-measure cannot start a layout loop.
struct MeasuredScrollView<Content: View>: View {
    private let width: CGFloat
    private let maximumHeight: CGFloat
    private let estimatedHeight: CGFloat
    private let content: () -> Content
    @State private var measuredHeight: CGFloat?

    init(
        width: CGFloat,
        maximumHeight: CGFloat,
        estimatedHeight: CGFloat,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.width = width
        self.maximumHeight = maximumHeight
        self.estimatedHeight = estimatedHeight
        self.content = content
    }

    var body: some View {
        ScrollView(.vertical) {
            content()
                .frame(width: width, alignment: .leading)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: StatusPanelContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: width, height: resolvedHeight)
        .onPreferenceChange(StatusPanelContentHeightKey.self) { height in
            // Until the first real measurement arrives the estimate stands in, so a section never
            // flashes at zero height while it is being laid out.
            guard height > 0 else { return }
            guard let measuredHeight else {
                self.measuredHeight = height
                return
            }
            guard abs(measuredHeight - height) > 0.5 else { return }
            self.measuredHeight = height
        }
    }

    private var resolvedHeight: CGFloat {
        min(max(measuredHeight ?? estimatedHeight, 1), maximumHeight)
    }
}

/// Carries a section's measured content height up to the scroll container.
private struct StatusPanelContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
